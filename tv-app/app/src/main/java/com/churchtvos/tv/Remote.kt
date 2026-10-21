package com.churchtvos.tv

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

/** What a phone, the website or the Mac app can ask this TV to do (see the database function send_screen_command). */
sealed interface RemoteCommand {
    data object Next : RemoteCommand
    data object Previous : RemoteCommand
    data class Jump(val index: Int) : RemoteCommand
    /** on == null toggles. */
    data class Blank(val on: Boolean?) : RemoteCommand
    data object Stop : RemoteCommand
    /** The server has recorded a play-now override; fetch it right away. */
    data object Start : RemoteCommand
    data class Message(val text: String, val seconds: Int, val background: String) : RemoteCommand
    data object ClearMessage : RemoteCommand
}

@Serializable
data class RawCommand(val id: Long = 0, val command: String, val payload: JsonObject = JsonObject(emptyMap()))

private fun JsonObject.str(k: String) = (get(k) as? JsonPrimitive)?.contentOrNull
private fun JsonObject.int(k: String) = (get(k) as? JsonPrimitive)?.intOrNull
private fun JsonObject.bool(k: String) = (get(k) as? JsonPrimitive)?.booleanOrNull

/** Unknown or malformed commands are ignored (null), so a newer server never breaks an older TV. */
fun RawCommand.toRemoteCommand(): RemoteCommand? = when (command) {
    "next" -> RemoteCommand.Next
    "previous" -> RemoteCommand.Previous
    "jump" -> payload.int("index")?.let { RemoteCommand.Jump(it) }
    "blank" -> RemoteCommand.Blank(payload.bool("on"))
    "stop" -> RemoteCommand.Stop
    "start" -> RemoteCommand.Start
    "message" -> payload.str("text")?.takeIf { it.isNotBlank() }?.let {
        RemoteCommand.Message(it, (payload.int("seconds") ?: 30).coerceIn(5, 300), payload.str("background") ?: "#1B2A4A")
    }
    "clear_message" -> RemoteCommand.ClearMessage
    else -> null
}

/** A message sign currently covering the screen. */
data class ActiveMessage(val text: String, val background: String, val untilMillis: Long)

/** What this TV is showing, reported to the server so remotes can display it. */
data class PlaybackStatus(
    val module: String = "",
    val state: String = "idle", // idle, playing, blank, message
    val title: String = "",
    val label: String = "",
    val index: Int = 0,
    val count: Int = 0,
    val outline: List<String> = emptyList(),
    val refKind: String? = null,
    val refId: String? = null,
)

/** The meeting point between the network loop (TvSync) and whatever is on screen. */
object Remote {
    private val _commands = MutableSharedFlow<RemoteCommand>(extraBufferCapacity = 32)
    val commands: SharedFlow<RemoteCommand> = _commands.asSharedFlow()
    fun emit(command: RemoteCommand) { _commands.tryEmit(command) }

    val status = MutableStateFlow(PlaybackStatus())
    val message = MutableStateFlow<ActiveMessage?>(null)

    /** A short live note from the slide on screen (for example "NDI: Main camera, live"), added to the status label. */
    val ndiNote = MutableStateFlow<String?>(null)

    fun idle() { status.value = PlaybackStatus() }
}
