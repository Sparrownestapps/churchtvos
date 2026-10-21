package com.churchtvos.tv

import java.io.File
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Playlist(val id: String, val name: String, val items: List<PlaylistItem>)

@Serializable
sealed interface PlaylistItem {
    val title: String

    @Serializable
    @SerialName("video")
    data class Video(override val title: String, val url: String) : PlaylistItem

    /** [seconds] = null means the image stays up until someone presses next. */
    @Serializable
    @SerialName("image")
    data class Image(override val title: String, val url: String, val seconds: Int? = null) : PlaylistItem

    @Serializable
    @SerialName("countdown")
    data class Countdown(
        override val title: String,
        val seconds: Int = 60,
        val mode: String = "duration",
        val until: String? = null,
        val audio: CountdownAudio? = null,
        @SerialName("at_zero") val atZero: String = "next",
        @SerialName("if_passed") val ifPassed: String = "zero",
    ) : PlaylistItem

    @Serializable
    @SerialName("lyrics")
    data class Lyrics(
        override val title: String,
        val slides: List<String>,
        /** Section label for each slide (Verse 1, Chorus...); optional. */
        val labels: List<String> = emptyList(),
        /** Show the song title as its own first slide that waits for the leader to press Next. */
        @SerialName("show_title") val showTitle: Boolean = false,
        val authors: String? = null,
        val ccli: String? = null,
        val copyright: String? = null,
    ) : PlaylistItem

    /** A simple text sign: coloured background, title and optional subtext (Signage). */
    @Serializable
    @SerialName("sign")
    data class Sign(
        override val title: String,
        val subtext: String = "",
        val background: String = "#1B2A4A",
        val seconds: Int = 10,
        val align: String = "center",
        val logo: Boolean = false,
    ) : PlaylistItem

    /** A live HLS stream (BoxCast static link, OBS/gateway output...). [seconds] null = until next / until the loop moves on. */
    @Serializable
    @SerialName("stream")
    data class Stream(
        override val title: String,
        val url: String,
        val seconds: Int? = null,
        val audio: Boolean = false,
        val fallback: String = "skip", // "skip" or "hold"
    ) : PlaylistItem

    /** Any item type this app version does not know: skipped instead of rejecting the whole playlist. */
    @Serializable
    @SerialName("unknown")
    data class Unknown(override val title: String = "") : PlaylistItem

    /** Streams from YouTube at playback time. No [videoId] means "whatever [channelId] is live-streaming now". */
    @Serializable
    @SerialName("youtube")
    data class YouTube(
        override val title: String,
        @SerialName("video_id") val videoId: String? = null,
        @SerialName("channel_id") val channelId: String? = null,
        val start: Int? = null,
    ) : PlaylistItem
}

/** Remote media a playlist needs on the device before it can play. */
val Playlist.mediaUrls: List<String>
    get() = items.mapNotNull {
        when (it) {
            is PlaylistItem.Video -> it.url
            is PlaylistItem.Image -> it.url
            is PlaylistItem.Countdown -> it.audio?.url
            else -> null
        }
    }

/** One screen of content. Lyrics expand to one slide per section. */
sealed interface Slide {
    data class Video(val file: File) : Slide
    data class Image(val file: File, val seconds: Int?) : Slide
    data class Countdown(val title: String, val spec: CountdownSpec, val audioFile: File?) : Slide
    /** A picture shipped inside the app (demo mode). */
    data class Bundled(@androidx.annotation.DrawableRes val res: Int, val seconds: Int) : Slide
    data class Lyric(val song: String, val text: String, val number: Int, val count: Int) : Slide
    /** The song name on its own, before the words. Holds until Next is pressed. */
    data class SongTitle(val title: String, val authors: String?, val ccli: String?, val copyright: String?) : Slide
    data class YouTube(val videoId: String?, val channelId: String?, val start: Int?) : Slide
    data class Sign(val title: String, val subtext: String, val background: String, val seconds: Int, val align: String, val logo: Boolean) : Slide
    data class Stream(val url: String, val audio: Boolean, val seconds: Int?, val fallback: String) : Slide
}

fun PlaylistItem.Countdown.spec() = CountdownSpec(mode, seconds, until, audio, atZero, ifPassed)

fun Playlist.toSlides(cache: MediaCache): List<Slide> = items.flatMap { item ->
    when (item) {
        is PlaylistItem.Video -> listOf(Slide.Video(cache.fileFor(item.url)))
        is PlaylistItem.Image -> listOf(Slide.Image(cache.fileFor(item.url), item.seconds))
        is PlaylistItem.Countdown -> listOf(Slide.Countdown(item.title, item.spec(), item.audio?.let { a -> cache.fileFor(a.url).takeIf { it.exists() } }))
        is PlaylistItem.Lyrics -> item.toLyricSlides()
        is PlaylistItem.YouTube -> listOf(Slide.YouTube(item.videoId, item.channelId, item.start))
        is PlaylistItem.Sign -> listOf(Slide.Sign(item.title, item.subtext, item.background, item.seconds, item.align, item.logo))
        is PlaylistItem.Stream -> listOf(Slide.Stream(item.url, item.audio, item.seconds, item.fallback))
        is PlaylistItem.Unknown -> emptyList()
    }
}

data class DownloadProgress(val done: Int, val total: Int)

/** A song's slides: an optional title slide first, then one slide per lyric section. */
fun PlaylistItem.Lyrics.toLyricSlides(): List<Slide> {
    val words = slides.mapIndexed { i, text -> Slide.Lyric(title, text, i + 1, slides.size) }
    return if (showTitle) listOf<Slide>(Slide.SongTitle(title, authors, ccli, copyright)) + words else words
}

/** Short description of a slide for remotes ("Jump to slide" lists and the now-showing line). */
fun Slide.label(): String = when (this) {
    is Slide.Video -> "Video"
    is Slide.Image -> "Picture"
    is Slide.Bundled -> "Slide"
    is Slide.Countdown -> title.ifBlank { "Countdown" }
    is Slide.Lyric -> "$song · Part $number of $count"
    is Slide.SongTitle -> "$title (title)"
    is Slide.YouTube -> "YouTube"
    is Slide.Sign -> title.ifBlank { "Sign" }
    is Slide.Stream -> "Live stream"
}

/** What a player tells remotes about itself. Null means "do not report" (demo mode). */
data class PlayerReport(val module: String, val title: String, val refKind: String? = null, val refId: String? = null)
