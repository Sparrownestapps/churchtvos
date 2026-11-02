import type { CountdownSpec } from './model'
import { parseClock, zonedParts, zonedToEpoch } from './time'

/** Epoch millis of today's [until] ("HH:MM") in [zone], or null when it can't be read. */
export function untilMillis(until: string | null, nowMs: number, zone: string): number | null {
  const mins = parseClock(until)
  if (mins === null) return null
  const p = zonedParts(nowMs, zone)
  return zonedToEpoch(p.year, p.month, p.day, Math.floor(mins / 60), Math.floor(mins % 60), zone)
}

/** When a countdown that appears at [startedAt] reaches zero. */
export function countdownEnd(spec: CountdownSpec, startedAt: number, zone: string): number {
  if (spec.mode === 'until') return untilMillis(spec.until, startedAt, zone) ?? startedAt
  return startedAt + spec.seconds * 1000
}

/** "5:00", "0:07", or "1:05:00" for an hour or more. Rounds up so 0:00 only shows at the end. */
export function formatCountdown(remainingMs: number): string {
  const total = Math.ceil(Math.max(0, remainingMs) / 1000)
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const ss = String(s).padStart(2, '0')
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`
}

/** Volume multiplier: 1 until the last [fadeSeconds], then ramps to 0 at zero. */
export function fadeFactor(remainingMs: number, fadeSeconds: number): number {
  if (fadeSeconds <= 0) return 1
  return Math.min(1, Math.max(0, remainingMs / 1000 / fadeSeconds))
}
