package com.churchtvos.tv

import android.os.Bundle
import android.view.KeyEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
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
    private var settingsOpen by mutableStateOf(false)

    private var centerDownAt = 0L
    private var longPressHandled = false

    // Holding OK for a second opens (and closes) Settings from anywhere: Google TV remotes have no Menu button.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_DPAD_CENTER || event.keyCode == KeyEvent.KEYCODE_ENTER) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                if (event.repeatCount == 0) {
                    centerDownAt = event.eventTime
                    longPressHandled = false
                } else if (longPressHandled) {
                    return true
                } else if (event.eventTime - centerDownAt >= 1000) {
                    longPressHandled = true
                    settingsOpen = !settingsOpen
                    return true
                }
            } else if (event.action == KeyEvent.ACTION_UP && longPressHandled) {
                longPressHandled = false
                return true // do not also "click" whatever had focus
            }
        }
        return super.dispatchKeyEvent(event)
    }

    // The remote's Menu button opens (and closes) Settings from anywhere.
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_MENU) {
            settingsOpen = !settingsOpen
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A display must never fall asleep or start the screensaver while this app is in front (home screens included).
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        AutoLaunch.start(applicationContext)
        val cache = MediaCache(applicationContext)
        val sync = TvSync(applicationContext, cache)
        // Debug builds only: `adb shell am start -n com.churchtvos.tv/.MainActivity --es debug_youtube <id|live:CHANNEL>`
        val debugYouTube = if (BuildConfig.DEBUG) intent.getStringExtra("debug_youtube") else null
        // Debug builds only: --es debug_sign '<sign item json>' and/or --es debug_home 1, with --es debug_orientation portrait|portrait_flipped
        val debugSign = if (BuildConfig.DEBUG) {
            // adb strips quotes from JSON, so a base64 form is accepted too (debug_sign_b64).
            intent.getStringExtra("debug_sign")
                ?: intent.getStringExtra("debug_sign_b64")?.let { String(android.util.Base64.decode(it, android.util.Base64.DEFAULT)) }
        } else null
        val debugHome = if (BuildConfig.DEBUG) intent.getStringExtra("debug_home") != null else false
        val debugOrientation = if (BuildConfig.DEBUG) intent.getStringExtra("debug_orientation") else null
        // Debug builds only: --es debug_deck_b64 '<base64 of a Deck json>' (downloads the deck's media first)
        val debugDeck = if (BuildConfig.DEBUG) intent.getStringExtra("debug_deck_b64")?.let {
            AppJson.decodeFromString<Deck>(String(android.util.Base64.decode(it, android.util.Base64.DEFAULT)))
        } else null
        setContent {
            if (debugDeck != null) {
                BrandTheme(Brand()) {
                    Oriented(debugOrientation ?: "landscape") {
                        var ready by remember { mutableStateOf(false) }
                        LaunchedEffect(Unit) {
                            debugDeck.mediaUrls.forEach { runCatching { cache.download(it) } }
                            ready = true
                        }
                        if (ready) SlidesPlayer(debugDeck, cache, onExit = { finish() }) else Box(Modifier.fillMaxSize().background(Color.Black))
                    }
                }
            } else if (debugSign != null || debugHome) {
                val branding = if (BuildConfig.DEBUG) intent.getStringExtra("debug_brand") else null
                BrandTheme(Brand(primary = parseHexColor(branding) ?: Brand().primary, logoUrl = intent.getStringExtra("debug_logo"))) {
                    Oriented(debugOrientation ?: "landscape") {
                        if (debugSign != null) {
                            val item = AppJson.decodeFromString<PlaylistItem>(debugSign)
                            // Debug only: pretend the church has the experimental NDI flag so an "ndi" item can be tried.
                            androidx.compose.runtime.CompositionLocalProvider(LocalNdiAllowed provides true) {
                                PlayerScreen(Playlist("debug", "debug", listOf(item)).toSlides(cache), onExit = { finish() })
                            }
                        } else {
                            val sample = Playlist("debug", "Week 3: Noah and the Ark", listOf(
                                PlaylistItem.Countdown("Service starts in", 300),
                                PlaylistItem.Video("Bible story", "https://example.com/a.mp4"),
                                PlaylistItem.Lyrics("Sample song", listOf("Verse", "Chorus")),
                                PlaylistItem.Stream("Main room live", "https://example.com/live.m3u8"),
                            ))
                            HomeScreen("Cambridge", "Room 201", "NOW SHOWING", sample, "✓ Ready to play", true) {}
                        }
                    }
                }
            } else if (debugYouTube != null) {
                val slide = if (debugYouTube.startsWith("live:")) {
                    Slide.YouTube(null, debugYouTube.removePrefix("live:"), null)
                } else {
                    Slide.YouTube(debugYouTube, null, null)
                }
                // Countdown either side to check switching into and out of YouTube.
                PlayerScreen(
                    listOf(Slide.Countdown("Before", CountdownSpec(seconds = 4), null), slide, Slide.Countdown("After", CountdownSpec(seconds = 30), null)),
                    onExit = { finish() },
                )
            } else {
                App(sync, cache, settingsOpen, onSettingsChange = { settingsOpen = it })
            }
        }
    }
}

