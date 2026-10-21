package com.churchtvos.tv

import android.net.Uri
import android.view.LayoutInflater
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import androidx.tv.material3.Text
import coil3.compose.AsyncImage
import kotlin.math.cos
import kotlin.math.sin
import kotlinx.coroutines.delay

private val DefaultBackground = Color(0xFF1B2A4A)

/** slide, then deck, then theme, then the church's primary colour. */
private fun resolveBackground(deck: Deck, slide: DeckSlide?): SlideBackground? {
    val own = slide?.background?.takeIf { it !is SlideBackground.Unknown }
    return own ?: deck.background?.takeIf { it !is SlideBackground.Unknown } ?: deck.theme.background?.takeIf { it !is SlideBackground.Unknown }
}

private fun needsForegroundPlayer(slide: DeckSlide?) =
    slide is DeckSlide.Stream || (slide is DeckSlide.Media && slide.mediaKind == "video")

private fun newPlayerView(context: android.content.Context, player: Player, zoom: Boolean): PlayerView {
    val view = LayoutInflater.from(context).inflate(R.layout.player_texture, null) as PlayerView
    view.setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
    view.resizeMode = if (zoom) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
    view.player = player
    return view
}

/** The background layers: colour or gradient, a picture, or a looping video, plus the dimming overlay. */
@Composable
private fun BackgroundLayer(bg: SlideBackground?, cache: MediaCache, bgPlayer: Player) {
    val fallback = LocalBrand.current.primary
    Box(Modifier.fillMaxSize()) {
        when (bg) {
            null, is SlideBackground.Unknown -> Box(Modifier.fillMaxSize().background(fallback.takeIf { it != Color.Unspecified } ?: DefaultBackground))
            is SlideBackground.Solid -> Box(Modifier.fillMaxSize().background(parseHexColor(bg.color) ?: DefaultBackground))
            is SlideBackground.Gradient -> {
                val a = parseHexColor(bg.color) ?: DefaultBackground
                val b = parseHexColor(bg.color2) ?: Color.Black
                Box(
                    Modifier.fillMaxSize().drawBehind {
                        // CSS-style angle: 0 = to top, 90 = to right, 180 = to bottom.
                        val rad = Math.toRadians(bg.angle.toDouble())
                        val dx = sin(rad).toFloat()
                        val dy = -cos(rad).toFloat()
                        val half = (kotlin.math.abs(size.width * dx) + kotlin.math.abs(size.height * dy)) / 2f
                        val c = Offset(size.width / 2f, size.height / 2f)
                        val s = Offset(c.x - dx * half, c.y - dy * half)
                        val e = Offset(c.x + dx * half, c.y + dy * half)
                        drawRect(Brush.linearGradient(listOf(a, b), start = s, end = e))
                    },
                )
            }
            is SlideBackground.Image -> {
                Box(Modifier.fillMaxSize().background(parseHexColor(bg.color) ?: Color.Black))
                val file = cache.fileFor(bg.url)
                if (file.exists()) {
                    AsyncImage(
                        model = file,
                        contentDescription = null,
                        contentScale = if (bg.fit == "contain") ContentScale.Fit else ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
            is SlideBackground.Video -> {
                Box(Modifier.fillMaxSize().background(parseHexColor(bg.color) ?: Color.Black))
                if (cache.fileFor(bg.url).exists()) {
                    AndroidView(
                        factory = { newPlayerView(it, bgPlayer, zoom = bg.fit != "contain") },
                        update = { it.resizeMode = if (bg.fit == "contain") AspectRatioFrameLayout.RESIZE_MODE_FIT else AspectRatioFrameLayout.RESIZE_MODE_ZOOM },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
        val dim = (bg?.dim ?: 0f).coerceIn(0f, 0.8f)
        if (dim > 0f) Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = dim)))
    }
}

private fun DeckSlide.listLabel(): String = when (this) {
    is DeckSlide.Text -> listOfNotNull(title?.takeIf { it.isNotBlank() }, body?.lineSequence()?.firstOrNull()?.takeIf { it.isNotBlank() }).firstOrNull() ?: "Text"
    is DeckSlide.Media -> if (mediaKind == "video") "Video" else "Picture"
    is DeckSlide.Countdown -> title?.takeIf { it.isNotBlank() }?.let { "Countdown: $it" } ?: "Countdown"
    is DeckSlide.Stream -> title?.takeIf { it.isNotBlank() }?.let { "Live: $it" } ?: "Live stream"
    is DeckSlide.Blank -> "Blank"
    is DeckSlide.SongTitle -> "$title (title)"
    is DeckSlide.Lyric -> "$song · ${label?.takeIf { it.isNotBlank() } ?: "Part $number"}"
    is DeckSlide.Unknown -> "—"
}

/**
 * Plays a deck from the TV remote: Right = next, Left = back, OK = slide list (jump anywhere),
 * Play/Pause = black screen on/off, Back = stop.
 */
@Composable
fun SlidesPlayer(deck: Deck, cache: MediaCache, onExit: () -> Unit, onFinished: () -> Unit = onExit, report: Boolean = true) {
    val context = LocalContext.current
    val rotated = LocalRotated.current
    val slides = remember(deck) {
        deck.playableSlides.filter { s ->
            // A slide whose file never downloaded would be blank; skip it rather than stall.
            when (s) {
                is DeckSlide.Media -> cache.fileFor(s.url).exists()
                else -> true
            }
        }
    }
    if (slides.isEmpty()) {
        Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
            Text("This deck has no slides yet.", style = TextStyle(fontFamily = Lato, fontSize = 24.sp, color = Color.White))
        }
        BackHandler(onBack = onExit)
        return
    }

    var index by remember { mutableIntStateOf(0) }
    var blank by remember { mutableStateOf(false) }
    var showList by remember { mutableStateOf(false) }
    var streamFailed by remember { mutableStateOf(false) }
    val slide = slides.getOrNull(index)

    val next by rememberUpdatedState {
        blank = false
        if (index < slides.lastIndex) index++ else if (deck.loop) index = 0 else onFinished()
    }
    val previous = { blank = false; if (index > 0) index-- }

    // Remote control: report what is on screen, obey commands.
    val outline = remember(slides) { slides.map { it.listLabel() } }
    LaunchedEffect(index, blank) {
        if (report) {
            Remote.status.value = PlaybackStatus(
                module = Module.SLIDES, state = if (blank) "blank" else "playing", title = deck.name,
                label = slides.getOrNull(index)?.listLabel().orEmpty(), index = index, count = slides.size, outline = outline,
                refKind = "deck", refId = deck.id,
            )
        }
    }
    DisposableEffect(report) { onDispose { if (report) Remote.idle() } }
    LaunchedEffect(Unit) {
        Remote.commands.collect { c ->
            when (c) {
                RemoteCommand.Next -> next()
                RemoteCommand.Previous -> previous()
                is RemoteCommand.Jump -> { blank = false; showList = false; index = c.index.coerceIn(0, slides.lastIndex) }
                is RemoteCommand.Blank -> blank = c.on ?: !blank
                RemoteCommand.Stop -> onExit()
                else -> Unit
            }
        }
    }

    val bgPlayer = remember { ExoPlayer.Builder(context).build().apply { repeatMode = Player.REPEAT_MODE_ALL; volume = 0f } }
    val fgPlayer = remember { ExoPlayer.Builder(context).build() }
    val currentSlide by rememberUpdatedState(slide)
    DisposableEffect(fgPlayer) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) next()
            }

            override fun onPlayerError(error: PlaybackException) {
                val s = currentSlide
                if (s is DeckSlide.Stream) {
                    if (s.fallback == "hold") streamFailed = true else next()
                }
            }
        }
        fgPlayer.addListener(listener)
        onDispose { fgPlayer.release(); bgPlayer.release() }
    }

    val bg = resolveBackground(deck, slide)
    val bgVideoPath = (bg as? SlideBackground.Video)?.url?.let { cache.fileFor(it).takeIf { f -> f.exists() }?.path }
    var loadedBgPath by remember { mutableStateOf<String?>(null) }
    // The background video only restarts when the file changes, so slides that share one keep it playing.
    LaunchedEffect(bgVideoPath) {
        if (bgVideoPath == null) {
            bgPlayer.stop(); bgPlayer.clearMediaItems(); loadedBgPath = null
        } else if (bgVideoPath != loadedBgPath) {
            bgPlayer.setMediaItem(MediaItem.fromUri(Uri.fromFile(java.io.File(bgVideoPath))))
            bgPlayer.prepare(); bgPlayer.play(); loadedBgPath = bgVideoPath
        }
    }

    LaunchedEffect(streamFailed) {
        if (streamFailed) {
            delay(10_000)
            streamFailed = false
            next()
        }
    }

    LaunchedEffect(index) {
        streamFailed = false
        when (slide) {
            is DeckSlide.Media -> if (slide.mediaKind == "video") {
                fgPlayer.volume = if (slide.audio) 1f else 0f
                fgPlayer.setMediaItem(MediaItem.fromUri(Uri.fromFile(cache.fileFor(slide.url))))
                fgPlayer.prepare(); fgPlayer.play()
            } else { fgPlayer.stop(); fgPlayer.clearMediaItems() }
            is DeckSlide.Stream -> {
                fgPlayer.volume = if (slide.audio) 1f else 0f
                fgPlayer.setMediaItem(MediaItem.fromUri(slide.url))
                fgPlayer.prepare(); fgPlayer.play()
            }
            else -> { fgPlayer.stop(); fgPlayer.clearMediaItems() }
        }
        val seconds = when (slide) {
            is DeckSlide.Text -> slide.seconds
            is DeckSlide.Media -> if (slide.mediaKind == "image") slide.seconds else null
            is DeckSlide.Stream -> slide.seconds
            else -> null
        }
        if (seconds != null && seconds > 0) {
            delay(seconds * 1000L)
            next()
        }
    }

    // While blanked (or the slide list is open) the foreground video pauses; backgrounds keep running.
    LaunchedEffect(blank) {
        if (blank) fgPlayer.pause() else if (needsForegroundPlayer(slide)) fgPlayer.play()
    }

    BackHandler(onBack = { if (showList) showList = false else onExit() })
    KeepScreenOn()

    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    val style = remember(deck, slide) {
        val text = slide as? DeckSlide.Text
        deck.theme.toStyle(text?.align, text?.textColor)
    }
    val brand = LocalBrand.current

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                if (showList) return@onPreviewKeyEvent false // the list handles Up/Down/OK itself
                when (event.key) {
                    Key.DirectionRight, Key.MediaNext, Key.MediaFastForward -> { next(); true }
                    Key.DirectionLeft, Key.MediaPrevious, Key.MediaRewind -> { previous(); true }
                    Key.DirectionCenter, Key.Enter -> { showList = true; true }
                    Key.MediaPlayPause, Key.MediaPlay, Key.MediaPause -> { blank = !blank; true }
                    else -> false
                }
            },
    ) {
        BackgroundLayer(bg, cache, bgPlayer)

        if (needsForegroundPlayer(slide)) {
            val zoom = (slide as? DeckSlide.Media)?.fit == "cover"
            AndroidView(
                factory = { newPlayerView(it, fgPlayer, zoom) },
                update = { it.resizeMode = if (zoom) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT },
                modifier = Modifier.fillMaxSize(),
            )
        }

        androidx.compose.runtime.key(index) {
            when (slide) {
                is DeckSlide.Text -> TextSlideView(slide, style)
                is DeckSlide.Lyric -> LyricSlideView(slide, style)
                is DeckSlide.SongTitle -> SongTitleView(slide, style)
                is DeckSlide.Countdown -> CountdownView(slide, style, brand.accent, slide.audio?.let { cache.fileFor(it.url).takeIf { f -> f.exists() } }, blank) { next() }
                is DeckSlide.Media -> if (slide.mediaKind == "image") {
                    AsyncImage(
                        model = cache.fileFor(slide.url),
                        contentDescription = null,
                        contentScale = if (slide.fit == "cover") ContentScale.Crop else ContentScale.Fit,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                is DeckSlide.Stream -> if (streamFailed) {
                    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
                        Text("Waiting for the live feed…", style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 28.sp, color = Color.White, textAlign = TextAlign.Center))
                    }
                }
                is DeckSlide.Blank -> Box(Modifier.fillMaxSize().background(parseHexColor(slide.color) ?: Color.Black))
                else -> Unit
            }
        }

        if (deck.theme.logo.show) {
            val logo = brand.logoOn(if (style.color.isLight()) Color.Black else Color.White)
            if (logo != null) {
                val align = when (deck.theme.logo.position) {
                    "bottom_right" -> Alignment.BottomEnd
                    "top_left" -> Alignment.TopStart
                    "top_right" -> Alignment.TopEnd
                    else -> Alignment.BottomStart
                }
                AsyncImage(
                    model = logo,
                    contentDescription = brand.orgName,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.align(align).padding(horizontal = 40.dp, vertical = 24.dp).widthIn(max = 180.dp).fillMaxWidth(0.14f),
                )
            }
        }

        if (blank) Box(Modifier.fillMaxSize().background(Color.Black))

        if (showList) {
            SlideList(
                slides = slides,
                current = index,
                onPick = { i -> blank = false; index = i; showList = false },
                onClose = { showList = false },
            )
        }
    }
}

/** Jump to any slide: Up/Down to choose, OK to go, Back to close. */
@Composable
private fun SlideList(slides: List<DeckSlide>, current: Int, onPick: (Int) -> Unit, onClose: () -> Unit) {
    val state = rememberLazyListState(initialFirstVisibleItemIndex = (current - 2).coerceAtLeast(0))
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.82f)), contentAlignment = Alignment.Center) {
        Column(Modifier.widthIn(max = 640.dp).fillMaxWidth(0.8f)) {
            Text("Jump to a slide", style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 22.sp, color = Color.White), modifier = Modifier.padding(bottom = 12.dp))
            LazyColumn(state = state, modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp).heightIn(max = 420.dp)) {
                itemsIndexed(slides) { i, s ->
                    TvButton(
                        "${i + 1}.  ${s.listLabel()}${if (i == current) "   ◀ now" else ""}",
                        if (i == current) Modifier.fillMaxWidth().focusRequester(focus) else Modifier.fillMaxWidth(),
                    ) { onPick(i) }
                }
            }
            Text("OK to go  ·  Back to close", style = TextStyle(fontFamily = Lato, fontSize = 13.sp, color = Color.White.copy(alpha = 0.7f)))
        }
    }
    BackHandler(onBack = onClose)
}
