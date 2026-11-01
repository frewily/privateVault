package dev.privatevault.w01

/** An invalidated binding cannot publish a late STOPPED or READY result. */
internal class CoreReplyGate {
    private var instance: String? = null
    private var generation = -1L
    fun open(instance: String, generation: Long) { this.instance = instance; this.generation = generation }
    fun accepts(instance: String?, generation: Long) = this.instance != null && this.instance == instance && this.generation == generation
    fun close() { instance = null }
}
