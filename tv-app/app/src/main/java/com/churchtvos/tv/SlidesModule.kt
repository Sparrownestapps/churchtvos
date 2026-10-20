package com.churchtvos.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.Text
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val whenFormatSlides = DateTimeFormatter.ofPattern("EEE MMM d · h:mm a").withZone(ZoneId.systemDefault())

/** The Slides module: shows the scheduled deck and plays it from the remote when Play is pressed. */
@Composable
fun SlidesModule(device: DeviceState, state: TvUiState, now: Instant, cache: MediaCache) {
    // Snapshot of the deck when Play was pressed, so a sync mid-service can't change it.
    var playing by remember { mutableStateOf<Deck?>(null) }
    var autoStartedFor by remember { mutableStateOf<String?>(null) } // see KidsModule: autoplay starts each scheduled item once
    val active = playing
    if (active != null) {
        SlidesPlayer(active, cache, onExit = { playing = null })
        return
    }

    val current = device.currentDeck(now)
    val schedule = current ?: device.nextDeck(now)
    val deck = schedule?.deck
    val ready = deck != null && deck.mediaUrls.all { cache.fileFor(it).exists() } && deck.playableSlides.isNotEmpty()
    val downloading = state.downloading
    LaunchedEffect(current?.id, ready, device.screen.autoplay) {
        if (device.screen.autoplay && current != null && ready && autoStartedFor != current.id) {
            autoStartedFor = current.id
            playing = deck
        }
    }
    DeckHomeScreen(
        site = device.site.orEmpty(),
        location = device.location.orEmpty(),
        heading = when {
            current != null -> "NOW SHOWING"
            schedule != null -> "UP NEXT · ${whenFormatSlides.format(schedule.start).uppercase()}"
            else -> "NOTHING SCHEDULED"
        },
        deck = deck,
        status = when {
            deck == null -> "Schedule a deck for this location in the dashboard."
            deck.playableSlides.isEmpty() -> "This deck has no slides yet."
            ready -> "✓ Ready to play"
            downloading != null -> "Downloading media… ${downloading.done + 1} of ${downloading.total}"
            state.failedDownloads > 0 -> "⚠ Some media couldn't download. Retrying…"
            else -> "Preparing media…"
        } + if (state.offline) "  ·  Offline, using saved schedule" else "",
        canPlay = ready,
        onPlay = { playing = deck },
    )
}

private fun DeckSlide.homeLabel(): Pair<String, String> = when (this) {
    is DeckSlide.Text -> "TEXT" to (title?.takeIf { it.isNotBlank() } ?: body?.lineSequence()?.firstOrNull().orEmpty())
    is DeckSlide.Media -> (if (mediaKind == "video") "VIDEO" else "PICTURE") to ""
    is DeckSlide.Countdown -> "COUNTDOWN" to (title ?: "")
    is DeckSlide.Stream -> "LIVE" to (title ?: "")
    is DeckSlide.Blank -> "BLANK" to ""
    is DeckSlide.SongTitle -> "SONG" to title
    is DeckSlide.Lyric -> "LYRICS" to "$song · ${label ?: "Part $number"}"
    is DeckSlide.Unknown -> "" to ""
}

@Composable
fun DeckHomeScreen(
    site: String,
    location: String,
    heading: String,
    deck: Deck?,
    status: String,
    canPlay: Boolean,
    onPlay: () -> Unit,
) {
    val playFocus = remember { FocusRequester() }
    LaunchedEffect(canPlay) { if (canPlay) playFocus.requestFocus() }
    val portrait = LocalRotated.current

    @Composable
    fun Identity() {
        Column {
            Text(site.uppercase(), style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = if (portrait) 18.sp else 14.sp, letterSpacing = 2.sp, color = BrandAccent))
            Text(location, style = TextStyle(fontFamily = JuliusSansOne, fontSize = if (portrait) 56.sp else 44.sp, color = BrandPrimary))
        }
    }

    @Composable
    fun Hint() {
        Text(
            "OK or Play to start  ·  Right / Left for next / back  ·  OK for the slide list  ·  Play/Pause for a black screen  ·  Back to stop",
            style = TextStyle(fontFamily = Lato, fontSize = if (portrait) 14.sp else 12.sp, color = Greyscale),
        )
    }

    @Composable
    fun Card(modifier: Modifier) {
        Column(modifier.background(Paper, RoundedCornerShape(16.dp)).padding(28.dp)) {
            Text(heading, style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 2.sp, color = BrandAccent))
            Text(deck?.name ?: "—", style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Black, fontSize = 28.sp, color = BrandPrimary))
            Spacer(Modifier.height(16.dp))
            deck?.playableSlides.orEmpty().take(if (portrait) 14 else 8).forEach { slide ->
                val (kind, label) = slide.homeLabel()
                Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(kind, style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 11.sp, letterSpacing = 1.sp, color = BrandAccent), modifier = Modifier.width(96.dp))
                    Text(label, style = TextStyle(fontFamily = Lato, fontSize = 16.sp, color = Greyscale), maxLines = 1)
                }
            }
            val total = deck?.playableSlides?.size ?: 0
            if (total > (if (portrait) 14 else 8)) {
                Text("+ ${total - (if (portrait) 14 else 8)} more", style = TextStyle(fontFamily = Lato, fontSize = 13.sp, color = Greyscale))
            }
            Spacer(Modifier.weight(1f))
            Text(status, style = TextStyle(fontFamily = Lato, fontSize = 13.sp, color = Greyscale))
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onPlay,
                enabled = canPlay,
                modifier = Modifier.focusRequester(playFocus),
                colors = ButtonDefaults.colors(
                    containerColor = BrandPrimary,
                    contentColor = Color.White,
                    focusedContainerColor = BrandAccent,
                    focusedContentColor = Color.White,
                    disabledContainerColor = BrandPrimary.copy(alpha = 0.2f),
                    disabledContentColor = Color.White,
                ),
            ) { Text("Play", style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 18.sp)) }
        }
    }

    if (portrait) {
        Column(Modifier.fillMaxSize().background(Color.White).padding(horizontal = 40.dp, vertical = 48.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            OrgLogo()
            Identity()
            Card(Modifier.weight(1f).fillMaxWidth())
            Hint()
        }
    } else {
        Row(Modifier.fillMaxSize().background(Color.White).padding(horizontal = 48.dp, vertical = 27.dp), horizontalArrangement = Arrangement.spacedBy(40.dp)) {
            Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.SpaceBetween) {
                OrgLogo()
                Identity()
                Hint()
            }
            Card(Modifier.weight(1f).fillMaxHeight())
        }
    }
}
