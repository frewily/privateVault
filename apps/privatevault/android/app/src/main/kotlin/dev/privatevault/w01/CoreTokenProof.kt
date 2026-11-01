package dev.privatevault.w01

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Proves the HTTP token was signed by this native core's fresh key.
 * The fixed upstream emits this canonical HS256 header. Claim/expiry handling
 * remains upstream; this is an instance proof, not a general JWT library.
 */
internal class CoreTokenProof(signingKey: String) {
    private val key = signingKey.toByteArray(Charsets.UTF_8)
    init { require(key.size in 16..256) }
    fun verify(token: String, decodeUrlBase64: (String) -> ByteArray) {
        require(token.length in 1..8192)
        val parts = token.split('.')
        require(parts.size == 3 && parts[0] == HS256_HEADER)
        require(parts.all { it.isNotEmpty() && it.all { c -> c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '_' || c == '-' } })
        val signature = decodeUrlBase64(parts[2])
        require(signature.size == 32)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        val expected = mac.doFinal((parts[0] + "." + parts[1]).toByteArray(Charsets.US_ASCII))
        require(MessageDigest.isEqual(expected, signature))
    }
    companion object {
        const val HS256_HEADER = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    }
}
