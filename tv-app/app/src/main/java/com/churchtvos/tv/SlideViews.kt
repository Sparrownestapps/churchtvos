package com.churchtvos.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/** How text looks on a slide: the theme with any per-slide overrides applied. */
data class SlideStyle(
    val titleFont: FontFamily,
    val bodyFont: FontFamily,
    val titleScale: Float,
    val bodyScale: Float,
    val color: Color,
    val center: Boolean,
    val position: String,
    val shadow: Shadow?,
    val marginPct: Float,
    val showLabels: Boolean,
) {
    val textAlign: TextAlign get() = if (center) TextAlign.Center else TextAlign.Start
    val horizontal: Alignment.Horizontal get() = if (center) Alignment.CenterHorizontally else Alignment.Start
    fun text(font: FontFamily, weight: FontWeight, alpha: Float = 1f) =
        TextStyle(fontFamily = font, fontWeight = weight, color = color.copy(alpha = alpha), textAlign = textAlign, lineHeight = 1.15f.em, shadow = shadow)
}

fun ThemeConfig.toStyle(slideAlign: String? = null, slideColor: String? = null): SlideStyle {
    val color = parseHexColor(slideColor) ?: parseHexColor(textColor) ?: Color.White
    val shadow = when {
        outline -> Shadow(Color.Black, Offset.Zero, 14f)
        shadow -> Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 3f), 10f)
        else -> null
    }
    return SlideStyle(
        titleFont = if (font == "julius") JuliusSansOne else Lato,
        bodyFont = Lato,
        titleScale = titleScale.coerceIn(0.5f, 1.5f),
        bodyScale = bodyScale.coerceIn(0.5f, 1.5f),
        color = color,
        center = (slideAlign ?: align ?: "center") != "left",
        position = position ?: "center",
        shadow = shadow,
        marginPct = margin.coerceIn(0f, 20f),
        showLabels = showLabels,
    )
}

@Composable
private fun FitText(
    text: String,
    style: TextStyle,
    height: Dp,
    minSp: Float,
    maxSp: Float,
    maxLines: Int,
    contentAlignment: Alignment,
) {
    Box(Modifier.fillMaxWidth().height(height), contentAlignment = contentAlignment) {
        BasicText(
            text,
            modifier = Modifier.fillMaxWidth(),
            style = style,
            maxLines = maxLines,
            autoSize = TextAutoSize.StepBased(minFontSize = minSp.sp, maxFontSize = maxSp.sp, stepSize = 2.sp),
        )
    }
}

private fun vertical(position: String) = when (position) {
    "top" -> Arrangement.Top
    "lower" -> Arrangement.Bottom
    else -> Arrangement.Center
}

/** Title and body text. Layouts: title_body, title, body, lower_third. */
@Composable
fun TextSlideView(slide: DeckSlide.Text, style: SlideStyle) {
    val hasTitle = !slide.title.isNullOrBlank() && slide.layout != "body"
    val hasBody = !slide.body.isNullOrBlank() && slide.layout != "title"
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val h = maxHeight
        val w = maxWidth
        val padH = w * (style.marginPct / 100f)
        val padV = h * (style.marginPct / 100f)
        if (slide.layout == "lower_third") {
            Box(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color.Black.copy(alpha = 0.45f))
                    .padding(horizontal = padH.coerceAtLeast(24.dp), vertical = 16.dp),
            ) {
                Column(horizontalAlignment = style.horizontal) {
                    if (hasTitle) FitText(slide.title!!, style.text(style.titleFont, FontWeight.Black), h * 0.14f, 20f, 70f * style.titleScale, 1, Alignment.BottomStart)
                    if (hasBody) FitText(slide.body!!, style.text(style.bodyFont, FontWeight.Normal), h * 0.12f, 16f, 40f * style.bodyScale, 2, Alignment.TopStart)
                }
            }
        } else {
            Column(
                Modifier.fillMaxSize().padding(horizontal = padH, vertical = padV),
                horizontalAlignment = style.horizontal,
                verticalArrangement = vertical(style.position),
            ) {
                if (hasTitle) {
                    val boxH = h * (if (hasBody) 0.34f else 0.6f) * (1f - 2 * style.marginPct / 100f).coerceAtLeast(0.6f)
                    FitText(slide.title!!, style.text(style.titleFont, FontWeight.Black), boxH, 28f, 150f * style.titleScale, 3, if (style.center) Alignment.BottomCenter else Alignment.BottomStart)
                }
                if (hasBody) {
                    val boxH = h * (if (hasTitle) 0.38f else 0.7f) * (1f - 2 * style.marginPct / 100f).coerceAtLeast(0.6f)
                    if (hasTitle) androidx.compose.foundation.layout.Spacer(Modifier.height(h * 0.02f))
                    FitText(slide.body!!, style.text(style.bodyFont, FontWeight.Normal), boxH, 20f, 72f * style.bodyScale, 12, if (hasTitle) (if (style.center) Alignment.TopCenter else Alignment.TopStart) else (if (style.center) Alignment.Center else Alignment.CenterStart))
                }
            }
        }
    }
}

