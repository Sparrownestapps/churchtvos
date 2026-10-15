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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage

fun parseHexColor(hex: String?): Color? =
    runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrNull()

/** Text colour for a background: dark text on light backgrounds (relative luminance above 0.5), else white. The dashboard preview uses the same threshold. */
fun textColorOn(background: Color): Color = if (background.luminance() > 0.5f) Color(0xFF111111) else Color.White

/** A sign built in the dashboard: coloured background, title, optional subtext, optional church logo. Text scales to fit in landscape and portrait. */
@Composable
fun SignSlide(slide: Slide.Sign) {
    val brand = LocalBrand.current
    val background = parseHexColor(slide.background) ?: brand.primary
    val foreground = textColorOn(background)
    val center = slide.align != "left"
    val align = if (center) TextAlign.Center else TextAlign.Start
    val logo = if (slide.logo) brand.logoOn(background) else null

    BoxWithConstraints(Modifier.fillMaxSize().background(background)) {
        val h = maxHeight
        val w = maxWidth
        val pad = h * 0.08f
        Column(
            Modifier.fillMaxSize().padding(horizontal = w * 0.07f, vertical = pad),
            horizontalAlignment = if (center) Alignment.CenterHorizontally else Alignment.Start,
        ) {
            if (logo != null) {
                AsyncImage(
                    model = logo,
                    contentDescription = brand.orgName,
                    contentScale = ContentScale.Fit,
                    alignment = if (center) Alignment.Center else Alignment.CenterStart,
                    modifier = Modifier.fillMaxWidth().height(h * 0.14f).clip(androidx.compose.foundation.shape.RoundedCornerShape(4.dp)),
                )
            }
            val hasSub = slide.subtext.isNotBlank()
            val titleBox = h * (if (hasSub) 0.42f else 0.62f)
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = if (center) Alignment.Center else Alignment.CenterStart) {
                Column(horizontalAlignment = if (center) Alignment.CenterHorizontally else Alignment.Start) {
                    BasicText(
                        slide.title,
                        modifier = Modifier.fillMaxWidth().height(titleBox),
                        style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Black, color = foreground, textAlign = align, lineHeight = 1.1f.em),
                        maxLines = 3,
                        autoSize = TextAutoSize.StepBased(minFontSize = 28.sp, maxFontSize = 160.sp, stepSize = 2.sp),
                    )
                    if (hasSub) {
                        BasicText(
                            slide.subtext,
                            modifier = Modifier.fillMaxWidth().height(h * 0.24f).padding(top = 12.dp),
                            style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Normal, color = foreground.copy(alpha = 0.9f), textAlign = align, lineHeight = 1.2f.em),
                            maxLines = 4,
                            autoSize = TextAutoSize.StepBased(minFontSize = 18.sp, maxFontSize = 72.sp, stepSize = 2.sp),
                        )
                    }
                }
            }
        }
    }
}
