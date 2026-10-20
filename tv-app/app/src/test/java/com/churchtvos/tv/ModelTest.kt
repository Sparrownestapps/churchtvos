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

    @Test
    fun lyricsWithTitleSlideComeFirstAndOldShapeStillWorks() {
        val json = """{"id":"p","name":"S","items":[
          {"type":"lyrics","title":"Great Are You Lord","slides":["a","b"],"labels":["Verse 1","Chorus"],"show_title":true,"authors":"Smith","ccli":"123","copyright":"(c) X"},
          {"type":"lyrics","title":"Old","slides":["x"]}]}"""
        val items = AppJson.decodeFromString<Playlist>(json).items
        val withTitle = (items[0] as PlaylistItem.Lyrics).toLyricSlides()
        assertEquals(3, withTitle.size)
        val title = withTitle[0] as Slide.SongTitle
        assertEquals("Great Are You Lord", title.title)
        assertEquals("123", title.ccli)
        assertEquals("a", (withTitle[1] as Slide.Lyric).text)
        assertEquals(2, (withTitle[2] as Slide.Lyric).number)
        val old = (items[1] as PlaylistItem.Lyrics).toLyricSlides()
        assertEquals(1, old.size)
        assertTrue(old[0] is Slide.Lyric)
    }

    private val deckJson = """
        {"id":"d","name":"Sunday","loop":true,
         "theme":{"font":"julius","title_scale":1.2,"text_color":"#FFFFFF","position":"lower","background":{"type":"video","url":"https://x/bg.mp4","dim":0.4}},
         "background":{"type":"gradient","color":"#112233","color2":"#000000","angle":90},
         "slides":[
          {"id":"a","kind":"text","title":"Welcome","body":"Hello","layout":"lower_third","background":{"type":"image","url":"https://x/a.jpg","fit":"cover","dim":0.3}},
          {"kind":"song_title","title":"Song","authors":"Auth","ccli":"123"},
          {"kind":"lyric","song":"Song","text":"line","label":"Verse 1","number":1,"count":2},
          {"id":"m","kind":"media","url":"https://x/p.png","media_kind":"image","seconds":8},
          {"id":"c","kind":"countdown","seconds":90},
          {"id":"s","kind":"stream","url":"https://x/live.m3u8"},
          {"id":"b","kind":"blank"},
          {"id":"z","kind":"hologram","whatever":1},
          {"id":"y","kind":"text","title":"Odd bg","background":{"type":"plasma"}}
         ]}
    """.trimIndent()

    @Test
    fun deckDecodesAllKindsAndSkipsUnknown() {
        val deck = AppJson.decodeFromString<Deck>(deckJson)
        assertEquals(9, deck.slides.size)
        assertTrue(deck.slides[7] is DeckSlide.Unknown)
        assertEquals(8, deck.playableSlides.size)
        assertTrue(deck.loop)
        assertEquals("julius", deck.theme.font)
        assertEquals(1.2f, deck.theme.titleScale)
        assertTrue(deck.theme.background is SlideBackground.Video)
        assertTrue(deck.background is SlideBackground.Gradient)
        val text = deck.slides[0] as DeckSlide.Text
        assertEquals("lower_third", text.layout)
        assertEquals(0.3f, (text.background as SlideBackground.Image).dim)
        assertTrue((deck.slides[8] as DeckSlide.Text).background is SlideBackground.Unknown)
        assertEquals(8, (deck.slides[3] as DeckSlide.Media).seconds)
        assertEquals(1, (deck.slides[2] as DeckSlide.Lyric).number)
    }

    @Test
    fun deckMediaUrlsCoverBackgroundsAndMedia() {
        val deck = AppJson.decodeFromString<Deck>(deckJson)
        assertEquals(setOf("https://x/bg.mp4", "https://x/a.jpg", "https://x/p.png"), deck.mediaUrls.toSet())
    }

    @Test
    fun deviceStateCarriesSlidesSchedules() {
        val state = AppJson.decodeFromString<DeviceState>(
            """{"paired":true,"enabled_modules":["slides"],"slides":{"schedules":[
                {"id":"x","starts_at":"2026-10-18T13:00:00+00:00","ends_at":"2026-10-18T14:00:00+00:00","deck":{"id":"d","name":"S","slides":[]}}]}}""",
        )
        val inside = java.time.Instant.parse("2026-10-18T13:30:00Z")
        assertEquals("S", state.currentDeck(inside)?.deck?.name)
        assertEquals(null, state.currentDeck(java.time.Instant.parse("2026-10-18T15:00:00Z")))
    }

    @Test
    fun countdownTimeFormatAndFade() {
        assertEquals("5:00", formatCountdown(300_000))
        assertEquals("0:07", formatCountdown(6_100))
        assertEquals("0:00", formatCountdown(0))
        assertEquals("1:05:00", formatCountdown(3_900_000))
        assertEquals(1f, fadeFactor(10_000, 3f))
        assertEquals(0.5f, fadeFactor(1_500, 3f))
        assertEquals(0f, fadeFactor(0, 3f))
        assertEquals(1f, fadeFactor(500, 0f))
    }

    @Test
    fun untilMillisUsesTheSiteTimeZone() {
        val zone = java.time.ZoneId.of("America/Toronto")
        val now = java.time.Instant.parse("2026-10-18T12:00:00Z").toEpochMilli() // 08:00 EDT
        val nine = untilMillis("09:00", now, zone)!!
        assertEquals(java.time.Instant.parse("2026-10-18T13:00:00Z").toEpochMilli(), nine)
        assertEquals(null, untilMillis("later", now, zone))
        assertEquals(null, untilMillis(null, now, zone))
    }

    @Test
    fun countdownDecodesNewFieldsAndOldItemsKeepOldBehaviour() {
        val items = AppJson.decodeFromString<Playlist>(
            """{"id":"p","name":"C","items":[
              {"type":"countdown","title":"Old","seconds":300},
              {"type":"countdown","title":"New","mode":"until","until":"09:00","at_zero":"hold","if_passed":"zero",
               "audio":{"url":"https://x/a.mp3","volume":0.5,"loop":false,"fade_seconds":5,"align_end":true}}]}""",
        ).items
        val old = (items[0] as PlaylistItem.Countdown).spec()
        assertEquals("next", old.atZero)
        assertEquals("duration", old.mode)
        assertEquals(300, old.seconds)
        val new = (items[1] as PlaylistItem.Countdown).spec()
        assertEquals("until", new.mode)
        assertEquals("hold", new.atZero)
        assertEquals(true, new.audio?.alignEnd)
        assertEquals(5f, new.audio?.fadeSeconds)
        assertEquals(listOf("https://x/a.mp3"), AppJson.decodeFromString<Playlist>("""{"id":"p","name":"C","items":[{"type":"countdown","title":"N","audio":{"url":"https://x/a.mp3"}}]}""").mediaUrls)
    }

    @Test
    fun organizationStatusDefaultsToActiveAndReadsSuspended() {
        val a = AppJson.decodeFromString<DeviceState>("""{"paired":true,"organization":{"name":"X"}}""")
        assertEquals("active", a.organization?.status)
        val b = AppJson.decodeFromString<DeviceState>("""{"paired":true,"organization":{"name":"X","status":"suspended"}}""")
        assertEquals("suspended", b.organization?.status)
    }
}
