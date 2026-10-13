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
    data class Lyric(val song: String, val text: String, val number: Int, val count: Int) : Slide
    data class YouTube(val videoId: String?, val channelId: String?, val start: Int?) : Slide
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
    }
}

data class DownloadProgress(val done: Int, val total: Int)
