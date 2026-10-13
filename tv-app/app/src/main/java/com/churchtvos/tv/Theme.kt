package com.churchtvos.tv

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

/** A church's look on the TV: set in the dashboard under Settings → Branding. */
data class Brand(
    val primary: Color = Color(0xFF1B2A4A),
    val accent: Color = Color(0xFFF2A33A),
    val logoUrl: String? = null,
    val orgName: String = "Church TV OS",
)

val LocalBrand = compositionLocalOf { Brand() }

val BrandPrimary: Color @Composable get() = LocalBrand.current.primary
val BrandAccent: Color @Composable get() = LocalBrand.current.accent
val Greyscale = Color(0xFF58595B)
val Paper = Color(0xFFF4F5F7)

val Lato = FontFamily(
    Font(R.font.lato_regular),
    Font(R.font.lato_bold, FontWeight.Bold),
    Font(R.font.lato_black, FontWeight.Black),
)
val JuliusSansOne = FontFamily(Font(R.font.julius_sans_one))

private fun parseColor(hex: String?, fallback: Color): Color =
    runCatching { Color(android.graphics.Color.parseColor(hex)) }.getOrDefault(fallback)

fun DeviceState.brand(): Brand {
    val base = Brand()
    val b = organization?.branding
    return Brand(
        primary = parseColor(b?.primaryColor, base.primary),
        accent = parseColor(b?.accentColor, base.accent),
        logoUrl = b?.logoUrl,
        orgName = organization?.name ?: base.orgName,
    )
}

@Composable
fun BrandTheme(brand: Brand, content: @Composable () -> Unit) =
    CompositionLocalProvider(LocalBrand provides brand, content = content)
