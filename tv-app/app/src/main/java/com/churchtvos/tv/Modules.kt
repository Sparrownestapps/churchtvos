package com.churchtvos.tv

import java.time.DateTimeException
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

object Module {
    const val KIDS = "kids"
    const val SIGNAGE = "signage"
    const val OFF = "off"
}

private fun zonedNow(timezone: String, nowMillis: Long): ZonedDateTime {
    val zone = try { ZoneId.of(timezone) } catch (e: DateTimeException) { ZoneId.systemDefault() }
    return ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(nowMillis), zone)
}

/** Same rule the server uses: day in [days] (0 = Sunday) and start <= time < end. */
private fun matches(days: List<Int>, start: String, end: String, at: ZonedDateTime): Boolean {
    val day = at.dayOfWeek.value % 7
    val time = at.toLocalTime()
    return day in days && !time.isBefore(LocalTime.parse(start)) && time.isBefore(LocalTime.parse(end))
}

/**
 * The module this TV should run right now. Evaluated on the TV so mixed TVs keep switching while offline.
 * Highest priority wins; among equals the later rule (the server sends them oldest first) wins.
 */
fun DeviceState.moduleNow(nowMillis: Long): String {
    val at = zonedNow(timezone, nowMillis)
    val rule = moduleRules
        .filter { matches(it.days, it.start, it.end, at) }
        .withIndex()
        .maxWithOrNull(compareBy({ it.value.priority }, { it.index }))
        ?.value
    return rule?.module ?: defaultModule
}

/** The Signage playlist for right now, or null for a black screen. */
fun DeviceState.signagePlaylistNow(nowMillis: Long): Playlist? {
    val at = zonedNow(timezone, nowMillis)
    val slot = signage.slots
        .filter { matches(it.days, it.start, it.end, at) }
        .withIndex()
        .maxWithOrNull(compareBy({ it.value.priority }, { it.index }))
        ?.value
    return slot?.playlist ?: signage.defaultPlaylist
}