private val whenFormat = DateTimeFormatter.ofPattern("EEE MMM d · h:mm a").withZone(ZoneId.systemDefault())

@Composable
fun App(sync: TvSync, cache: MediaCache, settingsOpen: Boolean, onSettingsChange: (Boolean) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val state by sync.state.collectAsState()
    LaunchedEffect(Unit) { sync.run() }
    LaunchedEffect(Unit) { sync.runRemote() }

    var now by remember { mutableStateOf(Instant.now()) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(15_000)
            now = Instant.now()
        }
    }

    val device = state.device
    // A "play this now" request from a remote ends when it times out, finishes, or someone stops it (Stop or Back).
    var dismissedUntil by remember { mutableStateOf<String?>(null) }
    val currentOverride by androidx.compose.runtime.rememberUpdatedState(device?.override)
    val message by Remote.message.collectAsState()
    LaunchedEffect(Unit) {
        Remote.commands.collect { c ->
            when (c) {
                is RemoteCommand.Message -> Remote.message.value = ActiveMessage(c.text, c.background, System.currentTimeMillis() + c.seconds * 1000L)
                RemoteCommand.ClearMessage -> Remote.message.value = null
                RemoteCommand.Stop -> dismissedUntil = currentOverride?.until
                else -> Unit
            }
        }
    }
    var demo by remember { mutableStateOf<String?>(null) }
    var demoMenu by remember { mutableStateOf(false) }
    var autoLaunch by remember { mutableStateOf(sync.store.autoLaunch) }
    var asked by remember { mutableStateOf(sync.store.autoLaunchAsked || !AutoLaunch.supported) }
    val demoNow = demo

    val zone = remember(device?.timezone) { runCatching { java.time.ZoneId.of(device?.timezone) }.getOrDefault(java.time.ZoneId.systemDefault()) }
    androidx.compose.runtime.CompositionLocalProvider(LocalTimeZone provides zone, LocalNdiAllowed provides (device?.experimental?.ndi == true)) {
    BrandTheme(device?.brand() ?: Brand()) {
        Oriented(device?.screen?.orientation ?: "landscape") {
            when {
                demoNow != null -> {
                    var loop by remember { mutableIntStateOf(0) }
                    key(demoNow, loop) {
                        PlayerScreen(Demo.slides(demoNow), onExit = { demo = null }, onFinished = { loop++ })
                    }
                }
                demoMenu -> DemoMenu(onPick = { demo = it; demoMenu = false; onSettingsChange(false) }, onClose = { demoMenu = false })
                settingsOpen -> SettingsScreen(
                    autoLaunch = autoLaunch,
                    autoLaunchSupported = AutoLaunch.supported,
                    paired = device?.paired == true,
                    detail = "Version ${BuildConfig.VERSION_NAME}" + (device?.screen?.name?.let { "  ·  $it" } ?: "") + "  ·  $DASHBOARD_HOST",
                    onToggleAutoLaunch = { autoLaunch = !autoLaunch; AutoLaunch.setEnabled(context, autoLaunch); asked = true },
                    onDemo = { demoMenu = true },
                    onClose = { onSettingsChange(false) },
                )
                device == null -> MessageScreen("Connecting…", state.error)
                !device.paired -> PairingScreen(device.pairingCode ?: "······", state.offline, onSettings = { onSettingsChange(true) })
                !asked -> AutoLaunchPrompt { yes ->
                    AutoLaunch.setEnabled(context, yes)
                    autoLaunch = yes
                    asked = true
                }
                device.organization?.status == "suspended" -> MessageScreen(
                    "This account is paused",
                    "Please ask your church's administrator to contact Church TV OS support.",
                )
                device.override?.takeIf { it.until != dismissedUntil && it.untilInstant.isAfter(now) } != null -> {
                    val o = device.override!!
                    OverrideScreen(o, state, cache, onDone = { dismissedUntil = o.until })
                }
                else -> {
                    val module = device.moduleNow(now.toEpochMilli())
                    // Each module can have its own look, and its own splash when the TV starts or switches into it.
                    BrandTheme(device.brand(module)) {
                        val brand = LocalBrand.current
                        var splashDone by remember(module) { mutableStateOf(brand.splashSeconds == null || module == Module.OFF) }
                        LaunchedEffect(module) {
                            if (!splashDone) {
                                delay((brand.splashSeconds ?: 0) * 1000L)
                                splashDone = true
                            }
                        }
                        when {
                            !splashDone -> SplashScreen()
                            module == Module.OFF -> Box(Modifier.fillMaxSize().background(Color.Black))
                            module !in device.enabledModules -> MessageScreen(
                                "This screen is set to ${module.replaceFirstChar { it.uppercase() }}",
                                "That module isn't switched on for ${device.organization?.name ?: "this church"}. Ask your church's admin.",
                            )
                            module == Module.SIGNAGE -> SignageModule(device, now, cache)
                            module == Module.SLIDES -> SlidesModule(device, state, now, cache)
                            else -> KidsModule(device, state, now, cache)
                        }
                    }
                }
            }
        }
    }
    MessageOverlay(message)
    }
}

