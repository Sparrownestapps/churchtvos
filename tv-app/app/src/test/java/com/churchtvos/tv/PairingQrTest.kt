package com.churchtvos.tv

import com.google.zxing.BinaryBitmap
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PairingQrTest {
    @Test
    fun payloadIsUppercaseWithoutSpaces() {
        assertEquals("https://app.churchtvos.com/pair?code=TFWK5H", pairingQrPayload("TFWK5H"))
        assertEquals("https://app.churchtvos.com/pair?code=TFWK5H", pairingQrPayload("tfw k5h"))
        assertEquals("https://app.churchtvos.com/pair?code=TFWK5H", pairingQrPayload("TFW  K5H"))
    }

    @Test
    fun placeholderIsNotACode() {
        assertNull(pairingQrPayload("······"))
        assertNull(pairingQrPayload(""))
    }

    @Test
    fun matrixIsNonEmptySquareAndDecodesBackToThePayload() {
        val payload = pairingQrPayload("TFWK5H")!!
        val m = qrMatrix(payload)
        assertTrue(m.isNotEmpty() && m.size == m[0].size)
        assertTrue(m.any { row -> row.any { it } })
        // Render with a quiet zone at 8px per module and decode with zxing's reader.
        val scale = 8; val quiet = 4; val side = (m.size + quiet * 2) * scale
        val pixels = IntArray(side * side) { 0xFFFFFFFF.toInt() }
        for (y in m.indices) for (x in m.indices) if (m[y][x])
            for (dy in 0 until scale) for (dx in 0 until scale)
                pixels[((y + quiet) * scale + dy) * side + (x + quiet) * scale + dx] = 0xFF000000.toInt()
        val decoded = QRCodeReader().decode(BinaryBitmap(HybridBinarizer(RGBLuminanceSource(side, side, pixels)))).text
        assertEquals(payload, decoded)
    }
}
