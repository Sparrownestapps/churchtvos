import { useCallback, useEffect, useState } from 'react'
import type { Entitlement, Location, Role, ScreenModule, Site } from './types'

/** Unwraps a Supabase response, throwing its error so callers can show it. */
export function must<T>(res: { data: T; error: { message: string } | null }): T {
  if (res.error) throw new Error(res.error.message)
  return res.data
}

/** Loads data on mount (and when deps change); reload() fetches again. */
export function useLoad<T>(load: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T>()
  const [error, setError] = useState<string | null>(null)
  const [version, setVersion] = useState(0)
  const reload = useCallback(() => setVersion((v) => v + 1), [])

  useEffect(() => {
    let cancelled = false
    load()
      .then((d) => !cancelled && (setData(d), setError(null)))
      .catch((e: Error) => !cancelled && setError(e.message))
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, ...deps])

  return { data, error, reload }
}

/** Runs an action, alerting on failure. Returns true on success. */
export async function attempt(action: () => Promise<unknown>): Promise<boolean> {
  try {
    await action()
    return true
  } catch (e) {
    alert((e as Error).message)
    return false
  }
}

export function fmtBytes(n: number | null) {
  if (n == null) return ''
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`
  if (n < 1024 * 1024 * 1024) return `${(n / 1024 / 1024).toFixed(1)} MB`
  return `${(n / 1024 / 1024 / 1024).toFixed(2)} GB`
}

export function fmtWhen(iso: string) {
  return new Date(iso).toLocaleString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}

export function timeAgo(iso: string | null) {
  if (!iso) return 'never'
  const s = Math.round((Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.round(s / 60)} min ago`
  if (s < 86400) return `${Math.round(s / 3600)} hr ago`
  return `${Math.round(s / 86400)} days ago`
}

/** Value for <input type="datetime-local"> in the browser's time zone. */
export function toLocalInput(d: Date) {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function nextSundayAt(hour: number) {
  const d = new Date()
  d.setDate(d.getDate() + ((7 - d.getDay()) % 7 || 7))
  d.setHours(hour, 0, 0, 0)
  return d
}

export function locationLabel(location: Location | undefined, sites: Site[]) {
  if (!location) return 'Unknown location'
  const site = sites.find((s) => s.id === location.site_id)
  return site ? `${site.name} · ${location.name}` : location.name
}

export function scopeLabel(siteId: string | null, sites: Site[]) {
  return siteId ? sites.find((s) => s.id === siteId)?.name ?? '—' : 'All sites'
}

/** Is a module switched on right now? Same rule as the server's module_enabled(). */
export function entitled(e: Entitlement | undefined) {
  if (!e) return false
  if (e.status === 'active' || e.status === 'trialing') return true
  return e.status === 'past_due' && !!e.grace_ends_at && new Date(e.grace_ends_at).getTime() > Date.now()
}

export function randomName(file: string) {
  return `${crypto.randomUUID()}-${file.replace(/[^\w.-]+/g, '_')}`
}

export function slugify(name: string) {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 38)
}

export const isHex = (v: string | undefined): v is string => !!v && /^#[0-9a-fA-F]{6}$/.test(v)

export function moveItem<T>(list: T[], i: number, by: number): T[] {
  const next = [...list]
  const [item] = next.splice(i, 1)
  next.splice(Math.max(0, Math.min(next.length, i + by)), 0, item)
  return next
}

// ───────── Weekly rules (module schedules and signage slots) ─────────

/** Display order, Monday first. Values match Postgres: 0 = Sunday. */
export const WEEK = [
  { value: 1, short: 'Mon' },
  { value: 2, short: 'Tue' },
  { value: 3, short: 'Wed' },
  { value: 4, short: 'Thu' },
  { value: 5, short: 'Fri' },
  { value: 6, short: 'Sat' },
  { value: 0, short: 'Sun' },
]

export const MODULE_NAME: Record<ScreenModule, string> = { kids: 'Kids', signage: 'Signage', off: 'Off (black screen)' }

/** "08:00:00" -> "8:00" */
export function shortTime(t: string) {
  const [h, m] = t.split(':')
  return `${Number(h)}:${m}`
}

/** "Mon-Sat", "Sun", "Mon, Wed, Fri" or "daily". */
export function daysLabel(days: number[]) {
  const on = WEEK.filter((d) => days.includes(d.value))
  if (on.length === 7) return 'daily'
  const parts: string[] = []
  for (let i = 0; i < on.length; ) {
    let j = i
    const idx = (k: number) => WEEK.findIndex((d) => d.value === on[k].value)
    while (j + 1 < on.length && idx(j + 1) === idx(j) + 1) j++
    parts.push(j - i >= 2 ? `${on[i].short}-${on[j].short}` : on.slice(i, j + 1).map((d) => d.short).join(', '))
    i = j + 1
  }
  return parts.join(', ')
}

export function timeLabel(start: string, end: string) {
  const allDay = start.startsWith('00:00') && end >= '23:59'
  return allDay ? '' : `${shortTime(start)}-${shortTime(end)}`
}

/** "Signage Mon-Sat, Kids Sun 8:00-13:00" */
export function summarizeRules(
  rules: { module: ScreenModule; days: number[]; start_time: string; end_time: string; priority: number }[],
  fallback?: ScreenModule,
) {
  const text = [...rules]
    .sort((a, b) => a.priority - b.priority)
    .map((r) => [MODULE_NAME[r.module].replace(' (black screen)', ''), daysLabel(r.days), timeLabel(r.start_time, r.end_time)].filter(Boolean).join(' '))
    .join(', ')
  if (!text) return fallback ? `Always ${MODULE_NAME[fallback].replace(' (black screen)', '').toLowerCase()}` : 'No schedule'
  return text
}

export const roleLabel = (r: Role) => ({ owner: 'Owner', admin: 'Admin', editor: 'Editor', operator: 'Operator' })[r]
