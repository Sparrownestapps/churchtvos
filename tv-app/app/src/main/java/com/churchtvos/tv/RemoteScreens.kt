package com.churchtvos.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/** Waits (up to 30 s) for a deck's or playlist's files to finish downloading, then shows [content]. */
@Composable
fun WaitForMedia(urls: List<String>, cache: MediaCache, content: @Composable () -> Unit) {
    var waited by remember { mutableIntStateOf(0) }
    val ready = urls.all { cache.fileFor(it).exists() }
    LaunchedEffect(ready) {
        while (!ready && waited < 30) {
            delay(1_000)
            waited++
        }
    }
    if (ready || waited >= 30) content() else MessageScreen("Getting ready…", "Downloading what was just sent to this screen.")
}

/** A "play this now" request from a phone, the website or the Mac app. It replaces the schedule until it ends or is stopped. */
@Composable
fun OverrideScreen(override: OverrideInfo, state: TvUiState, cache: MediaCache, onDone: () -> Unit) {
    val deck = override.deck
    val playlist = override.playlist
    when {
        override.kind == "deck" && deck != null ->
            WaitForMedia(deck.mediaUrls, cache) { SlidesPlayer(deck, cache, onExit = onDone, onFinished = onDone) }
        override.kind == "playlist" && playlist != null ->
            WaitForMedia(playlist.mediaUrls, cache) {
                val slides = remember(playlist) { playlist.toSlides(cache) }
                PlayerScreen(slides, onExit = onDone, report = PlayerReport(Module.KIDS, playlist.name, "playlist", playlist.id))
            }
        else -> MessageScreen("Nothing to play", state.error)
    }
}

/** A message sign covering everything for a while (sent from a remote). Clears itself. */
@Composable
fun MessageOverlay(message: ActiveMessage?) {
    if (message == null) return
    LaunchedEffect(message) {
        val wait = message.untilMillis - System.currentTimeMillis()
        if (wait > 0) delay(wait)
        if (Remote.message.value == message) Remote.message.value = null
    }
    val bg = parseHexColor(message.background) ?: Color(0xFF1B2A4A)
    Box(Modifier.fillMaxSize().background(bg).padding(horizontal = 64.dp, vertical = 48.dp), contentAlignment = Alignment.Center) {
        BasicText(
            message.text,
            modifier = Modifier.fillMaxSize(),
            style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Black, color = textColorOn(bg), textAlign = TextAlign.Center, lineHeight = 1.15f.em),
            maxLines = 6,
            autoSize = TextAutoSize.StepBased(minFontSize = 24.sp, maxFontSize = 160.sp, stepSize = 2.sp),
        )
    }
}
