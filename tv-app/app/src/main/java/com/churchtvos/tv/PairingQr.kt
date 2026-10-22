package com.churchtvos.tv

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel

/**
 * The pairing QR contract (shared with the iOS app and the dashboard's /pair page):
 * the QR encodes exactly https://app.churchtvos.com/pair?code=<CODE>, with the 6 characters uppercase and no spaces.
 */
fun pairingQrPayload(code: String): String? {
    val clean = code.filterNot { it.isWhitespace() }.uppercase()
    // The placeholder shown before a code arrives ("······") is not a code, so no QR yet.
    if (clean.length != 6 || !clean.all { it in 'A'..'Z' || it in '0'..'9' }) return null
    return "https://$DASHBOARD_HOST/pair?code=$clean"
}

/** QR modules (true = dark) for [text], without any quiet zone. Medium error correction keeps it sparse enough to scan from across a room. */
fun qrMatrix(text: String): Array<BooleanArray> {
    val hints = mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0)
    val m = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, hints)
    return Array(m.height) { y -> BooleanArray(m.width) { x -> m.get(x, y) } }
}

/** Black modules on a white tile with a 4-module quiet zone, as the QR spec requires. */
@Composable
fun PairingQr(code: String, size: Dp) {
    val payload = pairingQrPayload(code) ?: return
    val matrix = remember(payload) { qrMatrix(payload) }
    val quiet = 4
    val modules = matrix.size + quiet * 2
    Box(Modifier.size(size).background(Color.White, RoundedCornerShape(4.dp)).padding(0.dp)) {
        Canvas(Modifier.size(size)) {
            val cell = this.size.minDimension / modules
            drawRect(Color.White, size = this.size)
            for (y in matrix.indices) for (x in matrix[y].indices) {
                if (matrix[y][x]) drawRect(
                    Color.Black,
                    topLeft = Offset((x + quiet) * cell, (y + quiet) * cell),
                    size = Size(cell + 0.5f, cell + 0.5f), // slight overlap avoids hairline gaps between modules
                )
            }
        }
    }
}