/** One section of a song's words. */
@Composable
fun LyricSlideView(slide: DeckSlide.Lyric, style: SlideStyle) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val h = maxHeight
        val w = maxWidth
        Column(
            Modifier.fillMaxSize().padding(horizontal = w * (style.marginPct / 100f), vertical = h * (style.marginPct / 100f)),
            horizontalAlignment = style.horizontal,
            verticalArrangement = vertical(style.position),
        ) {
            if (style.showLabels && !slide.label.isNullOrBlank()) {
                BasicText(
                    slide.label.uppercase(),
                    modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                    style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 18.sp, letterSpacing = 3.sp, color = style.color.copy(alpha = 0.7f), textAlign = style.textAlign, shadow = style.shadow),
                )
            }
            FitText(slide.text, style.text(style.bodyFont, FontWeight.Bold), h * 0.62f, 24f, 86f * style.bodyScale, 8, if (style.center) Alignment.Center else Alignment.CenterStart)
        }
        BasicText(
            "${slide.song}  ·  ${slide.number}/${slide.count}",
            modifier = Modifier.align(Alignment.BottomEnd).padding(horizontal = 48.dp, vertical = 27.dp),
            style = TextStyle(fontFamily = Lato, fontSize = 12.sp, color = style.color.copy(alpha = 0.6f), shadow = style.shadow),
        )
    }
}

/** The song name before its words. Holds until Next. */
@Composable
fun SongTitleView(slide: DeckSlide.SongTitle, style: SlideStyle) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val h = maxHeight
        val w = maxWidth
        Column(
            Modifier.fillMaxSize().padding(horizontal = w * 0.08f, vertical = h * 0.08f),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            FitText(slide.title, style.text(style.titleFont, FontWeight.Black).copy(textAlign = TextAlign.Center), h * 0.40f, 28f, 140f * style.titleScale, 3, Alignment.BottomCenter)
            if (!slide.authors.isNullOrBlank()) {
                BasicText(slide.authors, Modifier.fillMaxWidth().padding(top = 8.dp), style = style.text(style.bodyFont, FontWeight.Normal, 0.85f).copy(fontSize = 26.sp, textAlign = TextAlign.Center), maxLines = 2)
            }
            val footer = listOfNotNull(slide.ccli?.takeIf { it.isNotBlank() }?.let { "CCLI Song # $it" }, slide.copyright?.takeIf { it.isNotBlank() }).joinToString("  ·  ")
            if (footer.isNotEmpty()) {
                BasicText(footer, Modifier.fillMaxWidth().padding(top = 24.dp), style = style.text(style.bodyFont, FontWeight.Normal, 0.6f).copy(fontSize = 14.sp, textAlign = TextAlign.Center), maxLines = 2)
            }
        }
    }
}

@Composable
fun CountdownView(slide: DeckSlide.Countdown, style: SlideStyle, accent: Color, audioFile: java.io.File?, paused: Boolean, onDone: () -> Unit) {
    val spec = CountdownSpec(slide.mode, slide.seconds, slide.until, slide.audio, slide.atZero, slide.ifPassed)
    CountdownRunner(spec, audioFile, paused, onDone) { time ->
        Box(Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 27.dp)) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                if (!slide.title.isNullOrBlank()) {
                    BasicText(
                        slide.title.uppercase(),
                        style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 22.sp, letterSpacing = 4.sp, color = accent, shadow = style.shadow),
                    )
                }
                BasicText(
                    time,
                    style = TextStyle(fontFamily = JuliusSansOne, fontSize = (160 * style.titleScale).sp, color = style.color, shadow = style.shadow),
                )
            }
        }
    }
}

/** True when the colour is light enough that dark text/logos read better on it. */
fun Color.isLight(): Boolean = luminance() > 0.5f
