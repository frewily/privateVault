package dev.privatevault.w01

import android.content.Context
import android.system.Os
import dev.privatevault.nativebridge.pvcore.Pvcore
import org.json.JSONObject
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Instantiated only by CoreService after verifying its dedicated process. */
internal class GoCoreAdapter(private val context: Context) {
    private var probe: CoreProbe? = null
    private var directory: File? = null
    private var nativeEntered = false

    fun startAndProbe(cancelled: AtomicBoolean): ByteArray {
        check(!nativeEntered && !cancelled.get())
        check(Pvcore.version() == CoreProtocol.VERSION)
        val buildId = Pvcore.buildID()
        check(Regex("pv-w01a-[a-f0-9]{16}").matches(buildId))
        val parent = File(context.filesDir, "w01-runs")
        check(parent.mkdirs() || parent.isDirectory)
        Os.chmod(parent.absolutePath, 448)
        val owned = File(parent, UUID.randomUUID().toString())
        check(owned.mkdir())
        Os.chmod(owned.absolutePath, 448)
        directory = owned
        val fixtures = File(owned, "fixture")
        check(fixtures.mkdir())
        Os.chmod(fixtures.absolutePath, 448)
        val sample = File(fixtures, "样本.png")
        context.assets.open("flutter_assets/assets/w01_sample.png").use { input ->
            sample.outputStream().use { output ->
                val bytes = input.readBytes()
                check(bytes.size == 14415 && CoreProbe.digest(bytes) == CoreProtocol.DIGEST)
                output.write(bytes)
            }
        }
        Os.chmod(sample.absolutePath, 384)
        check(!cancelled.get())
        val port = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { it.localPort }
        nativeEntered = true
        val credentials = JSONObject(Pvcore.start(owned.absolutePath, port.toLong()))
        check(credentials.getString("buildId") == buildId)
        check(credentials.getString("baseUrl") == "http://127.0.0.1:$port")
        val signingKey = credentials.getString("serverKey")
        check(Regex("[a-f0-9]{64}").matches(signingKey))
        val session = CoreProbe(credentials.getString("baseUrl"), credentials.getString("username"), credentials.getString("password"), signingKey)
        probe = session
        return session.authenticateAndRead(cancelled)
    }

    fun readFixture(cancelled: AtomicBoolean): ByteArray =
        checkNotNull(probe).readFixture(cancelled)

    fun close() {
        if (nativeEntered) Pvcore.stop()
        probe = null
        // Only the UUID directory this adapter created is eligible for removal.
        directory?.let { check(it.deleteRecursively()) }
        directory = null
    }
}
