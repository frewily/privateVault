package dev.privatevault.w01

import android.os.Bundle

internal object CoreProtocol {
    const val START = 1
    const val STOP = 2
    const val READ = 3
    const val STATE = 4
    const val VERSION = "v4.2.8"
    const val DIGEST = "d70a3c38d62588d9a2b61b7f676fef022039df34c12c92bfade0129103005901"
    fun ticket(instance: String, generation: Long) = Bundle().apply {
        putString("instance", instance); putLong("generation", generation)
    }
    fun matches(data: Bundle, instance: String, generation: Long) =
        data.getString("instance") == instance && data.getLong("generation", -1) == generation
}
