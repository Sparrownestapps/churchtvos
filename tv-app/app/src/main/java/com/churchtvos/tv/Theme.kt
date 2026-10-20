package com.churchtvos.tv

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight

/** A church's look on the TV: set in the dashboard under Settings → Branding. */
data class Brand(
    val primary: Color = Color(0xFF1B2A4A),
    val accent: Color = Color(0xFFF2A33A),
    val logoUrl: String? = null,
    val logoDarkUrl: String? = null,
    val orgName: String = "Church TV OS",
    val splashSeconds: Int? = null, // null = no splash
) {
    /** Logo for [background]: the dark-background logo on dark colours, else the normal one (falling back either way). */
    fun logoOn(background: Color): String? =
        if (background.luminance() < 0.4f) logoDarkUrl ?: logoUrl else logoUrl ?: logoDarkUrl
}

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

/** The church's look, with [module]'s own settings (if any) laid over it. */
fun DeviceState.brand(module: String? = null): Brand {
    val base = Brand()
    val org = organization?.branding
    val own = when (module) {
        Module.KIDS -> org?.modules?.kids
        Module.SIGNAGE -> org?.modules?.signage
        Module.SLIDES -> org?.modules?.slides
        else -> null
    }
    val splash = SplashInfo(
        enabled = own?.splash?.enabled ?: org?.splash?.enabled,
        seconds = own?.splash?.seconds ?: org?.splash?.seconds,
    )
    return Brand(
        primary = parseColor(own?.primaryColor ?: org?.primaryColor, base.primary),
        accent = parseColor(own?.accentColor ?: org?.accentColor, base.accent),
        logoUrl = own?.logoUrl ?: org?.logoUrl,
        logoDarkUrl = own?.logoDarkUrl ?: org?.logoDarkUrl,
        orgName = organization?.name ?: base.orgName,
        splashSeconds = if (splash.enabled == true) (splash.seconds ?: 5).coerceIn(2, 30) else null,
    )
}

@Composable
fun BrandTheme(brand: Brand, content: @Composable () -> Unit) =
    CompositionLocalProvider(LocalBrand provides brand, content = content)
