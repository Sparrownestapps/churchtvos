package com.churchtvos.tv

import android.content.Context
import android.os.Build
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

data class TvUiState(
    /** Null until we've heard from the server or loaded a saved copy. */
    val device: DeviceState? = null,
    val offline: Boolean = false,
    val downloading: DownloadProgress? = null,
    val failedDownloads: Int = 0,
    val error: String? = null,
)

/** Keeps the TV in step with the dashboard: polls its schedules (Kids and Signage) and pre-downloads the media. */
class TvSync(private val appContext: Context, private val cache: MediaCache) {
    val store = DeviceStore(appContext)
    private val api = SupabaseApi()

    private val _state = MutableStateFlow(TvUiState(device = store.cachedState?.let(::decode)))
    val state = _state.asStateFlow()

    suspend fun run() {
        var registered = false
        while (true) {
            try {
                if (!registered) {
                    api.registerDevice(store.deviceId, store.secret, Build.MODEL, BuildConfig.VERSION_NAME)
                    registered = true
                }
                val raw = api.deviceState(store.deviceId, store.secret)
                val device = decode(raw)
                val wasPaired = store.isPaired
                store.cachedState = raw
                if (device.paired && !wasPaired) AutoLaunch.start(appContext)
                _state.update { it.copy(device = device, offline = false, error = null) }
                downloadMedia(device)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (e.message?.contains("Unknown device") == true) {
                    // Server no longer knows this TV (e.g. deleted from the dashboard): start over.
                    store.reset()
                    registered = false
                    _state.update { TvUiState() }
                } else {
                    _state.update { it.copy(offline = true, error = e.message) }
                }
            }
            // Poll quickly while waiting to be paired so it feels instant.
            delay(if (_state.value.device?.paired == true) 30_000 else 5_000)
        }
    }

    private suspend fun downloadMedia(device: DeviceState) {
        val kidsUrls = device.kids.schedules.sortedBy { it.start }.flatMap { it.playlist.mediaUrls }
        val signagePlaylists = device.signage.slots.map { it.playlist } + listOfNotNull(device.signage.defaultPlaylist)
        val slidesUrls = device.slides.schedules.sortedBy { it.start }.flatMap { it.deck.mediaUrls }
        val urls = (kidsUrls + signagePlaylists.flatMap { it.mediaUrls } + slidesUrls).distinct()
        val missing = urls.filterNot { cache.fileFor(it).exists() }
        var failed = 0
        missing.forEachIndexed { i, url ->
            _state.update { it.copy(downloading = DownloadProgress(i, missing.size)) }
            try {
                cache.download(url)
            } catch (e: IOException) {
                failed++
            }
        }
        _state.update { it.copy(downloading = null, failedDownloads = failed) }
        if (device.paired) cache.prune(urls)
    }

    private fun decode(raw: String): DeviceState = AppJson.decodeFromString(raw)
}
