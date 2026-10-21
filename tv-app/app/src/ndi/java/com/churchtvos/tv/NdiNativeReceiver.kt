package com.churchtvos.tv

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.nsd.NsdManager
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import com.churchtvos.ndi.NdiNative

/**
 * EXPERIMENTAL receiver backed by the NDI SDK (the "ndi" flavor only). One instance per NDI slide.
 *
 * NDI on Android needs an NsdManager kept alive while a finder or receiver exists, and a multicast lock for discovery.
 * Both are held from [start] to [stop]. Every native call is wrapped so a failure becomes "lost", never a crash.
 */
class NdiNativeReceiver(private val context: Context) : NdiReceiver {
    private val main = Handler(Looper.getMainLooper())
    private var handle = 0L
    private var nsd: NsdManager? = null // referenced on purpose: NDI's documentation requires it to stay alive
    private var multicast: WifiManager.MulticastLock? = null
    private var poller: Runnable? = null
    private var audioThread: Thread? = null
    @Volatile private var audioRunning = false

    override fun start(spec: NdiSpec, surface: Surface, onSnapshot: (NdiSnapshot) -> Unit) {
        if (handle != 0L) return
        try {
            nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
            multicast = (context.getSystemService(Context.WIFI_SERVICE) as? WifiManager)?.createMulticastLock("churchtvos-ndi")?.apply {
                setReferenceCounted(false)
                acquire()
            }
            handle = NdiNative.create()
            NdiNative.start(handle, spec.source, spec.directAddress, surface, spec.audio)
        } catch (t: Throwable) {
            Log.w(TAG, "NDI start failed", t)
            handle = 0L
            main.post { onSnapshot(NdiSnapshot(NdiPhase.LOST)) }
            release()
            return
        }

        val out = LongArray(NdiNative.SNAPSHOT_SIZE)
        val tick = object : Runnable {
            override fun run() {
                val h = handle
                if (h == 0L) return
                try {
                    NdiNative.snapshot(h, out)
                    onSnapshot(
                        NdiSnapshot(
                            phase = NdiPhase.entries.getOrElse(out[NdiNative.PHASE].toInt()) { NdiPhase.LOST },
                            width = out[NdiNative.WIDTH].toInt(),
                            height = out[NdiNative.HEIGHT].toInt(),
                            msSinceFrame = out[NdiNative.MS_SINCE_FRAME],
                        ),
                    )
                } catch (t: Throwable) {
                    Log.w(TAG, "NDI snapshot failed", t)
                    onSnapshot(NdiSnapshot(NdiPhase.LOST))
                }
                main.postDelayed(this, 250)
            }
        }
        poller = tick
        main.post(tick)
        if (spec.audio) startAudio(handle, out)
    }

    /** Pulls stereo 16-bit audio from the native ring and plays it. Video-only is fine if this fails. */
    private fun startAudio(h: Long, info: LongArray) {
        audioRunning = true
        audioThread = Thread({
            var track: AudioTrack? = null
            var rate = 0
            val buffer = ShortArray(4096)
            val localInfo = LongArray(NdiNative.SNAPSHOT_SIZE)
            try {
                while (audioRunning) {
                    val n = NdiNative.readAudio(h, buffer)
                    if (n <= 0) continue
                    NdiNative.snapshot(h, localInfo)
                    val r = localInfo[NdiNative.AUDIO_RATE].toInt()
                    if (r > 0 && r != rate) {
                        track?.release()
                        rate = r
                        track = AudioTrack.Builder()
                            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build())
                            .setAudioFormat(AudioFormat.Builder().setSampleRate(rate).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
                            .setBufferSizeInBytes(maxOf(AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT), rate / 5 * 4))
                            .setTransferMode(AudioTrack.MODE_STREAM)
                            .build().also { it.play() }
                    }
                    track?.write(buffer, 0, n)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "NDI audio stopped", t)
            } finally {
                runCatching { track?.stop() }
                track?.release()
            }
        }, "ndi-audio").apply { isDaemon = true; start() }
    }

    override fun stop() {
        poller?.let(main::removeCallbacks)
        poller = null
        audioRunning = false
        val h = handle
        handle = 0L
        if (h != 0L) {
            try {
                NdiNative.stop(h) // blocks until the native thread has finished with the surface
                audioThread?.join(500)
                NdiNative.destroy(h)
            } catch (t: Throwable) {
                Log.w(TAG, "NDI stop failed", t)
            }
        }
        audioThread = null
        release()
    }

    private fun release() {
        runCatching { multicast?.takeIf { it.isHeld }?.release() }
        multicast = null
        nsd = null
    }

    private companion object { const val TAG = "ChurchTvNdi" }
}
