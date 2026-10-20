package com.churchtvos.tv

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Button
import androidx.tv.material3.ButtonDefaults
import androidx.tv.material3.Text

@Composable
internal fun TvButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = modifier,
        colors = ButtonDefaults.colors(
            containerColor = BrandPrimary,
            contentColor = Color.White,
            focusedContainerColor = BrandAccent,
            focusedContentColor = Color.White,
        ),
    ) { Text(text, style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Bold, fontSize = 18.sp)) }
}

@Composable
private fun SettingsFrame(title: String, content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxSize().background(Color.White).padding(horizontal = 48.dp, vertical = 27.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(title, style = TextStyle(fontFamily = JuliusSansOne, fontSize = 40.sp, color = BrandPrimary, textAlign = TextAlign.Center))
        Spacer(Modifier.height(24.dp))
        content()
    }
}

private val body = TextStyle(fontFamily = Lato, fontSize = 18.sp, lineHeight = 28.sp, color = Greyscale, textAlign = TextAlign.Center)

/** Opened with the remote's Menu button (or the Settings button on the pairing screen). */
@Composable
fun SettingsScreen(
    autoLaunch: Boolean,
    autoLaunchSupported: Boolean,
    paired: Boolean,
    detail: String,
    onToggleAutoLaunch: () -> Unit,
    onDemo: () -> Unit,
    onClose: () -> Unit,
) {
    BackHandler(onBack = onClose)
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    SettingsFrame("Settings") {
        if (paired && autoLaunchSupported) {
            Text(
                if (autoLaunch) "Church TV OS opens by itself when this TV turns on." else "Church TV OS does not open by itself. You'll need to start it from the Fire TV home screen.",
                style = body,
            )
            Spacer(Modifier.height(16.dp))
            TvButton(
                if (autoLaunch) "Auto-launch: ON (press to turn off)" else "Auto-launch: OFF (press to turn on)",
                Modifier.focusRequester(focus),
                onToggleAutoLaunch,
            )
            Spacer(Modifier.height(12.dp))
            TvButton("Demo mode", onClick = onDemo)
        } else {
            if (paired) {
                Text("Auto-launch isn't available on this device: its system doesn't let apps open themselves. Start Church TV OS from the home screen.", style = body)
                Spacer(Modifier.height(16.dp))
            }
            TvButton("Demo mode", Modifier.focusRequester(focus), onDemo)
        }
        Spacer(Modifier.height(12.dp))
        TvButton("Close", onClick = onClose)
        Spacer(Modifier.height(20.dp))
        Text(detail, style = TextStyle(fontFamily = Lato, fontSize = 13.sp, color = Greyscale, textAlign = TextAlign.Center))
    }
}

/** Asked once, right after a TV is paired. */
@Composable
fun AutoLaunchPrompt(onAnswer: (Boolean) -> Unit) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    SettingsFrame("Open automatically?") {
        Text(
            "Should Church TV OS start by itself whenever this TV is switched on?\nYou can change this later: press the Menu button on the remote.",
            style = body,
        )
        Spacer(Modifier.height(20.dp))
        TvButton("Yes, open automatically", Modifier.focusRequester(focus)) { onAnswer(true) }
        Spacer(Modifier.height(12.dp))
        TvButton("Not now") { onAnswer(false) }
    }
}

/** Demo mode picker. */
@Composable
fun DemoMenu(onPick: (String) -> Unit, onClose: () -> Unit) {
    BackHandler(onBack = onClose)
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    SettingsFrame("Demo mode") {
        Text("Sample content, no account needed. Press Back to leave a demo.", style = body)
        Spacer(Modifier.height(20.dp))
        TvButton("Kids demo (countdown, lyrics)", Modifier.focusRequester(focus)) { onPick(Demo.KIDS) }
        Spacer(Modifier.height(12.dp))
        TvButton("Signage demo (looping slides)") { onPick(Demo.SIGNAGE) }
        Spacer(Modifier.height(12.dp))
        TvButton("Back", onClick = onClose)
    }
}
