package dev.privatevault.w01

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/** All credential-bearing requests stay on this exact loopback endpoint. */
internal class CoreProbe(private val base: String, private val username: String, private var password: String, signingKey: String) {
    private val endpoint = CoreEndpoint(base)
    private val tokenProof = CoreTokenProof(signingKey)
    private var token = ""
    private data class Response(val status: Int, val bytes: ByteArray)

    private fun request(url: String, body: JSONObject? = null, authenticated: Boolean = false): Response {
        endpoint.check(url)
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = false
        connection.connectTimeout = 1000
        connection.readTimeout = 2000
        connection.requestMethod = if (body == null) "GET" else "POST"
        if (authenticated) { check(token.isNotEmpty()); connection.setRequestProperty("Authorization", token) }
        try {
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val output = ByteArrayOutputStream()
            stream?.use { input ->
                val buffer = ByteArray(4096)
                while (true) {
                    val size = input.read(buffer)
                    if (size < 0) break
                    check(output.size() + size <= 96 * 1024)
                    output.write(buffer, 0, size)
                }
            }
            return Response(status, output.toByteArray())
        } finally { connection.disconnect() }
    }

    private fun json(path: String, body: JSONObject? = null, authenticated: Boolean = false): JSONObject {
        val response = request(base + path, body, authenticated)
        check(response.status == 200)
        return JSONObject(String(response.bytes, Charsets.UTF_8))
    }

    fun authenticateAndRead(cancelled: AtomicBoolean): ByteArray {
        val deadline = System.nanoTime() + 30_000_000_000L
        var ready = false
        while (!cancelled.get() && System.nanoTime() < deadline) {
            try {
                val settings = json("/api/public/settings")
                check(settings.getInt("code") == 200)
                val version = settings.getJSONObject("data").getString("version")
                check(version.startsWith("v4.2.8 (Commit: 25e4eb663ffb73991a68d85df4f690d48ad137a6)"))
                ready = true
                break
            } catch (_: Exception) { Thread.sleep(100) }
        }
        check(ready && !cancelled.get())
        val login = json("/api/auth/login", JSONObject().put("username", username).put("password", password))
        password = ""
        check(login.getInt("code") == 200)
        token = login.getJSONObject("data").getString("token")
        check(token.isNotEmpty())
        tokenProof.verify(token) {
            android.util.Base64.decode(it, android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING)
        }
        val denied = json("/api/fs/list", JSONObject().put("path", "/w01").put("password", ""))
        check(denied.getInt("code") in listOf(401, 403))
        val management = json("/api/admin/storage/list?page=1&per_page=1")
        check(management.getInt("code") in listOf(401, 403))
        val unsigned = request(base + "/d/w01/%E6%A0%B7%E6%9C%AC.png")
        check(unsigned.status in listOf(401, 403))
        return readFixture(cancelled)
    }

    fun readFixture(cancelled: AtomicBoolean): ByteArray {
        check(!cancelled.get())
        val listing = json("/api/fs/list", JSONObject().put("path", "/w01").put("password", "").put("refresh", true).put("page", 1).put("per_page", 10), true)
        check(listing.getInt("code") == 200)
        val content = listing.getJSONObject("data").getJSONArray("content")
        check(content.length() == 1)
        val item = content.getJSONObject(0)
        check(item.getString("name") == "样本.png" && item.getLong("size") == 14415L && !item.getBoolean("is_dir"))
        val get = json("/api/fs/get", JSONObject().put("path", "/w01/样本.png").put("password", ""), true)
        check(get.getInt("code") == 200)
        val file = get.getJSONObject("data")
        check(file.getString("name") == "样本.png" && file.getLong("size") == 14415L)
        check(!cancelled.get())
        val sign = file.getString("sign")
        check(sign.isNotEmpty())
        val encoded = java.net.URLEncoder.encode(sign, "UTF-8")
        val response = request(base + "/p/w01/%E6%A0%B7%E6%9C%AC.png?sign=$encoded")
        check(response.status == 200 && response.bytes.size == 14415)
        check(!cancelled.get() && digest(response.bytes) == CoreProtocol.DIGEST)
        return response.bytes
    }

    companion object {
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
