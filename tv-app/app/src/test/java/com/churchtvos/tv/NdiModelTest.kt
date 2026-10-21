package com.churchtvos.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NdiModelTest {
    private val itemJson = """
        {"id":"p","name":"With NDI","items":[
          {"type":"ndi","title":"Main camera","source":"STUDIO-PC (Camera 1)","address":"192.168.1.50:5961","audio":true,"fit":"fill","fallback":"message","fallback_text":"Back in a moment","max_wait_seconds":20,"seconds":45},
          {"type":"ndi","title":"Bare","source":"PC (Cam)"},
          {"type":"hologram","title":"From the future"}
        ]}
    """.trimIndent()

    @Test
    fun ndiItemDecodesWithAllFieldsAndDefaults() {
        val items = AppJson.decodeFromString<Playlist>(itemJson).items
        val full = items[0] as PlaylistItem.Ndi
        assertEquals("STUDIO-PC (Camera 1)", full.source)
        assertEquals("192.168.1.50:5961", full.address)
        assertTrue(full.audio)
        assertEquals("fill", full.fit)
        assertEquals("message", full.fallback)
        assertEquals("Back in a moment", full.fallbackText)
        assertEquals(20, full.maxWaitSeconds)
        assertEquals(45, full.seconds)
        val bare = items[1] as PlaylistItem.Ndi
        assertNull(bare.address)
        assertFalse(bare.audio)
        assertEquals("fit", bare.fit)
        assertEquals("skip", bare.fallback)
        assertEquals(NDI_DEFAULT_WAIT, bare.maxWaitSeconds)
        assertNull(bare.seconds)
        // Unknown kinds still fall back to Unknown, so an older or newer server never breaks the playlist.
        assertTrue(items[2] is PlaylistItem.Unknown)
    }

    @Test
    fun ndiDeckSlideDecodesAndUnknownKindsStillWork() {
        val deck = AppJson.decodeFromString<Deck>(
            """{"id":"d","name":"Deck","slides":[
                {"kind":"ndi","id":"s1","title":"Cam","source":"A (B)","fit":"fill","fallback":"message","fallback_text":"x","max_wait_seconds":9},
                {"kind":"warp","id":"s2"},
                {"kind":"blank","id":"s3"}]}""",
        )
        val ndi = deck.slides[0] as DeckSlide.Ndi
        assertEquals("A (B)", ndi.source)
        assertEquals(9, ndi.maxWaitSeconds)
        assertEquals("fill", ndi.spec().fit)
        assertTrue(deck.slides[1] is DeckSlide.Unknown)
        assertEquals(2, deck.playableSlides.size)
    }

    @Test
    fun deviceStateReadsTheExperimentalFlagAndDefaultsOff() {
        val on = AppJson.decodeFromString<DeviceState>("""{"paired":true,"experimental":{"ndi":true}}""")
        val off = AppJson.decodeFromString<DeviceState>("""{"paired":true}""")
        assertTrue(on.experimental.ndi)
        assertFalse(off.experimental.ndi)
    }

    @Test
    fun mediaUrlsIgnoreNdi() {
        assertTrue(AppJson.decodeFromString<Playlist>(itemJson).mediaUrls.isEmpty())
    }

    private val spec = NdiSpec(source = "PC (Cam)", maxWaitSeconds = 10)

    @Test
    fun waitsThenSkipsWhenTheSourceNeverAppears() {
        assertEquals(NdiAction.WAIT, ndiAction(spec, streaming = false, unavailableMs = 0))
        assertEquals(NdiAction.WAIT, ndiAction(spec, streaming = false, unavailableMs = 9_999))
        assertEquals(NdiAction.SKIP, ndiAction(spec, streaming = false, unavailableMs = 10_000))
    }

    @Test
    fun showsTheMessageAfterTheWaitAndRecoversWhenFramesReturn() {
        val withMessage = spec.copy(fallback = "message", fallbackText = "Back soon")
        assertEquals(NdiAction.SHOW_MESSAGE, ndiAction(withMessage, false, 12_000))
        assertEquals(NdiAction.LIVE, ndiAction(withMessage, true, 12_000))
        assertEquals("Back soon", withMessage.messageText)
        assertEquals("Waiting for the live feed…", withMessage.copy(fallbackText = "  ").messageText)
    }

    @Test
    fun badWaitValuesFallBackToTheDefault() {
        assertEquals(NDI_DEFAULT_WAIT * 1000L, spec.copy(maxWaitSeconds = 0).maxWaitMs)
        assertEquals(NDI_DEFAULT_WAIT * 1000L, spec.copy(maxWaitSeconds = 9999).maxWaitMs)
        assertEquals(3_000L, spec.copy(maxWaitSeconds = 3).maxWaitMs)
        assertEquals(120_000L, spec.copy(maxWaitSeconds = 120).maxWaitMs)
    }

    @Test
    fun addressIsOnlyUsedWhenItLooksUsable() {
        assertNull(spec.directAddress)
        assertNull(spec.copy(address = "   ").directAddress)
        assertNull(spec.copy(address = "bad address").directAddress)
        assertEquals("10.0.0.5:5961", spec.copy(address = " 10.0.0.5:5961 ").directAddress)
    }

    @Test
    fun flagOffNeverPlaysAndStoreBuildKeepsOnlyMessageItems() {
        val skip = spec.copy(fallback = "skip")
        val message = spec.copy(fallback = "message")
        // flag off: nothing plays, in any build
        assertFalse(skip.isPlayable(flagOn = false, buildHasNdi = true))
        assertFalse(message.isPlayable(flagOn = false, buildHasNdi = true))
        // ndi build, flag on: both play
        assertTrue(skip.isPlayable(true, true))
        assertTrue(message.isPlayable(true, true))
        // store build, flag on: "skip" is dropped at once, "message" stays so the message is shown
        assertFalse(skip.isPlayable(true, false))
        assertTrue(message.isPlayable(true, false))
    }

    @Test
    fun slideListsDropBlockedNdiSlidesOnly() {
        val slides = listOf(
            Slide.Sign("a", "", "#000000", 5, "center", false),
            Slide.Ndi(spec.copy(fallback = "skip")),
            Slide.Ndi(spec.copy(fallback = "message")),
        )
        assertEquals(1, slides.withoutBlockedNdi(flagOn = false, buildHasNdi = true).size)
        assertEquals(3, slides.withoutBlockedNdi(flagOn = true, buildHasNdi = true).size)
        assertEquals(2, slides.withoutBlockedNdi(flagOn = true, buildHasNdi = false).size)
    }

    @Test
    fun playlistsAndDecksBuildNdiSlidesAndSkipUnknown() {
        val playlist = AppJson.decodeFromString<Playlist>(itemJson)
        val slides = playlist.items.flatMap { item ->
            when (item) {
                is PlaylistItem.Ndi -> listOf(Slide.Ndi(item.spec()))
                else -> emptyList()
            }
        }
        assertEquals(2, slides.size)
        assertEquals("NDI: Main camera", slides[0].label())
        val deck = AppJson.decodeFromString<Deck>("""{"id":"d","name":"D","slides":[{"kind":"ndi","source":"X"},{"kind":"blank"}]}""")
        assertEquals(1, deck.playableSlides(ndiFlagOn = false, buildHasNdi = true).size)
        assertEquals(2, deck.playableSlides(ndiFlagOn = true, buildHasNdi = true).size)
        assertEquals(1, deck.playableSlides(ndiFlagOn = true, buildHasNdi = false).size) // default fallback is "skip"
    }

    @Test
    fun statusNoteReadsWell() {
        val s = spec.copy(title = "Main camera")
        assertEquals("NDI: Main camera, live", ndiStatusNote(s, NdiAction.LIVE))
        assertEquals("NDI: Main camera, connecting", ndiStatusNote(s, NdiAction.WAIT))
        assertEquals("NDI: PC (Cam), unavailable", ndiStatusNote(spec, NdiAction.SHOW_MESSAGE))
    }

    @Test
    fun frameSizeFitsOrFillsTheBox() {
        // 16:9 picture in a 1920x1080 box: both modes fill it exactly
        assertEquals(1920 to 1080, ndiFrameSize(1920, 1080, 16f / 9f, fill = false))
        assertEquals(1920 to 1080, ndiFrameSize(1920, 1080, 16f / 9f, fill = true))
        // 4:3 picture: fit leaves bars at the sides, fill crops top and bottom
        assertEquals(1440 to 1080, ndiFrameSize(1920, 1080, 4f / 3f, fill = false))
        assertEquals(1920 to 1440, ndiFrameSize(1920, 1080, 4f / 3f, fill = true))
        // portrait (rotated) box with a landscape picture: fit letterboxes
        assertEquals(1080 to 608, ndiFrameSize(1080, 1920, 16f / 9f, fill = false))
        assertEquals(3413 to 1920, ndiFrameSize(1080, 1920, 16f / 9f, fill = true))
        // unknown size fills the box
        assertEquals(800 to 600, ndiFrameSize(800, 600, 0f, fill = false))
    }
}
