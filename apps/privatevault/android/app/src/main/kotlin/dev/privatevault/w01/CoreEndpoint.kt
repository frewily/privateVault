package dev.privatevault.w01

import java.net.URI

/** Shared by the real HTTP probe and host-side contract checks. */
internal class CoreEndpoint(base: String) {
    private val origin = URI(base)
    init {
        require(origin.scheme == "http" && origin.host == "127.0.0.1" && origin.port in 1024..65535 &&
            origin.rawUserInfo == null && origin.rawQuery == null && origin.fragment == null && origin.path.isEmpty())
    }
    fun check(url: String) {
        val target = URI(url)
        require(target.scheme == origin.scheme && target.host == origin.host && target.port == origin.port &&
            target.rawUserInfo == null && target.fragment == null)
    }
}
