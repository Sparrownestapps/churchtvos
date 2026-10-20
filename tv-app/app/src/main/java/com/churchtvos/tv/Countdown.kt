package com.churchtvos.tv

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import java.io.File
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.ceil
import kotlin.math.min
import kotlinx.coroutines.delay
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** The site's time zone (from the server), so "count down to 9:00" means 9:00 where the TV is. */
val LocalTimeZone = compositionLocalOf { ZoneId.systemDefault() }

/** Audio that plays during a countdown (a file from the media library). */
@Serializable
data class CountdownAudio(
    val url: String,
    @SerialName("media_id") val mediaId: String? = null,
    val volume: Float = 0.8f,
    val loop: Boolean = true,
    @SerialName("fade_seconds") val fadeSeconds: Float = 3f,
    @SerialName("align_end") val alignEnd: Boolean = false,
)

/**
 * mode "duration": count down [seconds] from when the slide appears. mode "until": count down to the clock time [until] ("HH:MM") today.
 * atZero "next" moves on by itself, "hold" stays on 0:00 until Next. A missing atZero means "next" (how older Kids countdowns always behaved).
 * ifPassed (until mode): "zero" shows 0:00 (then follows atZero), "skip" leaves the slide out.
 */
data class CountdownSpec(
    val mode: String = "duration",
    val seconds: Int = 60,
    val until: String? = null,
    val audio: CountdownAudio? = null,
    val atZero: String = "next",
    val ifPassed: String = "zero",
)

/** Epoch millis of today's [until] ("HH:MM") in [zone], or null when it can't be read. */
fun untilMillis(until: String?, nowMillis: Long, zone: ZoneId): Long? {
    val time = runCatching { LocalTime.parse(until?.trim()) }.getOrNull() ?: return null
    val today = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(nowMillis), zone).toLocalDate()
    return ZonedDateTime.of(today, time, zone).toInstant().toEpochMilli()
}

/** "5:00", "0:07", or "1:05:00" for an hour or more. Rounds up so 0:00 only shows at the end. */
fun formatCountdown(remainingMs: Long): String {
    val total = ceil(remainingMs.coerceAtLeast(0) / 1000.0).toLong()
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

/** Volume multiplier: 1 until the last [fadeSeconds], then ramps to 0 at zero. */
fun fadeFactor(remainingMs: Long, fadeSeconds: Float): Float {
    if (fadeSeconds <= 0f) return 1f
    return min(1f, (remainingMs / 1000f / fadeSeconds)).coerceIn(0f, 1f)
}

/**
 * Runs a countdown: ticks the clock, plays the optional music (started late and cut to finish at zero when "align end" is on),
 * then moves on or holds at 0:00. [content] draws the time text. While [paused] the music is paused.
 */
@Composable
fun CountdownRunner(
    spec: CountdownSpec,
    audioFile: File?,
    paused: Boolean,
    onFinished: () -> Unit,
    content: @Composable (text: String) -> Unit,
) {
    val context = LocalContext.current
    val zone = LocalTimeZone.current
    val startedAt = remember { System.currentTimeMillis() }
    val endAt = remember(spec, zone) {
        if (spec.mode == "until") untilMillis(spec.until, startedAt, zone) ?: startedAt
        else startedAt + spec.seconds * 1000L
    }
    var remainingMs by remember { mutableLongStateOf((endAt - startedAt).coerceAtLeast(0)) }
    val finished by rememberUpdatedState(onFinished)
    val alreadyPassed = spec.mode == "until" && endAt <= startedAt

    LaunchedEffect(spec, zone) {
        if (alreadyPassed && spec.ifPassed == "skip") {
            finished()
            return@LaunchedEffect
        }
        while (true) {
            remainingMs = (endAt - System.currentTimeMillis()).coerceAtLeast(0)
            if (remainingMs <= 0) break
            delay(250)
        }
        // At zero: move on, or hold on 0:00 until the leader presses Next. (A time that had already passed shows 0:00 for a moment first.)
        if (spec.atZero != "hold") {
            if (alreadyPassed) delay(2_000)
            finished()
        }
    }

    val audio = spec.audio
    val player = remember(audioFile) { if (audioFile != null && audio != null) ExoPlayer.Builder(context).build() else null }
    DisposableEffect(player) { onDispose { player?.release() } }

    // Music: start now, or (align end) wait/seek so the track ends exactly at zero.
    LaunchedEffect(player, spec) {
        if (player == null || audio == null || audioFile == null) return@LaunchedEffect
        if (alreadyPassed) return@LaunchedEffect
        player.volume = 0f
        player.repeatMode = if (audio.loop && !audio.alignEnd) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
        player.setMediaItem(MediaItem.fromUri(Uri.fromFile(audioFile)))
        player.prepare()
        var waited = 0
        while (player.playbackState != Player.STATE_READY && waited < 50) { delay(100); waited++ }
        if (audio.alignEnd) {
            val duration = player.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0L
            val untilZero = endAt - System.currentTimeMillis()
            if (duration > 0) {
                if (untilZero > duration) delay(untilZero - duration)
                else player.seekTo(duration - untilZero.coerceAtLeast(0))
            }
        }
        player.play()
    }
    // Volume follows the fade; pause follows the caller.
    LaunchedEffect(player, paused) {
        if (player == null || audio == null) return@LaunchedEffect
        while (true) {
            player.volume = audio.volume.coerceIn(0f, 1f) * fadeFactor(remainingMs, audio.fadeSeconds)
            if (remainingMs <= 0 && player.isPlaying) player.pause()
            if (paused && player.isPlaying) player.pause()
            delay(100)
        }
    }
    LaunchedEffect(paused) {
        if (!paused && player != null && remainingMs > 0 && player.playbackState == Player.STATE_READY && !player.isPlaying && player.mediaItemCount > 0) player.play()
    }

    content(formatCountdown(remainingMs))
}
