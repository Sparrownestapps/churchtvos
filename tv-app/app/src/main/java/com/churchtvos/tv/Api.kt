package com.churchtvos.tv

import android.content.Context
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

val AppJson = Json { ignoreUnknownKeys = true }

/** What the server says this TV should show (see device_state in the foundation migration). */
@Serializable
data class DeviceState(
    val paired: Boolean,
    @SerialName("pairing_code") val pairingCode: String? = null,
    val organization: OrganizationInfo? = null,
    val site: String? = null,
    val location: String? = null,
    val timezone: String = "America/Toronto",
    val screen: ScreenInfo = ScreenInfo(),
    @SerialName("enabled_modules") val enabledModules: List<String> = emptyList(),
    @SerialName("default_module") val defaultModule: String = "kids",
    @SerialName("module_rules") val moduleRules: List<ModuleRule> = emptyList(),
    val kids: KidsState = KidsState(),
    val signage: SignageState = SignageState(),
)

@Serializable
data class OrganizationInfo(val name: String, val branding: BrandingInfo = BrandingInfo())

/** One look: the church default (top level) or an override for a module. Unset fields inherit. */
@Serializable
data class SplashInfo(val enabled: Boolean? = null, val seconds: Int? = null)

@Serializable
data class LookInfo(
    @SerialName("logo_url") val logoUrl: String? = null,
    @SerialName("logo_dark_url") val logoDarkUrl: String? = null,
    @SerialName("primary_color") val primaryColor: String? = null,
    @SerialName("accent_color") val accentColor: String? = null,
    val splash: SplashInfo? = null,
)

@Serializable
data class ModuleLooks(val kids: LookInfo? = null, val signage: LookInfo? = null)

@Serializable
data class BrandingInfo(
    @SerialName("logo_url") val logoUrl: String? = null,
    @SerialName("logo_dark_url") val logoDarkUrl: String? = null,
    @SerialName("primary_color") val primaryColor: String? = null,
    @SerialName("accent_color") val accentColor: String? = null,
    val splash: SplashInfo? = null,
    val modules: ModuleLooks? = null,
)

@Serializable
data class ScreenInfo(val name: String? = null, val orientation: String = "landscape")

/** Which module runs when. Days are 0 = Sunday; times are local to the site. */
@Serializable
data class ModuleRule(
    val module: String,
    val days: List<Int> = emptyList(),
    val start: String,
    val end: String,
    val priority: Int = 0,
)

@Serializable
data class KidsState(val schedules: List<Schedule> = emptyList())

@Serializable
data class SignageSlot(
    val id: String,
    val days: List<Int> = emptyList(),
    val start: String,
    val end: String,
    val priority: Int = 0,
    val playlist: Playlist,
)

@Serializable
data class SignageState(
    val slots: List<SignageSlot> = emptyList(),
    @SerialName("default_playlist") val defaultPlaylist: Playlist? = null,
)

@Serializable
data class Schedule(
    val id: String,
    @SerialName("starts_at") val startsAt: String,
    @SerialName("ends_at") val endsAt: String? = null,
    val playlist: Playlist,
) {
    val start: Instant get() = OffsetDateTime.parse(startsAt).toInstant()
    val end: Instant? get() = endsAt?.let { OffsetDateTime.parse(it).toInstant() }
}

/** The schedule showing now (latest one that has started and not ended). */
fun DeviceState.current(now: Instant): Schedule? = kids.schedules
    .filter { it.start <= now && (it.end == null || it.end!! > now) }
    .maxByOrNull { it.start }

fun DeviceState.next(now: Instant): Schedule? = kids.schedules
    .filter { it.start > now }
    .minByOrNull { it.start }

class SupabaseApi {
    suspend fun registerDevice(id: String, secret: String, model: String, appVersion: String) {
        rpc("register_device", buildJsonObject {
            put("p_device_id", id)
            put("p_secret", secret)
            put("p_model", model)
            put("p_app_version", appVersion)
        })
    }

    /** Returns the raw JSON so it can be saved for offline use. */
    suspend fun deviceState(id: String, secret: String): String =
        rpc("device_state", buildJsonObject {
            put("p_device_id", id)
            put("p_secret", secret)
        })

    private suspend fun rpc(name: String, body: JsonObject): String = withContext(Dispatchers.IO) {
        val connection = URL("$SUPABASE_URL/rest/v1/rpc/$name").openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.setRequestProperty("apikey", SUPABASE_KEY)
        connection.setRequestProperty("Content-Type", "application/json")
        try {
            connection.outputStream.use { it.write(body.toString().toByteArray()) }
            val code = connection.responseCode
            val stream = if (code in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (code !in 200..299) throw IOException("Server error $code: $text")
            text
        } finally {
            connection.disconnect()
        }
    }
}

/** This TV's identity and last known state, kept across restarts. */
class DeviceStore(context: Context) {
    private val prefs = context.getSharedPreferences("church_tv_os", Context.MODE_PRIVATE)

    val deviceId: String get() = getOrCreate("device_id") { UUID.randomUUID().toString() }

    val secret: String
        get() = getOrCreate("secret") {
            ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        }

    val isPaired: Boolean
        get() = cachedState?.let { runCatching { AppJson.decodeFromString<DeviceState>(it).paired }.getOrNull() } == true

    var cachedState: String?
        get() = prefs.getString("state", null)
        set(value) = prefs.edit().putString("state", value).apply()

    /** Whether the TV opens the app by itself when switched on. Opt-in (the Appstore requires it): asked once after pairing, changeable in Settings. */
    var autoLaunch: Boolean
        get() = prefs.getBoolean("auto_launch", false)
        set(value) = prefs.edit().putBoolean("auto_launch", value).apply()

    /** True once the "open automatically?" question has been answered, so it is only asked once. */
    var autoLaunchAsked: Boolean
        get() = prefs.getBoolean("auto_launch_asked", false)
        set(value) = prefs.edit().putBoolean("auto_launch_asked", value).apply()

    /** Forget everything so the TV registers again with a fresh pairing code. */
    fun reset() = prefs.edit().clear().commit()

    private fun getOrCreate(key: String, create: () -> String): String =
        prefs.getString(key, null) ?: create().also { prefs.edit().putString(key, it).commit() }
}
