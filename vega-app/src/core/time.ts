// Wall-clock maths in the site's time zone (device_state.timezone), so schedules and "count down until 9:00"
// mean the time where the church is. Uses Intl; a zone the engine doesn't know falls back to the device's own zone.

export interface ZonedParts { year: number; month: number; day: number; weekday: number; hour: number; minute: number; second: number }

const formatters = new Map<string, Intl.DateTimeFormat | null>()

function formatter(zone: string): Intl.DateTimeFormat | null {
  if (!formatters.has(zone)) {
    let f: Intl.DateTimeFormat | null = null
    try {
      f = new Intl.DateTimeFormat('en-US', {
        timeZone: zone, hourCycle: 'h23', weekday: 'short',
        year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric',
      })
    } catch {
      f = null
    }
    formatters.set(zone, f)
  }
  return formatters.get(zone) ?? null
}

const WEEKDAYS: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 }

/** The civil date and time at [ms] in [zone]. weekday: 0 = Sunday. */
export function zonedParts(ms: number, zone: string): ZonedParts {
  const f = formatter(zone)
  if (f) {
    const p: Record<string, string> = {}
    for (const part of f.formatToParts(new Date(ms))) p[part.type] = part.value
    return {
      year: +p.year, month: +p.month, day: +p.day, weekday: WEEKDAYS[p.weekday] ?? 0,
      hour: +p.hour % 24, minute: +p.minute, second: +p.second,
    }
  }
  const d = new Date(ms)
  return {
    year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(), weekday: d.getDay(),
    hour: d.getHours(), minute: d.getMinutes(), second: d.getSeconds(),
  }
}

/** Minutes [zone] is ahead of UTC at [ms]. */
function offsetMinutes(ms: number, zone: string): number {
  const p = zonedParts(ms, zone)
  const asUtc = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second)
  return Math.round((asUtc - Math.floor(ms / 1000) * 1000) / 60000)
}

/** Epoch millis of a wall-clock time in [zone]. In a DST gap it lands just after; in an overlap, the first one. */
export function zonedToEpoch(year: number, month: number, day: number, hour: number, minute: number, zone: string): number {
  const wall = Date.UTC(year, month - 1, day, hour, minute)
  let guess = wall - offsetMinutes(wall, zone) * 60000
  guess = wall - offsetMinutes(guess, zone) * 60000
  return guess
}

/** "HH:MM" or "HH:MM:SS" as minutes since midnight, or null. */
export function parseClock(s: string | null | undefined): number | null {
  const m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec((s ?? '').trim())
  if (!m) return null
  const h = +m[1]
  const min = +m[2]
  if (h > 23 || min > 59) return null
  return h * 60 + min + (m[3] ? +m[3] / 60 : 0)
}

/** ISO timestamp from the server (always with an offset) to epoch millis; NaN when unreadable. */
export function isoMillis(s: string | null | undefined): number {
  return s ? Date.parse(s) : NaN
}

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

/** "SUN NOV 8 · 9:00 AM" style, as the Android home screen shows "UP NEXT" times. */
export function formatWhen(ms: number, zone: string): string {
  const p = zonedParts(ms, zone)
  const h12 = p.hour % 12 === 0 ? 12 : p.hour % 12
  return `${DAY_NAMES[p.weekday]} ${MONTH_NAMES[p.month - 1]} ${p.day} · ${h12}:${String(p.minute).padStart(2, '0')} ${p.hour < 12 ? 'AM' : 'PM'}`
}
