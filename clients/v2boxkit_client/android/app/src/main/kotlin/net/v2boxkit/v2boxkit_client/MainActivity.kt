package net.v2boxkit.v2boxkit_client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import libXray.LibXray
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(::handleMethod)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    TunnelEventBus.attach(sink)
                }

                override fun onCancel(arguments: Any?) {
                    TunnelEventBus.detach()
                }
            },
        )
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> prepareVpn(result)
            "start" -> startVpn(call, result)
            "stop" -> stopVpn(result)
            "isRunning" -> result.success(TunnelEventBus.isRunning())
            "invoke" -> invokeXray(call, result)
            else -> result.notImplemented()
        }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        if (pendingPermissionResult != null) {
            result.error("permission_pending", "VPN permission is already pending", null)
            return
        }
        val intent = VpnService.prepare(this)
        if (intent == null) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(intent, VPN_PERMISSION_REQUEST)
    }

    @Deprecated("Used for VpnService permission compatibility with FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != VPN_PERMISSION_REQUEST) return

        val granted =
            resultCode == Activity.RESULT_OK || VpnService.prepare(this) == null
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun startVpn(call: MethodCall, result: MethodChannel.Result) {
        if (VpnService.prepare(this) != null) {
            result.error("vpn_permission", "VPN permission has not been granted", null)
            return
        }
        val config = call.argument<String>("config")
        if (config.isNullOrBlank()) {
            result.error("missing_config", "Missing Xray configuration", null)
            return
        }
        val intent =
            Intent(this, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_START
                putExtra(XrayVpnService.EXTRA_CONFIG, config)
                putExtra(XrayVpnService.EXTRA_MTU, call.argument<Int>("mtu") ?: 1500)
                putExtra(
                    XrayVpnService.EXTRA_DNS,
                    call.argument<String>("dnsServer") ?: "1.1.1.1",
                )
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(null)
    }

    private fun stopVpn(result: MethodChannel.Result) {
        val intent =
            Intent(this, XrayVpnService::class.java).apply {
                action = XrayVpnService.ACTION_STOP
            }
        startService(intent)
        result.success(null)
    }

    private fun invokeXray(call: MethodCall, result: MethodChannel.Result) {
        val method = call.argument<String>("method")
        if (method.isNullOrBlank()) {
            result.error("missing_method", "Missing libXray method", null)
            return
        }
        val payload = call.argument<Map<String, Any?>>("payload") ?: emptyMap()
        executor.execute {
            try {
                val request =
                    JSONObject()
                        .put("apiVersion", 1)
                        .put("method", method)
                        .put("payload", JSONObject(payload))
                val response = JSONObject(LibXray.invoke(request.toString())).toMap()
                mainHandler.post { result.success(response) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("libxray", error.message ?: error.toString(), null)
                }
            }
        }
    }

    override fun onDestroy() {
        executor.shutdown()
        pendingPermissionResult?.error(
            "activity_destroyed",
            "Activity was destroyed while waiting for VPN permission",
            null,
        )
        pendingPermissionResult = null
        super.onDestroy()
    }

    companion object {
        private const val VPN_PERMISSION_REQUEST = 7001
        private const val METHOD_CHANNEL = "net.v2boxkit/tunnel"
        private const val EVENT_CHANNEL = "net.v2boxkit/tunnel-events"
    }
}

private fun JSONObject.toMap(): Map<String, Any?> {
    val result = mutableMapOf<String, Any?>()
    val iterator = keys()
    while (iterator.hasNext()) {
        val key = iterator.next()
        result[key] = jsonValueToKotlin(opt(key))
    }
    return result
}

private fun jsonValueToKotlin(value: Any?): Any? =
    when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.toMap()
        is JSONArray -> List(value.length()) { index -> jsonValueToKotlin(value.opt(index)) }
        else -> value
    }
