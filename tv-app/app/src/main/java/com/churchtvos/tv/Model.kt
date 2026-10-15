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
    data class Countdown(override val title: String, val seconds: Int) : PlaylistItem

    @Serializable
    @SerialName("lyrics")
    data class Lyrics(override val title: String, val slides: List<String>) : PlaylistItem

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
            else -> null
        }
    }

/** One screen of content. Lyrics expand to one slide per section. */
sealed interface Slide {
    data class Video(val file: File) : Slide
    data class Image(val file: File, val seconds: Int?) : Slide
    data class Countdown(val title: String, val seconds: Int) : Slide
    /** A picture shipped inside the app (demo mode). */
    data class Bundled(@androidx.annotation.DrawableRes val res: Int, val seconds: Int) : Slide
    data class Lyric(val song: String, val text: String, val number: Int, val count: Int) : Slide
    data class YouTube(val videoId: String?, val channelId: String?, val start: Int?) : Slide
    data class Sign(val title: String, val subtext: String, val background: String, val seconds: Int, val align: String, val logo: Boolean) : Slide
    data class Stream(val url: String, val audio: Boolean, val seconds: Int?, val fallback: String) : Slide
}

fun Playlist.toSlides(cache: MediaCache): List<Slide> = items.flatMap { item ->
    when (item) {
        is PlaylistItem.Video -> listOf(Slide.Video(cache.fileFor(item.url)))
        is PlaylistItem.Image -> listOf(Slide.Image(cache.fileFor(item.url), item.seconds))
        is PlaylistItem.Countdown -> listOf(Slide.Countdown(item.title, item.seconds))
        is PlaylistItem.Lyrics -> item.slides.mapIndexed { i, text ->
            Slide.Lyric(item.title, text, i + 1, item.slides.size)
        }
        is PlaylistItem.YouTube -> listOf(Slide.YouTube(item.videoId, item.channelId, item.start))
        is PlaylistItem.Sign -> listOf(Slide.Sign(item.title, item.subtext, item.background, item.seconds, item.align, item.logo))
        is PlaylistItem.Stream -> listOf(Slide.Stream(item.url, item.audio, item.seconds, item.fallback))
        is PlaylistItem.Unknown -> emptyList()
    }
}

data class DownloadProgress(val done: Int, val total: Int)
