package com.churchtvos.tv

import android.content.Context
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Keeps playlist media on the TV's own storage so Sunday playback
 * never depends on the building's Wi-Fi.
 */
class MediaCache(context: Context) {
    private val dir = File(context.filesDir, "media").apply { mkdirs() }

    fun fileFor(url: String): File {
        val hash = MessageDigest.getInstance("SHA-1")
            .digest(url.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val ext = url.substringBefore('?').substringAfterLast('/').substringAfterLast('.', "")
        return File(dir, if (ext.length in 1..5) "$hash.$ext" else hash)
    }

    suspend fun download(url: String) = withContext(Dispatchers.IO) {
        val target = fileFor(url)
        if (target.exists()) return@withContext

        // Write to a temp file first so a dropped connection never leaves half a video behind.
        val partial = File(target.path + ".part")
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        try {
            if (connection.responseCode !in 200..299) {
                throw IOException("Download failed (HTTP ${connection.responseCode})")
            }
            connection.inputStream.use { input ->
                partial.outputStream().use { output -> input.copyTo(output) }
            }
            if (!partial.renameTo(target)) throw IOException("Couldn't save ${target.name}")
        } finally {
            connection.disconnect()
            partial.delete()
        }
    }

    /** Deletes cached media no longer used by any scheduled playlist. */
    fun prune(keepUrls: Collection<String>) {
        val keep = keepUrls.map { fileFor(it).name }.toSet()
        dir.listFiles()?.filter { it.name !in keep }?.forEach { it.delete() }
    }
}
