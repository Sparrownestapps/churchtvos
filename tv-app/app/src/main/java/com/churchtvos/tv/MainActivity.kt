package com.churchtvos.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AutoLaunch.start(applicationContext)
        val cache = MediaCache(applicationContext)
        val sync = TvSync(applicationContext, cache)
        // Debug builds only: `adb shell am start -n com.churchtvos.tv/.MainActivity --es debug_youtube <id|live:CHANNEL>`
        val debugYouTube = if (BuildConfig.DEBUG) intent.getStringExtra("debug_youtube") else null
        setContent {
            if (debugYouTube != null) {
                val slide = if (debugYouTube.startsWith("live:")) {
                    Slide.YouTube(null, debugYouTube.removePrefix("live:"), null)
                } else {
                    Slide.YouTube(debugYouTube, null, null)
                }
                // Countdown either side to check switching into and out of YouTube.
                PlayerScreen(
                    listOf(Slide.Countdown("Before", 4), slide, Slide.Countdown("After", 30)),
                    onExit = { finish() },
                )
            } else {
                App(sync, cache)
            }
        }
    }
}

private val whenFormat = DateTimeFormatter.ofPattern("EEE MMM d · h:mm a").withZone(ZoneId.systemDefault())

@Composable
fun App(sync: TvSync, cache: MediaCache) {
    val state by sync.state.collectAsState()
    LaunchedEffect(Unit) { sync.run() }

    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(15_000)
            now = Instant.now()
        }
    }

    val device = state.device
    BrandTheme(device?.brand() ?: Brand()) {
        Oriented(device?.screen?.orientation ?: "landscape") {
            when {
                device == null -> MessageScreen("Connecting…", state.error)
                !device.paired -> PairingScreen(device.pairingCode ?: "······", state.offline)
                else -> when (val module = device.moduleNow(now.toEpochMilli())) {
                    Module.OFF -> Box(Modifier.fillMaxSize().background(Color.Black))
                    !in device.enabledModules -> MessageScreen(
                        "This screen is set to ${module.replaceFirstChar { it.uppercase() }}",
                        "That module isn't switched on for ${device.organization?.name ?: "this church"}. Ask your church's admin.",
                    )
                    Module.SIGNAGE -> SignageModule(device, now, cache)
                    else -> KidsModule(device, state, now, cache)
                }
            }
        }
    }
}

/** The Kids curriculum player: shows what's scheduled and starts when someone presses Play. */
@Composable
private fun KidsModule(device: DeviceState, state: TvUiState, now: Instant, cache: MediaCache) {
    // Snapshot of the playlist when Play was pressed, so a sync mid-service can't change it.
    var playing by remember { mutableStateOf<Playlist?>(null) }
    val active = playing

    if (active != null) {
        val slides = remember(active) { active.toSlides(cache) }
        PlayerScreen(slides, onExit = { playing = null })
        return
    }

    val current = device.current(now)
    val schedule = current ?: device.next(now)
    val playlist = schedule?.playlist
    val ready = playlist != null && playlist.mediaUrls.all { cache.fileFor(it).exists() }
    val downloading = state.downloading
    HomeScreen(
        site = device.site.orEmpty(),
        location = device.location.orEmpty(),
        heading = when {
            current != null -> "NOW SHOWING"
            schedule != null -> "UP NEXT · ${whenFormat.format(schedule.start).uppercase()}"
            else -> "NOTHING SCHEDULED"
        },
        playlist = playlist,
        status = when {
            playlist == null -> "Schedule a playlist for this location in the dashboard."
            ready -> "✓ Ready to play"
            downloading != null -> "Downloading media… ${downloading.done + 1} of ${downloading.total}"
            state.failedDownloads > 0 -> "⚠ Some media couldn't download. Retrying…"
            else -> "Preparing media…"
        } + if (state.offline) "  ·  Offline, using saved schedule" else "",
        canPlay = ready,
        onPlay = { playing = playlist },
    )
}

/** Signage: loops whatever playlist is scheduled right now; black when nothing is. */
@Composable
private fun SignageModule(device: DeviceState, now: Instant, cache: MediaCache) {
    val playlist = device.signagePlaylistNow(now.toEpochMilli())
    // Only items whose files have finished downloading, so the loop never stalls on a missing file.
    val playable = playlist?.copy(items = playlist.items.filter { item ->
        when (item) {
            is PlaylistItem.Video -> cache.fileFor(item.url).exists()
            is PlaylistItem.Image -> cache.fileFor(item.url).exists()
            else -> true
        }
    })
    if (playable == null || playable.items.isEmpty()) {
        Box(Modifier.fillMaxSize().background(Color.Black))
        return
    }
    var loop by remember { mutableIntStateOf(0) }
    // A new loop (or changed content) starts the playlist from the top.
    key(playable, loop) {
        val slides = remember(playable) {
            playable.copy(items = playable.items.map { if (it is PlaylistItem.Image && it.seconds == null) it.copy(seconds = 10) else it })
                .toSlides(cache)
        }
        PlayerScreen(slides, onExit = { loop++ })
    }
}
