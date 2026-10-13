package com.churchtvos.tv

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints

/** True when the whole UI is turned for a portrait-mounted TV (video then needs a rotatable surface). */
val LocalRotated = compositionLocalOf { false }

/**
 * Fire TV always outputs landscape, so for a TV mounted upright we lay the content out sideways
 * (width and height swapped) and turn it a quarter turn. "portrait" turns clockwise (TV's left edge
 * at the bottom); "portrait_flipped" turns the other way.
 */
@Composable
fun Oriented(orientation: String, content: @Composable () -> Unit) {
    if (orientation != "portrait" && orientation != "portrait_flipped") {
        content()
        return
    }
    val angle = if (orientation == "portrait") 90f else 270f
    Box(
        Modifier.layout { measurable, constraints ->
            val placeable = measurable.measure(Constraints.fixed(constraints.maxHeight, constraints.maxWidth))
            layout(constraints.maxWidth, constraints.maxHeight) {
                placeable.placeWithLayer(
                    (constraints.maxWidth - placeable.width) / 2,
                    (constraints.maxHeight - placeable.height) / 2,
                ) { rotationZ = angle }
            }
        },
    ) {
        CompositionLocalProvider(LocalRotated provides true, content = content)
    }
}
