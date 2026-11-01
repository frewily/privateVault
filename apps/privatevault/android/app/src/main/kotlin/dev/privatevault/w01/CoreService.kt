package dev.privatevault.w01

import android.app.Application
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** Bound only to the foreground UI; no persistent/background service. */
class CoreService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val workerThread = HandlerThread("pv-core-control")
    private lateinit var worker: Handler
    private var owner: Messenger? = null
    private var death: IBinder.DeathRecipient? = null
    private var instance = ""
    private var generation = -1L
    private var processVerified = false
    private var adapter: GoCoreAdapter? = null
    private val cancelled = AtomicBoolean(false)
    private val dying = AtomicBoolean(false)
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (processVerified && message.sendingUid == Process.myUid()) receive(message)
        true
    })

    override fun onCreate() {
        super.onCreate()
        val processName = if (Build.VERSION.SDK_INT >= 28) Application.getProcessName() else
            try { File("/proc/self/cmdline").inputStream().use {
                val buffer = ByteArray(256)
                val size = it.read(buffer)
                if (size > 0) String(buffer, 0, size).substringBefore('\u0000') else ""
            } } catch (_: Exception) { "" }
        processVerified = processName == "$packageName:pv_core"
        workerThread.start(); worker = Handler(workerThread.looper)
        if (!processVerified) stopSelf()
    }

    override fun onBind(intent: Intent): IBinder? = if (processVerified) messenger.binder else null
    override fun onUnbind(intent: Intent): Boolean { shutdown(); return false }
    override fun onDestroy() { shutdown(); super.onDestroy() }
    override fun onTaskRemoved(rootIntent: Intent?) { shutdown(); super.onTaskRemoved(rootIntent) }

    private fun receive(message: Message) {
        if (dying.get()) return
        if (message.what == CoreProtocol.START && owner == null) {
            val client = message.replyTo ?: return
            val id = message.data.getString("instance") ?: return
            if (id.length != 36) return
            instance = id; generation = message.data.getLong("generation", -1)
            if (generation < 0) return
            owner = client
            death = IBinder.DeathRecipient { main.post { shutdown() } }
            try { client.binder.linkToDeath(death!!, 0) } catch (_: Exception) { shutdown(); return }
            worker.post {
                try {
                    val core = GoCoreAdapter(this)
                    adapter = core
                    val fixture = core.startAndProbe(cancelled)
                    main.post { if (!cancelled.get()) reply("ready", fixture) }
                } catch (_: Exception) {
                    main.post { if (!cancelled.get()) reply("failed"); shutdown() }
                }
            }
            return
        }
        if (owner?.binder != message.replyTo?.binder || !CoreProtocol.matches(message.data, instance, generation)) return
        when (message.what) {
            CoreProtocol.STOP -> shutdown()
            CoreProtocol.READ -> worker.post {
                try {
                    val fixture = adapter?.readFixture(cancelled) ?: throw IllegalStateException()
                    main.post { if (!cancelled.get()) reply("ready", fixture) }
                } catch (_: Exception) { main.post { reply("failed"); shutdown() } }
            }
        }
    }

    private fun reply(phase: String, bytes: ByteArray? = null) {
        val data = CoreProtocol.ticket(instance, generation).apply {
            putString("phase", phase)
            if (bytes != null) {
                putByteArray("bytes", bytes); putString("version", CoreProtocol.VERSION); putString("sha256", CoreProtocol.DIGEST)
            }
        }
        try { owner?.send(Message.obtain(null, CoreProtocol.STATE).apply { this.data = data }) } catch (_: Exception) { shutdown() }
    }

    private fun shutdown() {
        if (!dying.compareAndSet(false, true)) return
        cancelled.set(true)
        // Even a stalled native initialization cannot leave an orphan HTTP server.
        if (processVerified) main.postDelayed({ Process.killProcess(Process.myPid()) }, 5000)
        worker.post {
            try { adapter?.close() } catch (_: Exception) { }
            main.post {
                reply("stopped")
                death?.let { try { owner?.binder?.unlinkToDeath(it, 0) } catch (_: Exception) { } }
                owner = null; stopSelf(); workerThread.quitSafely()
                if (processVerified) main.postDelayed({ Process.killProcess(Process.myPid()) }, 100)
            }
        }
    }
}
