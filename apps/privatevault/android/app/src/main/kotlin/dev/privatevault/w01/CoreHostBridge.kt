package dev.privatevault.w01

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Main-process state owns monotonic revisions across fresh core processes. */
internal class CoreHostBridge(private val context: Context, messenger: BinaryMessenger) {
    private val handler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "dev.privatevault.w01/core")
    private val events = EventChannel(messenger, "dev.privatevault.w01/core_events")
    private var sink: EventChannel.EventSink? = null
    private var revision = 0L
    private var generation = 0L
    private var instance = ""
    private var phase = "stopped"
    private var value: Map<String, Any> = mapOf("phase" to phase, "message" to "本机服务尚未启动", "revision" to revision)
    private var foreground = false
    private var closed = false
    private var connection: ServiceConnection? = null
    private var remote: Messenger? = null
    private var remoteDeath: IBinder.DeathRecipient? = null
    private var stoppedAcknowledged = false
    private val repliesGate = CoreReplyGate()
    private val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (!closed && message.sendingUid == Process.myUid() && message.what == CoreProtocol.STATE &&
            repliesGate.accepts(message.data.getString("instance"), message.data.getLong("generation", -1))) accept(message.data)
        true
    })

    init {
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "snapshot" -> Unit
                "start" -> start()
                "stop" -> stop()
                "read_fixture" -> if (phase == "ready") send(CoreProtocol.READ)
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            result.success(value)
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, listener: EventChannel.EventSink) { sink = listener; listener.success(value) }
            override fun onCancel(arguments: Any?) { sink = null }
        })
    }

    fun setForeground(active: Boolean) {
        foreground = active
        if (!active) stop()
    }

    private fun update(next: String, message: String, extra: Map<String, Any> = emptyMap()) {
        phase = next
        revision++
        value = mapOf("phase" to next, "message" to message, "revision" to revision) + extra
        sink?.success(value)
    }

    private fun fail() {
        release()
        update("failed", "本机服务已中断，可以重新启动。", mapOf("errorCode" to "core_service_unavailable"))
    }

    private fun start() {
        if (closed || phase in listOf("starting", "ready", "stopping")) return
        if (!foreground) { update("stopped", "请回到应用前台后启动本机服务。"); return }
        release()
        generation++
        instance = UUID.randomUUID().toString()
        repliesGate.open(instance, generation)
        stoppedAcknowledged = false
        val expected = generation
        update("starting", "正在准备本机服务并检查测试图片…")
        val owned = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                if (connection !== this || generation != expected || phase != "starting" || !foreground) return
                remote = Messenger(binder)
                remoteDeath = IBinder.DeathRecipient {
                    handler.post { if (connection === this) disconnected() }
                }
                try { binder.linkToDeath(remoteDeath!!, 0) } catch (_: Exception) { fail(); return }
                send(CoreProtocol.START)
            }
            private fun disconnected() {
                if (phase == "stopping" && stoppedAcknowledged) { release(); update("stopped", "本机服务已停止。") } else fail()
            }
            override fun onServiceDisconnected(name: ComponentName) {
                if (connection === this && generation == expected) disconnected()
            }
            override fun onBindingDied(name: ComponentName) { if (connection === this) fail() }
            override fun onNullBinding(name: ComponentName) { if (connection === this) fail() }
        }
        connection = owned
        try {
            if (!context.bindService(Intent(context, CoreService::class.java), owned, Context.BIND_AUTO_CREATE)) fail()
        } catch (_: Exception) { fail() }
        handler.postDelayed({ if (generation == expected && phase == "starting") { send(CoreProtocol.STOP); fail() } }, 35000)
    }

    private fun send(command: Int) {
        val target = remote ?: return
        try {
            target.send(Message.obtain(null, command).apply {
                data = CoreProtocol.ticket(instance, generation); replyTo = replies
            })
        } catch (_: Exception) {
            fail()
        }
    }

    private fun stop() {
        if (phase == "stopped" || closed) return
        val expected = generation
        update("stopping", "正在停止本机服务…")
        if (remote == null) { release(); update("stopped", "启动已取消，本机服务已停止。"); return }
        send(CoreProtocol.STOP)
        handler.postDelayed({ if (generation == expected && phase == "stopping") fail() }, 6000)
    }

    private fun accept(data: Bundle) {
        when (data.getString("phase")) {
            "ready" -> {
                if (phase !in listOf("starting", "ready") || !foreground) return
                val bytes = data.getByteArray("bytes") ?: return fail()
                if (bytes.size != 14415 || data.getString("sha256") != CoreProtocol.DIGEST ||
                    data.getString("version") != CoreProtocol.VERSION) return fail()
                update("ready", "本机服务与测试图片检查通过。", mapOf(
                    "version" to CoreProtocol.VERSION,
                    "fixture" to mapOf("name" to "样本.png", "byteLength" to bytes.size,
                        "sha256" to CoreProtocol.DIGEST, "bytesBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP))))
            }
            "stopped" -> {
                if (phase == "stopping") stoppedAcknowledged = true
                // Wait for the owned Binder to die before a new start is allowed.
            }
            "failed" -> fail()
        }
    }

    private fun release() {
        repliesGate.close()
        val death = remoteDeath
        if (death != null) try { remote?.binder?.unlinkToDeath(death, 0) } catch (_: Exception) { }
        remoteDeath = null
        remote = null
        val owned = connection
        connection = null
        if (owned != null) try { context.unbindService(owned) } catch (_: IllegalArgumentException) { }
    }

    fun close() {
        if (closed) return
        stop(); closed = true
        release(); handler.removeCallbacksAndMessages(null)
        methods.setMethodCallHandler(null); events.setStreamHandler(null); sink = null
    }
}
