package com.churchtvos.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Text

@Composable
fun PairingScreen(code: String, offline: Boolean) {
    BrandedScreen {
        Text("Pair this TV", style = TextStyle(fontFamily = JuliusSansOne, fontSize = 40.sp, color = BrandPrimary))
        Spacer(Modifier.height(20.dp))
        Text(
            code.chunked(3).joinToString("  "),
            style = TextStyle(fontFamily = Lato, fontWeight = FontWeight.Black, fontSize = 88.sp, letterSpacing = 10.sp, color = Color.White),
            modifier = Modifier
                .background(BrandPrimary, RoundedCornerShape(16.dp))
                .padding(horizontal = 40.dp, vertical = 8.dp),
        )
        Spacer(Modifier.height(24.dp))
        Text(
            "In the Church TV OS dashboard ($DASHBOARD_HOST),\ngo to Screens → Pair a TV, enter this code and choose the location.",
            style = TextStyle(fontFamily = Lato, fontSize = 18.sp, lineHeight = 28.sp, color = Greyscale, textAlign = TextAlign.Center),
        )
        if (offline) {
            Spacer(Modifier.height(16.dp))
            Text("⚠ Can't reach the internet. Check this TV's Wi-Fi.", style = TextStyle(fontFamily = Lato, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = BrandAccent))
        }
    }
}

@Composable
fun MessageScreen(title: String, detail: String?) {
    BrandedScreen {
        Text(title, style = TextStyle(fontFamily = JuliusSansOne, fontSize = 40.sp, color = BrandPrimary))
        if (detail != null) {
            Spacer(Modifier.height(12.dp))
            Text(detail, style = TextStyle(fontFamily = Lato, fontSize = 14.sp, color = Greyscale, textAlign = TextAlign.Center))
        }
    }
}

@Composable
private fun BrandedScreen(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.White).padding(horizontal = 48.dp, vertical = 27.dp)) {
        OrgLogo()
        Column(
            Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) { content() }
    }
}
