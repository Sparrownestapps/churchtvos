import type { DeckSchedule, DeviceState, Playlist, Schedule } from './types'
import { isoMillis, parseClock, zonedParts } from './time'

export const Module = { KIDS: 'kids', SIGNAGE: 'signage', SLIDES: 'slides', OFF: 'off' } as const

/** Same rule the server uses: day in [days] (0 = Sunday) and start <= time < end. */
function matches(days: number[], start: string, end: string, nowMs: number, zone: string): boolean {
  const p = zonedParts(nowMs, zone)
  const time = p.hour * 60 + p.minute + p.second / 60
  const s = parseClock(start)
  const e = parseClock(end)
  return s !== null && e !== null && days.includes(p.weekday) && time >= s && time < e
}

/** Highest priority wins; among equals the later one (the server sends them oldest first) wins. */
function best<T extends { priority: number }>(items: T[]): T | undefined {
  let pick: T | undefined
  for (const it of items) if (!pick || it.priority >= pick.priority) pick = it
  return pick
}

/** The module this TV should run right now. Evaluated on the TV so mixed TVs keep switching while offline. */
export function moduleNow(d: DeviceState, nowMs: number): string {
  const rule = best(d.module_rules.filter((r) => matches(r.days, r.start, r.end, nowMs, d.timezone)))
  return rule?.module ?? d.default_module
}

/** The Signage playlist for right now, or null for a black screen. */
export function signagePlaylistNow(d: DeviceState, nowMs: number): Playlist | null {
  const slot = best(d.signage.slots.filter((s) => matches(s.days, s.start, s.end, nowMs, d.timezone)))
  return slot?.playlist ?? d.signage.default_playlist ?? null
}

type Timed = { starts_at: string; ends_at?: string | null }

/** The latest item that has started and not ended. */
function currentOf<T extends Timed>(items: T[], nowMs: number): T | null {
  let pick: T | null = null
  for (const it of items) {
    const start = isoMillis(it.starts_at)
    const end = it.ends_at ? isoMillis(it.ends_at) : null
    if (start <= nowMs && (end === null || end > nowMs) && (!pick || start > isoMillis(pick.starts_at))) pick = it
  }
  return pick
}

function nextOf<T extends Timed>(items: T[], nowMs: number): T | null {
  let pick: T | null = null
  for (const it of items) {
    const start = isoMillis(it.starts_at)
    if (start > nowMs && (!pick || start < isoMillis(pick.starts_at))) pick = it
  }
  return pick
}

export const currentKids = (d: DeviceState, nowMs: number): Schedule | null => currentOf(d.kids.schedules, nowMs)
export const nextKids = (d: DeviceState, nowMs: number): Schedule | null => nextOf(d.kids.schedules, nowMs)
export const currentDeck = (d: DeviceState, nowMs: number): DeckSchedule | null => currentOf(d.slides.schedules, nowMs)
export const nextDeck = (d: DeviceState, nowMs: number): DeckSchedule | null => nextOf(d.slides.schedules, nowMs)
