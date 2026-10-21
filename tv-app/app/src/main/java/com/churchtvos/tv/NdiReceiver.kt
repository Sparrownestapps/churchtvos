package com.churchtvos.tv

import android.view.Surface

/** Where a receiver is in connecting to a source. */
enum class NdiPhase { SEARCHING, CONNECTING, STREAMING, LOST }

/** What the receiver can tell the screen about itself. [msSinceFrame] is -1 before the first frame. */
data class NdiSnapshot(val phase: NdiPhase = NdiPhase.SEARCHING, val width: Int = 0, val height: Int = 0, val msSinceFrame: Long = -1) {
    /** Frames are arriving now (the last one is under two seconds old). */
    val streaming: Boolean get() = phase == NdiPhase.STREAMING && msSinceFrame in 0..STALE_MS

    companion object { const val STALE_MS = 2_000L }
}

/**
 * Receives one NDI source and draws its video into a surface. The only implementation that does real work is in the
 * "ndi" product flavor; the store flavor has none ([createNdiReceiver] returns null there).
 * Calls come from the main thread. Implementations must make [stop] safe to call twice and must never throw.
 */
interface NdiReceiver {
    /** Starts looking for and receiving [spec]; video goes to [surface]. [onSnapshot] is called on the main thread about 4 times a second. */
    fun start(spec: NdiSpec, surface: Surface, onSnapshot: (NdiSnapshot) -> Unit)

    /** Stops receiving and releases everything, including the surface (blocks briefly until the native thread is done). */
    fun stop()
}
