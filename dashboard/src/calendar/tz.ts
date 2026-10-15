/**
 * Time zone helpers for the calendar.
 *
 * The calendar grid runs FullCalendar with timeZone "UTC" and feeds it "wall" dates: a Date whose UTC fields
 * hold the clock time in the SITE's time zone (so 8:00 in Toronto is Date.UTC(..., 8, 0) whatever the browser
 * zone is). toWall() converts a real instant into a wall date, fromWall() converts back. Both use Intl only,
 * so daylight saving is handled by the platform's time zone database.
 */
const cache = new Map<string, Intl.DateTimeFormat>()
function fmt(tz: string) {
  let f = cache.get(tz)
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      second: 'numeric',
    })
    cache.set(tz, f)
  }
  return f
}

export const browserTz = () => Intl.DateTimeFormat().resolvedOptions().timeZone

/** Falls back to the browser's zone if the name is unknown. */
export function safeTz(tz: string | null | undefined) {
  if (!tz) return browserTz()
  try {
    fmt(tz)
    return tz
  } catch {
    return browserTz()
  }
}

/** Real instant -> wall date (UTC fields = the clock in `tz`). */
export function toWall(ms: number, tz: string): Date {
  const p: Record<string, number> = {}
  for (const part of fmt(tz).formatToParts(new Date(ms))) if (part.type !== 'literal') p[part.type] = Number(part.value)
  return new Date(Date.UTC(p.year, p.month - 1, p.day, p.hour % 24, p.minute, p.second))
}

const offsetAt = (ms: number, tz: string) => toWall(ms, tz).getTime() - Math.floor(ms / 1000) * 1000

/**
 * Wall date -> real instant. Two passes so times just after a clock change come out right.
 * A time that does not exist (spring forward) lands an hour later; an ambiguous one (fall back) takes the first.
 */
export function fromWall(wall: Date, tz: string): Date {
  const w = wall.getTime()
  const first = w - offsetAt(w, tz)
  return new Date(w - offsetAt(first, tz))
}

const pad = (n: number) => String(n).padStart(2, '0')
export const ymd = (w: Date) => `${w.getUTCFullYear()}-${pad(w.getUTCMonth() + 1)}-${pad(w.getUTCDate())}`
export const hm = (w: Date) => `${pad(w.getUTCHours())}:${pad(w.getUTCMinutes())}`
export const addDays = (w: Date, n: number) => new Date(w.getTime() + n * 86_400_000)
export const wallOf = (date: string, time = '00:00') => {
  const [y, m, d] = date.split('-').map(Number)
  const [h, mi] = time.split(':').map(Number)
  return new Date(Date.UTC(y, m - 1, d, h, mi || 0, 0))
}
/** Monday 00:00 (wall) of the week containing w. */
export function weekStartOf(w: Date) {
  const day = new Date(Date.UTC(w.getUTCFullYear(), w.getUTCMonth(), w.getUTCDate()))
  return addDays(day, -((day.getUTCDay() + 6) % 7))
}

/** A rule's end time as a wall date on `date` ("23:59:59" means the end of the day, i.e. midnight). */
export function ruleEnd(date: string, end: string): Date {
  const e = end.slice(0, 5)
  return end >= '23:59' ? addDays(wallOf(date), 1) : wallOf(date, e)
}

/** Turns an end wall date back into a rule end time ("HH:MM:SS"), or null if it is past midnight of the start day. */
export function endToRule(start: Date, end: Date): string | null {
  const diff = Math.round((end.getTime() - wallOf(ymd(start)).getTime()) / 60_000)
  if (diff === 1440) return '23:59:59'
  if (diff > 1440 || diff <= 0) return null
  return `${hm(end)}:00`
}

/** "EDT", "GMT+1"... */
export function tzAbbr(tz: string, at = new Date()) {
  try {
    return new Intl.DateTimeFormat('en-US', { timeZone: tz, timeZoneName: 'short' }).formatToParts(at).find((p) => p.type === 'timeZoneName')?.value ?? tz
  } catch {
    return tz
  }
}

export function hourDiff(tz: string, at = new Date()) {
  return (offsetAt(at.getTime(), tz) - offsetAt(at.getTime(), browserTz())) / 3_600_000
}

export const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

export function fmtDay(date: string) {
  return wallOf(date).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' })
}

export function fmtClock(time: string) {
  const [h, m] = time.split(':').map(Number)
  return `${h % 12 || 12}:${pad(m)} ${h < 12 ? 'AM' : 'PM'}`
}
