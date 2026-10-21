package com.churchtvos.ndi

import android.view.Surface

/**
 * Thin JNI wrapper around the NDI receiver in cpp/ndi_jni.cpp. EXPERIMENTAL: needs the NDI Android SDK (licence unconfirmed).
 * All methods are safe to call from any thread except that [stop] and [destroy] block until the native thread has finished.
 * A handle of 0 means "no receiver".
 */
object NdiNative {
    /** False when libndi.so or libndi_jni.so could not be loaded (for example a build made without the SDK). */
    val loaded: Boolean = try {
        System.loadLibrary("ndi")
        System.loadLibrary("ndi_jni")
        true
    } catch (e: Throwable) {
        false
    }

    /** Index meanings for the array filled by [snapshot]. */
    const val PHASE = 0 // 0 searching, 1 connecting, 2 streaming, 3 lost
    const val WIDTH = 1
    const val HEIGHT = 2
    const val MS_SINCE_FRAME = 3 // -1 before the first frame
    const val AUDIO_RATE = 4
    const val AUDIO_CHANNELS = 5
    const val SNAPSHOT_SIZE = 6

    external fun create(): Long

    /** Starts the receive thread. [address] may be null or empty (find by name). Takes its own reference to [surface]. */
    external fun start(handle: Long, source: String, address: String?, surface: Surface, audio: Boolean)

    /** Stops the thread and releases the NDI receiver and the window. Safe to call twice. */
    external fun stop(handle: Long)

    external fun destroy(handle: Long)

    /** Fills [out] (size [SNAPSHOT_SIZE]). */
    external fun snapshot(handle: Long, out: LongArray)

    /** Blocks up to about 50 ms for stereo 16-bit audio; returns the number of shorts written (0 when none). */
    external fun readAudio(handle: Long, out: ShortArray): Int
}
