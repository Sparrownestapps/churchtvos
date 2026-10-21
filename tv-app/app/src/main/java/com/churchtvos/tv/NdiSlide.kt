package com.churchtvos.tv

import android.graphics.SurfaceTexture
import android.os.SystemClock
import android.view.Surface
import android.view.TextureView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.tv.material3.Text
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/**
 * EXPERIMENTAL: plays one NDI source as a slide. A TextureView is used (not a SurfaceView) so the picture rotates with the
 * rest of the UI on portrait screens (LocalRotated). Works in Kids/Signage playlists and Slides decks.
 *
 * In the store build there is no receiver: the slide shows its fallback message (or, for "skip", was never added).
 * [onUnavailable] is called once when the fallback is "skip" and the source did not appear within the wait time.
 */
@Composable
fun NdiSlideView(spec: NdiSpec, onUnavailable: () -> Unit) {
    val context = LocalContext.current
    val receiver = remember { createNdiReceiver(context) }
    var snapshot by remember { mutableStateOf(NdiSnapshot()) }
    val startedAt = remember { SystemClock.elapsedRealtime() }
    var lastGoodAt by remember { mutableLongStateOf(startedAt) }
    var action by remember { mutableStateOf(if (receiver == null) initialAction(spec) else NdiAction.WAIT) }
    val giveUp by rememberUpdatedState(onUnavailable)

    // The clock that decides between waiting, showing the message and skipping. A returning source always wins.
    LaunchedEffect(spec) {
        var skipped = false
        while (true) {
            val now = SystemClock.elapsedRealtime()
            if (receiver != null && snapshot.streaming) lastGoodAt = now
            val next = if (receiver == null) initialAction(spec) else ndiAction(spec, snapshot.streaming, now - lastGoodAt)
            if (next != action) action = next
            if (next == NdiAction.SKIP && !skipped) { skipped = true; giveUp() }
            delay(250)
        }
    }

    // Tell remotes what is on screen ("NDI: Main camera, live").
    LaunchedEffect(action) { Remote.ndiNote.value = ndiStatusNote(spec, action) }
    DisposableEffect(Unit) { onDispose { Remote.ndiNote.value = null; receiver?.stop() } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (receiver != null) {
            val ratio = if (snapshot.width > 0 && snapshot.height > 0) snapshot.width.toFloat() / snapshot.height else 0f
            AspectFrame(ratio, spec.fills, Modifier.fillMaxSize()) {
                AndroidView(
                    factory = { ctx ->
                        TextureView(ctx).apply {
                            isOpaque = true
                            surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                                private var surface: Surface? = null
                                override fun onSurfaceTextureAvailable(st: SurfaceTexture, w: Int, h: Int) {
                                    val s = Surface(st).also { surface = it }
                                    receiver.start(spec, s) { snapshot = it }
                                }
                                override fun onSurfaceTextureSizeChanged(st: SurfaceTexture, w: Int, h: Int) = Unit
                                override fun onSurfaceTextureDestroyed(st: SurfaceTexture): Boolean {
                                    receiver.stop()
                                    surface?.release()
                                    surface = null
                                    return true
                                }
                                override fun onSurfaceTextureUpdated(st: SurfaceTexture) = Unit
                            }
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        when (action) {
            NdiAction.WAIT -> if (receiver != null) Notice("Connecting to ${spec.source.ifBlank { "NDI source" }}…", small = true)
            NdiAction.SHOW_MESSAGE -> Box(Modifier.fillMaxSize().background(Color.Black)) { Notice(spec.messageText, small = false) }
            NdiAction.LIVE, NdiAction.SKIP -> Unit
        }
    }
}

private fun initialAction(spec: NdiSpec) = if (spec.fallback == "message") NdiAction.SHOW_MESSAGE else NdiAction.SKIP

@Composable
private fun Notice(text: String, small: Boolean) {
    Box(Modifier.fillMaxSize().padding(48.dp), contentAlignment = if (small) Alignment.BottomCenter else Alignment.Center) {
        Text(
            text,
            style = TextStyle(
                fontFamily = Lato,
                fontWeight = FontWeight.Bold,
                fontSize = if (small) 16.sp else 28.sp,
                color = Color.White.copy(alpha = if (small) 0.7f else 1f),
                textAlign = TextAlign.Center,
            ),
        )
    }
}

/** Sizes its child to the video's shape: "fit" shows it all, "fill" covers the box and crops. Unknown ratio fills the box. */
@Composable
private fun AspectFrame(ratio: Float, fill: Boolean, modifier: Modifier, content: @Composable () -> Unit) {
    Layout(content = content, modifier = modifier.clipToBounds()) { measurables, constraints ->
        val w = constraints.maxWidth
        val h = constraints.maxHeight
        val (cw, ch) = ndiFrameSize(w, h, ratio, fill)
        val placeable = measurables.first().measure(Constraints.fixed(cw, ch))
        layout(w, h) { placeable.place((w - cw) / 2, (h - ch) / 2) }
    }
}

/** The size the video is drawn at inside a w x h box. Pure, so it can be tested. */
fun ndiFrameSize(w: Int, h: Int, ratio: Float, fill: Boolean): Pair<Int, Int> {
    if (ratio <= 0f || w <= 0 || h <= 0) return w to h
    val byWidth = w to (w / ratio).roundToInt()
    val byHeight = (h * ratio).roundToInt() to h
    val widthFits = byWidth.second <= h
    return if (fill) (if (widthFits) byHeight else byWidth) else (if (widthFits) byWidth else byHeight)
}
