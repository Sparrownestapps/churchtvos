package com.churchtvos.tv

import android.net.Uri
import android.view.LayoutInflater
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalView
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
import kotlinx.coroutines.delay

/** [onExit] is Back; [onFinished] is reaching the end of the slides (signage loops, demo restarts). */
@Composable
fun PlayerScreen(slides: List<Slide>, onExit: () -> Unit, onFinished: () -> Unit = onExit) {
    val context = LocalContext.current
    val rotated = LocalRotated.current
    var index by remember { mutableIntStateOf(0) }
    val slide = slides.getOrNull(index)

    val next by rememberUpdatedState {
        if (index < slides.lastIndex) index++ else onFinished()
    }
    val previous = { if (index > 0) index-- }

    val currentSlide by rememberUpdatedState(slide)
    var streamFailed by remember { mutableStateOf(false) }

    val player = remember { ExoPlayer.Builder(context).build() }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) next()
            }

            // A dead or unreachable live stream never leaves a blank room: skip it, or hold a notice for a few seconds then skip.
            override fun onPlayerError(error: PlaybackException) {
                val s = currentSlide
                if (s is Slide.Stream) {
                    if (s.fallback == "hold") streamFailed = true else next()
                }
            }
        }
        player.addListener(listener)
        onDispose { player.release() }
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
        if (slide is Slide.Video) {
            player.volume = 1f
            player.setMediaItem(MediaItem.fromUri(Uri.fromFile(slide.file)))
            player.prepare()
            player.play()
        } else if (slide is Slide.Stream) {
            player.volume = if (slide.audio) 1f else 0f
            player.setMediaItem(MediaItem.fromUri(slide.url))
            player.prepare()
            player.play()
        } else {
            player.stop()
            player.clearMediaItems()
        }
        if (slide is Slide.Image && slide.seconds != null) {
            delay(slide.seconds * 1000L)
            next()
        }
        if (slide is Slide.Bundled) {
            delay(slide.seconds * 1000L)
            next()
        }
        if (slide is Slide.Sign) {
            delay(slide.seconds * 1000L)
            next()
        }
        if (slide is Slide.Stream && slide.seconds != null) {
            delay(slide.seconds * 1000L)
            next()
        }
    }

    BackHandler(onBack = onExit)
    KeepScreenOn()

    val youtube = remember(index) { YouTubeController() }

    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    Box(
        Modifier
            .fillMaxSize()
            // YouTube's video layer sits behind the window, so nothing opaque may be drawn over it.
            .background(if (slide is Slide.YouTube) Color.Transparent else Color.Black)
            .focusRequester(focus)
            .focusable()
            .onPreviewKeyEvent { event ->
                if (event.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (event.key) {
                    Key.DirectionRight, Key.MediaNext, Key.MediaFastForward -> { next(); true }
                    Key.DirectionLeft, Key.MediaPrevious, Key.MediaRewind -> { previous(); true }
                    Key.DirectionCenter, Key.Enter, Key.MediaPlayPause -> {
                        if (slide is Slide.Video || slide is Slide.Stream) player.playWhenReady = !player.playWhenReady
                        if (slide is Slide.YouTube) youtube.togglePause()
                        true
                    }
                    else -> false
                }
            },
    ) {
        // Kept mounted so switching between videos never flashes, but removed for YouTube:
        // its own video surface would otherwise sit underneath this one and play as a black screen.
        if (slide !is Slide.YouTube) AndroidView(
            factory = {
                val view = if (rotated) {
                    LayoutInflater.from(it).inflate(R.layout.player_texture, null) as PlayerView
                } else {
                    PlayerView(it).apply {
                        useController = false
                        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    }
                }
                view.also { v -> v.player = player }
            },
            modifier = Modifier.fillMaxSize(),
        )

        key(index) {
            when (slide) {
                is Slide.Image -> AsyncImage(
                    model = slide.file,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize().background(Color.Black),
                )
                is Slide.Bundled -> Image(
                    painter = painterResource(slide.res),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier.fillMaxSize().background(Color.Black),
                )
                is Slide.Countdown -> CountdownSlide(slide, onDone = { next() })
                is Slide.Lyric -> LyricSlide(slide)
                is Slide.YouTube -> YouTubeSlide(slide, youtube, onEnded = { next() })
                is Slide.Sign -> SignSlide(slide)
                is Slide.Stream -> if (streamFailed) StreamNotice(slide)
                is Slide.Video, null -> Unit
            }
        }
    }
}

@Composable
private fun StreamNotice(slide: Slide.Stream) {
    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        Text(
            "Waiting for the live feed…",
            style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 28.sp, color = Color.White, textAlign = TextAlign.Center),
        )
    }
}

@Composable
private fun CountdownSlide(slide: Slide.Countdown, onDone: () -> Unit) {
    var remaining by remember { mutableIntStateOf(slide.seconds) }
    LaunchedEffect(Unit) {
        while (remaining > 0) {
            delay(1_000)
            remaining--
        }
        onDone()
    }
    Box(Modifier.fillMaxSize().background(BrandPrimary).padding(horizontal = 48.dp, vertical = 27.dp)) {
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(slide.title.uppercase(), style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 22.sp, letterSpacing = 4.sp, color = BrandAccent))
            Text(
                "%d:%02d".format(remaining / 60, remaining % 60),
                style = TextStyle(fontFamily = JuliusSansOne, fontSize = 160.sp, color = Color.White),
            )
        }
    }
}

@Composable
private fun LyricSlide(slide: Slide.Lyric) {
    Box(Modifier.fillMaxSize().background(BrandPrimary).padding(horizontal = 48.dp, vertical = 27.dp)) {
        Text(
            slide.text,
            style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 40.sp, lineHeight = 54.sp, color = Color.White, textAlign = TextAlign.Center),
            modifier = Modifier.align(Alignment.Center),
        )
        Text(
            "${slide.song}  ·  ${slide.number}/${slide.count}",
            style = TextStyle(fontFamily = Lato, fontSize = 12.sp, color = Color.White.copy(alpha = 0.6f)),
            modifier = Modifier.align(Alignment.BottomEnd),
        )
    }
}

@Composable
private fun KeepScreenOn() {
    val view = LocalView.current
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
}