/** The Kids curriculum player: shows what's scheduled and starts when someone presses Play. */
@Composable
private fun KidsModule(device: DeviceState, state: TvUiState, now: Instant, cache: MediaCache) {
    // Snapshot of the playlist when Play was pressed, so a sync mid-service can't change it.
    var playing by remember { mutableStateOf<Playlist?>(null) }
    // With "start playing automatically" on, each scheduled item starts by itself once (pressing Back stops it for good).
    var autoStartedFor by remember { mutableStateOf<String?>(null) }
    val active = playing

    if (active != null) {
        val slides = remember(active) { active.toSlides(cache) }
        PlayerScreen(slides, onExit = { playing = null }, report = PlayerReport(Module.KIDS, active.name, "playlist", active.id))
        return
    }

    val current = device.current(now)
    val schedule = current ?: device.next(now)
    val playlist = schedule?.playlist
    val ready = playlist != null && playlist.mediaUrls.all { cache.fileFor(it).exists() }
    val downloading = state.downloading
    LaunchedEffect(current?.id, ready, device.screen.autoplay) {
        if (device.screen.autoplay && current != null && ready && autoStartedFor != current.id) {
            autoStartedFor = current.id
            playing = playlist
        }
    }
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
            is PlaylistItem.Unknown -> false
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
            playable.copy(items = playable.items.map {
                when {
                    it is PlaylistItem.Image && it.seconds == null -> it.copy(seconds = 10)
                    it is PlaylistItem.Stream && it.seconds == null -> it.copy(seconds = 30) // a loop must move on
                    it is PlaylistItem.Ndi && it.seconds == null -> it.copy(seconds = 30)
                    else -> it
                }
            })
                .toSlides(cache)
        }
        PlayerScreen(slides, onExit = { loop++ }, report = PlayerReport(Module.SIGNAGE, playable.name))
    }
}
