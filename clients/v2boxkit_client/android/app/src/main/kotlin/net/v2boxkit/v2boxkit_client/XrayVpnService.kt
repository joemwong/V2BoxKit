package net.v2boxkit.v2boxkit_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import java.net.InetAddress
import java.util.concurrent.Executors
import libXray.DialerController
import libXray.LibXray
import org.json.JSONObject

class XrayVpnService :
    VpnService(),
    DialerController {
    private val executor = Executors.newSingleThreadExecutor()
    private var tunFileDescriptor = -1

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_STOP -> executor.execute { stopRuntime(stopService = true) }
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, buildNotification("连接中"))
                val config = intent.getStringExtra(EXTRA_CONFIG)
                val mtu = intent.getIntExtra(EXTRA_MTU, 1500)
                val dns = intent.getStringExtra(EXTRA_DNS) ?: "1.1.1.1"
                if (config.isNullOrBlank()) {
                    TunnelEventBus.emit("error", "Missing Xray configuration")
                    executor.execute { stopRuntime(stopService = true, emitEvent = false) }
                } else {
                    executor.execute { startRuntime(config, mtu, dns) }
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun startRuntime(
        rawConfig: String,
        mtu: Int,
        dns: String,
    ) {
        TunnelEventBus.emit("connecting")
        try {
            stopRuntime(stopService = false, emitEvent = false)
            val dnsAddress = resolveDnsAddress(dns)
            val dnsEndpoint =
                if (dnsAddress.contains(':')) "[$dnsAddress]:53" else "$dnsAddress:53"
            val vpn =
                Builder()
                    .setSession("V2BoxKit")
                    .setMtu(mtu.coerceIn(1280, 1500))
                    .addAddress("172.19.0.2", 30)
                    .addAddress("fd00:172:19::2", 64)
                    .addRoute("0.0.0.0", 0)
                    .addRoute("::", 0)
                    .addDnsServer(dnsAddress)
                    .setBlocking(false)
                    .establish()
                    ?: error("Android did not create the VPN interface")

            tunFileDescriptor = vpn.detachFd()
            LibXray.registerDialerController(this)
            LibXray.registerListenerController(this)
            LibXray.setDNS(this, dnsEndpoint)

            val configuration = JSONObject(rawConfig)
            val environment = configuration.optJSONObject("env") ?: JSONObject()
            environment.put("xray.tun.fd", tunFileDescriptor.toString())
            configuration.put("env", environment)

            val request =
                JSONObject()
                    .put("apiVersion", 1)
                    .put("method", "runXrayFromJson")
                    .put(
                        "payload",
                        JSONObject().put("configJSON", configuration.toString()),
                    )
            val response = JSONObject(LibXray.invoke(request.toString()))
            if (!response.optBoolean("success", false)) {
                error(response.optString("error", "Xray failed to start"))
            }

            TunnelEventBus.emit("connected")
            updateNotification("已连接")
        } catch (error: Throwable) {
            TunnelEventBus.emit("error", error.message ?: error.toString())
            stopRuntime(stopService = true, emitEvent = false)
        }
    }

    private fun stopRuntime(
        stopService: Boolean,
        emitEvent: Boolean = true,
    ) {
        if (emitEvent) TunnelEventBus.emit("disconnecting")
        try {
            val request =
                JSONObject()
                    .put("apiVersion", 1)
                    .put("method", "stopXray")
                    .put("payload", JSONObject())
            LibXray.invoke(request.toString())
        } catch (_: Throwable) {
            // Closing the TUN still restores the operating system network.
        }
        try {
            LibXray.resetDNS()
        } catch (_: Throwable) {
            // Resolver may not have been installed when startup failed.
        }
        if (tunFileDescriptor >= 0) {
            try {
                ParcelFileDescriptor.adoptFd(tunFileDescriptor).close()
            } catch (_: Throwable) {
                // File descriptor may already have been invalidated by Android.
            }
            tunFileDescriptor = -1
        }
        if (emitEvent) TunnelEventBus.emit("disconnected")
        if (stopService) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            stopSelf()
        }
    }

    override fun protectFd(fd: Long): Boolean = protect(fd.toInt())

    override fun onRevoke() {
        executor.execute { stopRuntime(stopService = true) }
        super.onRevoke()
    }

    override fun onDestroy() {
        stopRuntime(stopService = false, emitEvent = false)
        executor.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    private fun resolveDnsAddress(value: String): String {
        return try {
            val normalized = value.trim()
            val host =
                when {
                    normalized.contains("://") ->
                        Uri.parse(normalized).host ?: "1.1.1.1"
                    normalized.startsWith("[") ->
                        normalized.substringAfter('[').substringBefore(']')
                    normalized.count { it == ':' } == 1 ->
                        normalized.substringBefore(':')
                    else -> normalized
                }
            InetAddress.getByName(host.ifBlank { "1.1.1.1" }).hostAddress
                ?: "1.1.1.1"
        } catch (_: Throwable) {
            "1.1.1.1"
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel =
            NotificationChannel(
                NOTIFICATION_CHANNEL,
                "VPN 连接",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "显示 V2BoxKit 系统 VPN 的运行状态"
                setShowBadge(false)
            }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java)
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
                .setContentTitle("V2BoxKit")
                .setContentText(text)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("V2BoxKit")
                .setContentText(text)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()
        }
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID, buildNotification(text))
    }

    companion object {
        const val ACTION_START = "net.v2boxkit.action.START"
        const val ACTION_STOP = "net.v2boxkit.action.STOP"
        const val EXTRA_CONFIG = "config"
        const val EXTRA_MTU = "mtu"
        const val EXTRA_DNS = "dns"
        private const val NOTIFICATION_CHANNEL = "v2boxkit_vpn"
        private const val NOTIFICATION_ID = 17021
    }
}
