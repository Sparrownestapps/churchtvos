package com.churchtvos.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.Text
import coil3.compose.AsyncImage

@Composable
fun HomeScreen(
    site: String,
    location: String,
    heading: String,
    playlist: Playlist?,
    status: String,
    canPlay: Boolean,
    onPlay: () -> Unit,
) {
    val playFocus = remember { FocusRequester() }
    LaunchedEffect(canPlay) {
        if (canPlay) playFocus.requestFocus()
    }
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
            "OK or Play to start  ·  Left / Right to move between slides  ·  Back to stop",
            style = TextStyle(fontFamily = Lato, fontSize = if (portrait) 14.sp else 12.sp, color = Greyscale),
        )
    }

    @Composable
    fun PlaylistCard(modifier: Modifier) {
        Column(
            modifier
                .background(Paper, RoundedCornerShape(16.dp))
                .padding(28.dp),
        ) {
            Text(heading, style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 12.sp, letterSpacing = 2.sp, color = BrandAccent))
            Text(playlist?.name ?: "—", style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Black, fontSize = 28.sp, color = BrandPrimary))
            Spacer(Modifier.height(16.dp))
            playlist?.items.orEmpty().filter { it !is PlaylistItem.Unknown }.take(if (portrait) 14 else 8).forEach { item ->
                Row(Modifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        item.kindLabel,
                        style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 11.sp, letterSpacing = 1.sp, color = BrandAccent),
                        modifier = Modifier.width(96.dp),
                    )
                    Text(item.title, style = TextStyle(fontFamily = Lato, fontSize = 16.sp, color = Greyscale))
                }
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
            ) {
                Text("Play", style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 18.sp))
            }
        }
    }

    // 48dp/27dp keeps everything inside the TV-safe area (5% overscan).
    if (portrait) {
        // A portrait-mounted TV: one column, logo and place on top, the playlist card filling the rest.
        Column(
            Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(horizontal = 40.dp, vertical = 48.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            OrgLogo()
            Identity()
            PlaylistCard(Modifier.weight(1f).fillMaxWidth())
            Hint()
        }
    } else {
        Row(
            Modifier
                .fillMaxSize()
                .background(Color.White)
                .padding(horizontal = 48.dp, vertical = 27.dp),
            horizontalArrangement = Arrangement.spacedBy(40.dp),
        ) {
            Column(
                Modifier.weight(1f).fillMaxHeight(),
                verticalArrangement = Arrangement.SpaceBetween,
            ) {
                OrgLogo()
                Identity()
                Hint()
            }
            PlaylistCard(Modifier.weight(1f).fillMaxHeight())
        }
    }
}

/** Full-screen logo on the brand's primary colour. */
@Composable
fun SplashScreen() {
    val brand = LocalBrand.current
    val logo = brand.logoOn(brand.primary)
    Box(Modifier.fillMaxSize().background(brand.primary), contentAlignment = Alignment.Center) {
        if (logo != null) {
            AsyncImage(
                model = logo,
                contentDescription = brand.orgName,
                contentScale = ContentScale.Fit,
                modifier = Modifier.fillMaxWidth(0.55f).fillMaxHeight(0.5f),
            )
        } else {
            Text(
                brand.orgName.uppercase(),
                style = TextStyle(fontFamily = JuliusSansOne, fontSize = 56.sp, letterSpacing = 6.sp, color = Color.White, textAlign = TextAlign.Center),
            )
        }
    }
}

/** The church's logo, or its name when no logo is set. 300dp keeps it legible from across a room. */
@Composable
fun OrgLogo(modifier: Modifier = Modifier) {
    val brand = LocalBrand.current
    val logo = brand.logoOn(Color.White)
    if (logo != null) {
        AsyncImage(
            model = logo,
            contentDescription = brand.orgName,
            contentScale = ContentScale.Fit,
            alignment = Alignment.CenterStart,
            modifier = modifier.width(300.dp).height(72.dp),
        )
    } else {
        Text(
            brand.orgName.uppercase(),
            style = TextStyle(fontFamily = JuliusSansOne, fontSize = 22.sp, letterSpacing = 3.sp, color = BrandPrimary),
            modifier = modifier,
        )
    }
}

private val PlaylistItem.kindLabel: String
    get() = when (this) {
        is PlaylistItem.Video -> "VIDEO"
        is PlaylistItem.Image -> "SLIDE"
        is PlaylistItem.Countdown -> "COUNTDOWN"
        is PlaylistItem.Lyrics -> "LYRICS"
        is PlaylistItem.YouTube -> if (videoId == null) "LIVE" else "YOUTUBE"
        is PlaylistItem.Sign -> "SIGN"
        is PlaylistItem.Stream -> "STREAM"
        is PlaylistItem.Ndi -> "NDI"
        is PlaylistItem.Unknown -> "—"
    }
