package net.v2boxkit.v2boxkit_client

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicReference

object TunnelEventBus {
    private val handler = Handler(Looper.getMainLooper())
    private val status = AtomicReference("disconnected")

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(value: EventChannel.EventSink?) {
        sink = value
        emit(status.get())
    }

    fun detach() {
        sink = null
    }

    fun emit(value: String, message: String? = null) {
        status.set(value)
        val event =
            mutableMapOf<String, Any?>(
                "status" to value,
            ).apply {
                if (message != null) put("message", message)
            }
        handler.post { sink?.success(event) }
    }

    fun isRunning(): Boolean = status.get() in setOf("connecting", "connected")
}
