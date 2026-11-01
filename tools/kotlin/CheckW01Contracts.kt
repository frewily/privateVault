package dev.privatevault.w01

/** No Android mocks: exercise the exact gate and endpoint guard used by production. */
fun main() {
    val gate = CoreReplyGate()
    gate.open("first", 1)
    check(gate.accepts("first", 1))
    gate.close() // failed binding: its later STOPPED must not hide the error.
    check(!gate.accepts("first", 1))
    gate.open("second", 2)
    check(!gate.accepts("first", 1))
    check(!gate.accepts("second", 1))
    check(gate.accepts("second", 2))
    gate.close()
    check(!gate.accepts("second", 2))
    val endpoint = CoreEndpoint("http://127.0.0.1:25444")
    endpoint.check("http://127.0.0.1:25444/p/w01/sample.png?sign=synthetic")
    for (url in listOf("http://example.invalid:25444/p", "http://127.0.0.1:25445/p",
        "https://127.0.0.1:25444/p", "http://user@127.0.0.1:25444/p", "http://127.0.0.1:25444/p#fragment")) {
        check(runCatching { endpoint.check(url) }.isFailure)
    }
    for (base in listOf("http://127.0.0.1:25444/path", "http://127.0.0.1:25444?query=x",
        "http://127.0.0.1:25444#fragment", "http://0.0.0.0:25444")) {
        check(runCatching { CoreEndpoint(base) }.isFailure)
    }
    // Public HS256 example vector, independent of the production signer.
    val token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
    val decode: (String) -> ByteArray = { java.util.Base64.getUrlDecoder().decode(it) }
    val proof = CoreTokenProof("your-256-bit-secret")
    proof.verify(token, decode)
    check(runCatching { CoreTokenProof("another-synthetic-key").verify(token, decode) }.isFailure)
    check(runCatching { proof.verify(token.replace("eyJzdWI", "eyJzdWJ"), decode) }.isFailure)
    check(runCatching { proof.verify(token.substringBeforeLast('.') + ".AA", decode) }.isFailure)
    check(runCatching { proof.verify("eyJhbGciOiJub25lIn0." + token.substringAfter('.'), decode) }.isFailure)
    check(runCatching { proof.verify("x".repeat(8193), decode) }.isFailure)
    println("PASS: old core messages rejected; loopback endpoint enforced; HS256 instance proof rejects wrong keys and tampering")
}
