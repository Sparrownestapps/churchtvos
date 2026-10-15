package com.churchtvos.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelTest {
    private val playlistJson = """
        {"id":"p","name":"Mixed","items":[
          {"type":"countdown","title":"Go","seconds":5},
          {"type":"sign","title":"Welcome","subtext":"Glad you're here","background":"#112233","seconds":12,"align":"left","logo":true},
          {"type":"stream","title":"Live","url":"https://example.com/live.m3u8","audio":true,"fallback":"hold"},
          {"type":"hologram","title":"From the future","whatever":1},
          {"type":"image","title":"Pic","url":"https://example.com/a.png"}
        ]}
    """.trimIndent()

    @Test
    fun unknownItemTypesAreSkippedNotFatal() {
        val playlist = AppJson.decodeFromString<Playlist>(playlistJson)
        assertEquals(5, playlist.items.size)
        assertTrue(playlist.items[3] is PlaylistItem.Unknown)
    }

    @Test
    fun signAndStreamDecode() {
        val items = AppJson.decodeFromString<Playlist>(playlistJson).items
        val sign = items[1] as PlaylistItem.Sign
        assertEquals("#112233", sign.background)
        assertEquals(12, sign.seconds)
        assertEquals("left", sign.align)
        assertTrue(sign.logo)
        val stream = items[2] as PlaylistItem.Stream
        assertEquals("hold", stream.fallback)
        assertTrue(stream.audio)
        assertEquals(null, stream.seconds)
    }

    @Test
    fun mediaUrlsIgnoreFeedsAndSigns() {
        val playlist = AppJson.decodeFromString<Playlist>(playlistJson)
        assertEquals(listOf("https://example.com/a.png"), playlist.mediaUrls)
    }

    @Test
    fun moduleRulesPickByDayAndTime() {
        // 2026-10-18 is a Sunday, 10:00 in Toronto (EDT, UTC-4) = 14:00Z
        val state = AppJson.decodeFromString<DeviceState>(
            """{"paired":true,"timezone":"America/Toronto","default_module":"signage",
                "module_rules":[{"module":"kids","days":[0],"start":"08:00:00","end":"13:00:00","priority":0}]}""",
        )
        val sunday10 = java.time.Instant.parse("2026-10-18T14:00:00Z").toEpochMilli()
        val monday10 = java.time.Instant.parse("2026-10-19T14:00:00Z").toEpochMilli()
        assertEquals("kids", state.moduleNow(sunday10))
        assertEquals("signage", state.moduleNow(monday10))
    }
}
