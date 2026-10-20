package com.churchtvos.tv

import java.time.Instant
import java.time.OffsetDateTime
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonClassDiscriminator

// Slides module data as the server sends it (see dashboard/src/slidesTypes.ts and the database function deck_expand).

@Serializable
data class SlidesState(val schedules: List<DeckSchedule> = emptyList())

@Serializable
data class DeckSchedule(
    val id: String,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String? = null,
    val deck: Deck,
) {
    val start: Instant get() = OffsetDateTime.parse(startsAt).toInstant()
    val end: Instant? get() = endsAt?.let { OffsetDateTime.parse(it).toInstant() }
}

@Serializable
data class Deck(
    val id: String,
    val name: String,
    val loop: Boolean = false,
    val theme: ThemeConfig = ThemeConfig(),
    val background: SlideBackground? = null,
    val slides: List<DeckSlide> = emptyList(),
)

@Serializable
data class LogoPlacement(val show: Boolean = false, val position: String = "bottom_left")

@Serializable
data class ThemeConfig(
    val font: String? = null, // "lato" (default) or "julius" for titles
    @SerialName("title_scale") val titleScale: Float = 1f,
    @SerialName("body_scale") val bodyScale: Float = 1f,
    @SerialName("text_color") val textColor: String? = null,
    val align: String? = null, // "center" (default) or "left"
    val position: String? = null, // "center" (default), "lower", "top"
    val shadow: Boolean = true,
    val outline: Boolean = false,
    val margin: Float = 8f,
    val background: SlideBackground? = null,
    @SerialName("show_labels") val showLabels: Boolean = true,
    val logo: LogoPlacement = LogoPlacement(),
)

/** A background layer. Resolution order: slide, then deck, then theme, then the church's primary colour. */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
sealed interface SlideBackground {
    val dim: Float get() = 0f

    @Serializable @SerialName("color")
    data class Solid(val color: String = "#1B2A4A", override val dim: Float = 0f) : SlideBackground

    @Serializable @SerialName("gradient")
    data class Gradient(val color: String = "#1B2A4A", val color2: String = "#000000", val angle: Float = 180f, override val dim: Float = 0f) : SlideBackground

    @Serializable @SerialName("image")
    data class Image(val url: String, val fit: String = "cover", val color: String? = null, override val dim: Float = 0f) : SlideBackground

    @Serializable @SerialName("video")
    data class Video(val url: String, val fit: String = "cover", val color: String? = null, override val dim: Float = 0f) : SlideBackground

    /** A background type this app version does not know: ignored. */
    @Serializable @SerialName("unknown")
    data object Unknown : SlideBackground
}

@OptIn(ExperimentalSerializationApi::class)
@Serializable
@JsonClassDiscriminator("kind")
sealed interface DeckSlide {
    val background: SlideBackground? get() = null

    @Serializable @SerialName("text")
    data class Text(
        val id: String = "",
        val title: String? = null,
        val body: String? = null,
        val layout: String = "title_body", // title_body, title, body, lower_third
        val align: String? = null,
        @SerialName("text_color") val textColor: String? = null,
        val seconds: Int? = null,
        override val background: SlideBackground? = null,
    ) : DeckSlide

    @Serializable @SerialName("media")
    data class Media(
        val id: String = "",
        val url: String,
        @SerialName("media_kind") val mediaKind: String = "image",
        val fit: String = "contain",
        val seconds: Int? = null,
        val audio: Boolean = true,
        override val background: SlideBackground? = null,
    ) : DeckSlide

    @Serializable @SerialName("countdown")
    data class Countdown(
        val id: String = "",
        val title: String? = null,
        val seconds: Int = 60,
        val mode: String = "duration",
        val until: String? = null,
        val audio: CountdownAudio? = null,
        @SerialName("at_zero") val atZero: String = "next",
        @SerialName("if_passed") val ifPassed: String = "zero",
        override val background: SlideBackground? = null,
    ) : DeckSlide

    @Serializable @SerialName("stream")
    data class Stream(
        val id: String = "",
        val title: String? = null,
        val url: String,
        val audio: Boolean = false,
        val fallback: String = "skip",
        val seconds: Int? = null,
        override val background: SlideBackground? = null,
    ) : DeckSlide

    @Serializable @SerialName("blank")
    data class Blank(val id: String = "", val color: String? = null) : DeckSlide

    /** The server expands a song slide into an optional title slide followed by one lyric slide per section. */
    @Serializable @SerialName("song_title")
    data class SongTitle(
        val title: String,
        val authors: String? = null,
        val ccli: String? = null,
        val copyright: String? = null,
        override val background: SlideBackground? = null,
    ) : DeckSlide

    @Serializable @SerialName("lyric")
    data class Lyric(
        val song: String = "",
        val text: String,
        val label: String? = null,
        val number: Int = 1,
        val count: Int = 1,
        override val background: SlideBackground? = null,
    ) : DeckSlide

    /** A slide kind newer than this app: skipped. */
    @Serializable @SerialName("unknown")
    data class Unknown(val id: String = "") : DeckSlide
}

val Deck.playableSlides: List<DeckSlide> get() = slides.filter { it !is DeckSlide.Unknown }

/** Remote files this deck needs on the TV before it can play (backgrounds, images, videos). */
val Deck.mediaUrls: List<String>
    get() {
        val urls = mutableListOf<String>()
        fun add(bg: SlideBackground?) {
            when (bg) {
                is SlideBackground.Image -> urls += bg.url
                is SlideBackground.Video -> urls += bg.url
                else -> Unit
            }
        }
        add(background)
        add(theme.background)
        slides.forEach { s ->
            add(s.background)
            if (s is DeckSlide.Media) urls += s.url
            if (s is DeckSlide.Countdown) s.audio?.let { urls += it.url }
        }
        return urls.distinct()
    }

fun DeviceState.currentDeck(now: Instant): DeckSchedule? = slides.schedules
    .filter { it.start <= now && (it.end == null || it.end!! > now) }
    .maxByOrNull { it.start }

fun DeviceState.nextDeck(now: Instant): DeckSchedule? = slides.schedules
    .filter { it.start > now }
    .minByOrNull { it.start }
