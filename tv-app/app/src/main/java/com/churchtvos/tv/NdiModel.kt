package com.churchtvos.tv

import androidx.compose.runtime.compositionLocalOf
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// EXPERIMENTAL NDI source (Kids items, Signage items and Slides slides). Contract: NDI-CONTRACT.md at the repository root.
// This file has NO NDI library dependency: it is in every build. Only the "ndi" product flavor can actually receive NDI.

/** Whether this build contains the NDI libraries (the "ndi" flavor). The store flavor has none and never will. */
object NdiBuild {
    val AVAILABLE: Boolean get() = BuildConfig.NDI_AVAILABLE
}

/** The church's experimental switches, from the server (organizations.ndi_enabled). */
@Serializable
data class ExperimentalInfo(val ndi: Boolean = false)

/** True when the server has switched NDI on for this church. Provided in App() from device_state. */
val LocalNdiAllowed = compositionLocalOf { false }

/** What to show or do for one NDI source. Defaults match the contract. */
@Serializable
data class NdiSpec(
    val title: String = "",
    val source: String = "",
    /** Optional "host" or "host:port" for networks where discovery does not work. */
    val address: String? = null,
    val audio: Boolean = false,
    /** "fit" (whole picture) or "fill" (crop to fill). */
    val fit: String = "fit",
    /** "skip" or "message". */
    val fallback: String = "skip",
    @SerialName("fallback_text") val fallbackText: String = "",
    @SerialName("max_wait_seconds") val maxWaitSeconds: Int = NDI_DEFAULT_WAIT,
    /** null = until Next (Kids) / until the loop moves on (Signage: the loop sets 30). */
    val seconds: Int? = null,
)

const val NDI_DEFAULT_WAIT = 15
const val NDI_MIN_WAIT = 3
const val NDI_MAX_WAIT = 120

/** Out-of-range or missing waits fall back to safe values (the server validates, but never trust cached data). */
val NdiSpec.maxWaitMs: Long get() = (if (maxWaitSeconds in NDI_MIN_WAIT..NDI_MAX_WAIT) maxWaitSeconds else NDI_DEFAULT_WAIT) * 1000L

/** Blank or unusable addresses mean "find it by name". */
val NdiSpec.directAddress: String?
    get() = address?.trim()?.takeIf { it.isNotEmpty() && ' ' !in it }

val NdiSpec.fills: Boolean get() = fit == "fill"

val NdiSpec.messageText: String
    get() = fallbackText.trim().ifEmpty { "Waiting for the live feed…" }

/** What the slide does with the clock at this moment. */
enum class NdiAction { WAIT, SKIP, SHOW_MESSAGE, LIVE }

/**
 * The fallback rule, as a pure function so it can be tested.
 * [streaming] = frames are arriving. [unavailableMs] = how long the source has been missing: since the slide started
 * (first connect) or since the last frame (after a drop). The picture comes back by itself whenever frames resume.
 */
fun ndiAction(spec: NdiSpec, streaming: Boolean, unavailableMs: Long): NdiAction = when {
    streaming -> NdiAction.LIVE
    unavailableMs < spec.maxWaitMs -> NdiAction.WAIT
    spec.fallback == "message" -> NdiAction.SHOW_MESSAGE
    else -> NdiAction.SKIP
}

/**
 * Whether a slide with this spec belongs in the playlist at all.
 * Off for the church = never plays (even from a stale saved copy). A build without NDI cannot show the picture, so it
 * keeps only items that asked for a message (the message is the whole slide) and drops "skip" items at once.
 */
fun NdiSpec.isPlayable(flagOn: Boolean, buildHasNdi: Boolean): Boolean = flagOn && (buildHasNdi || fallback == "message")

/** One-line status for remotes ("NDI: Main camera, live"). */
fun ndiStatusNote(spec: NdiSpec, action: NdiAction): String {
    val name = spec.title.ifBlank { spec.source }.ifBlank { "source" }
    return when (action) {
        NdiAction.LIVE -> "NDI: $name, live"
        NdiAction.WAIT -> "NDI: $name, connecting"
        NdiAction.SHOW_MESSAGE -> "NDI: $name, unavailable"
        NdiAction.SKIP -> "NDI: $name, unavailable (skipping)"
    }
}
