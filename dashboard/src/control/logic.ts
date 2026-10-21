import type { Role, Screen } from '../types'

/** The TV app version that understands remote-control commands. */
export const MIN_CONTROL_VERSION = '1.5.0'
export const ONLINE_MS = 90_000
export const STALE_MS = 60_000

export type ScreenStatus = {
  screen_id: string
  module: string | null
  state: 'idle' | 'playing' | 'blank' | 'message'
  title: string | null
  item_label: string | null
  slide_index: number | null
  slide_count: number | null
  outline: string[] | null
  ref_kind: 'deck' | 'playlist' | null
  ref_id: string | null
  updated_at: string
}

export type ShownState = 'playing' | 'blank' | 'message' | 'idle' | 'offline'

/** Roles that may use the Control page (the server enforces this too). */
export const CONTROL_ROLES: Role[] = ['owner', 'admin', 'editor', 'operator']
export const CONTROL_MODULES = ['kids', 'slides', 'signage']

export const canControlNav = (role: Role, moduleOn: (m: string) => boolean) =>
  CONTROL_ROLES.includes(role) && CONTROL_MODULES.some((m) => moduleOn(m))

/** Numeric compare of dotted versions ("1.10.0" > "1.9.0"). Missing parts count as 0. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map((p) => parseInt(p, 10) || 0)
  const pb = b.split('.').map((p) => parseInt(p, 10) || 0)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0)
    if (d !== 0) return d < 0 ? -1 : 1
  }
  return 0
}

/** Unknown versions count as too old (a TV that never reported one is older than 1.5.0). */
export const versionOk = (v: string | null | undefined) => !!v && compareVersions(v, MIN_CONTROL_VERSION) >= 0

export const isOnline = (lastSeen: string | null | undefined, now: number) =>
  !!lastSeen && now - new Date(lastSeen).getTime() < ONLINE_MS

export const isStale = (updatedAt: string | null | undefined, now: number) =>
  !updatedAt || now - new Date(updatedAt).getTime() > STALE_MS

/** What the state chip says. A stale status reads as idle; an offline TV as offline. */
export function shownState(screen: Pick<Screen, 'last_seen_at'>, status: ScreenStatus | undefined, now: number): ShownState {
  if (!isOnline(screen.last_seen_at, now)) return 'offline'
  if (!status || isStale(status.updated_at, now)) return 'idle'
  return status.state
}

/** 0 to 1, or null when there is no slide count. */
export function progress(status: ScreenStatus | undefined): number | null {
  if (!status || status.slide_index == null || !status.slide_count || status.slide_count < 1) return null
  return Math.max(0, Math.min(1, (status.slide_index + 1) / status.slide_count))
}

/** Clamp a reported index into the outline, or -1 when there is none. */
export function currentOutlineIndex(status: ScreenStatus | undefined): number {
  const o = status?.outline
  if (!o || o.length === 0 || status?.slide_index == null) return -1
  return Math.max(0, Math.min(o.length - 1, status.slide_index))
}

export function agoLabel(iso: string | null | undefined, now: number): string {
  if (!iso) return 'never'
  const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000))
  if (s < 60) return `${s} s ago`
  if (s < 3600) return `${Math.round(s / 60)} min ago`
  if (s < 86400) return `${Math.round(s / 3600)} hr ago`
  return `${Math.round(s / 86400)} days ago`
}

export const STATE_LABEL: Record<ShownState, string> = {
  playing: 'Playing',
  blank: 'Blank',
  message: 'Message',
  idle: 'Idle',
  offline: 'Offline',
}
