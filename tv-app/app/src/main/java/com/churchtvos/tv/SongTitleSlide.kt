package com.churchtvos.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/**
 * The song name before the words, in the church's primary colour. It has no timer: it stays up until the leader
 * presses Next. Authors and the CCLI song number appear underneath when the song has them.
 */
@Composable
fun SongTitleSlide(slide: Slide.SongTitle) {
    BoxWithConstraints(Modifier.fillMaxSize().background(BrandPrimary)) {
        val h = maxHeight
        val w = maxWidth
        Column(
            Modifier.fillMaxSize().padding(horizontal = w * 0.08f, vertical = h * 0.08f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
        ) {
            BasicText(
                slide.title,
                modifier = Modifier.fillMaxWidth().height(h * 0.40f),
                style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Black, color = Color.White, textAlign = TextAlign.Center, lineHeight = 1.1f.em),
                maxLines = 3,
                autoSize = TextAutoSize.StepBased(minFontSize = 28.sp, maxFontSize = 140.sp, stepSize = 2.sp),
            )
            if (!slide.authors.isNullOrBlank()) {
                BasicText(
                    slide.authors,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    style = TextStyle(fontFamily = Lato, fontSize = 26.sp, color = Color.White.copy(alpha = 0.85f), textAlign = TextAlign.Center),
                    maxLines = 2,
                )
            }
            val footer = listOfNotNull(
                slide.ccli?.takeIf { it.isNotBlank() }?.let { "CCLI Song # $it" },
                slide.copyright?.takeIf { it.isNotBlank() },
            ).joinToString("  ·  ")
            if (footer.isNotEmpty()) {
                BasicText(
                    footer,
                    modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
                    style = TextStyle(fontFamily = Lato, fontSize = 14.sp, color = Color.White.copy(alpha = 0.6f), textAlign = TextAlign.Center),
                    maxLines = 2,
                )
            }
        }
    }
}
