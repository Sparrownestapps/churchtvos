import { supabase } from '../supabase'
import { entitled, must } from '../lib'
import type { Entitlement, ModuleDef } from '../types'

export type OrgStatus = 'active' | 'suspended'

/** One row of the admin_list_organizations() RPC. */
export type AdminOrg = {
  id: string
  name: string
  slug: string
  created_at: string
  status: OrgStatus
  suspended_reason: string | null
  admin_notes: string | null
  reviewed_at: string | null
  owner_emails: string[]
  member_count: number
  screen_count: number
  last_seen_at: string | null
  media_count: number
  storage_bytes: number
  song_count: number
  deck_count: number
  playlist_count: number
  entitlements: AdminEnt[]
  /** EXPERIMENTAL NDI switch (organizations.ndi_enabled). */
  ndi_enabled: boolean
}

export type AdminEnt = {
  module: string
  status: Entitlement['status']
  tv_limit: number
  plan: string
  current_period_end: string | null
  grace_ends_at: string | null
  live: boolean
}

export type AuditEntry = {
  id: number
  at: string
  actor_email: string | null
  organization_id: string | null
  action: string
  detail: Record<string, unknown> | null
}

export const DAY = 86_400_000
export const ONLINE_MS = 90_000

export async function loadAdminOrgs(): Promise<AdminOrg[]> {
  const rows = must(await supabase.rpc('admin_list_organizations')) as AdminOrg[]
  // bigint columns can arrive as numbers or strings depending on the driver; normalise.
  return rows.map((r) => ({
    ...r,
    member_count: Number(r.member_count),
    screen_count: Number(r.screen_count),
    media_count: Number(r.media_count),
    storage_bytes: Number(r.storage_bytes),
    song_count: Number(r.song_count),
    deck_count: Number(r.deck_count),
    playlist_count: Number(r.playlist_count),
    owner_emails: r.owner_emails ?? [],
    entitlements: r.entitlements ?? [],
    ndi_enabled: !!r.ndi_enabled,
  }))
}

/** All applications, including ones not released yet (the app context only has the released ones). */
export async function loadAllModules(): Promise<ModuleDef[]> {
  return must(await supabase.from('modules').select('*').order('sort')) as ModuleDef[]
}

/** Same rule as the database: see entitled() in lib.ts. */
export const isLive = (e: AdminEnt | Entitlement, status: OrgStatus) =>
  entitled({ organization_id: '', ...e } as Entitlement, status)

export const daysLeft = (iso: string | null) => (iso ? Math.ceil((new Date(iso).getTime() - Date.now()) / DAY) : null)

export const fmtDate = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }) : ''

/** "3 days ago" / "in 4 days", rounded to whole days. */
export function relDays(iso: string) {
  const d = Math.round((Date.now() - new Date(iso).getTime()) / DAY)
  if (d === 0) return 'today'
  return d > 0 ? `${d} day${d === 1 ? '' : 's'} ago` : `in ${-d} day${d === -1 ? '' : 's'}`
}

export type Tone = 'ok' | 'warn' | 'bad' | 'off'

/** Plain-words label for one module's plan, e.g. "Live trial 12d left". */
export function planChip(e: AdminEnt, status: OrgStatus): { text: string; tone: Tone } {
  const live = isLive(e, status)
  if (e.status === 'trialing') {
    const d = daysLeft(e.current_period_end)
    if (live) return { text: d === null ? 'Live trial' : `Live trial ${Math.max(d, 0)}d left`, tone: d !== null && d <= 7 ? 'warn' : 'ok' }
    return { text: 'Expired', tone: 'bad' }
  }
  if (e.status === 'active') return { text: e.plan === 'internal' ? 'Active internal' : 'Active', tone: live ? 'ok' : 'off' }
  if (e.status === 'past_due') return { text: 'Past due', tone: live ? 'warn' : 'bad' }
  return { text: 'Canceled', tone: 'off' }
}

export type Bucket = 'new' | 'trial' | 'paid' | 'expired' | 'suspended'

export const hasLive = (o: AdminOrg) => o.entitlements.some((e) => isLive(e, o.status))
export const liveTrials = (o: AdminOrg) => o.entitlements.filter((e) => e.status === 'trialing' && isLive(e, o.status))
export const trialEndingSoon = (o: AdminOrg) =>
  o.status === 'active' && liveTrials(o).some((e) => e.current_period_end && new Date(e.current_period_end).getTime() - Date.now() <= 7 * DAY)

export function inBucket(o: AdminOrg, b: Bucket | 'all'): boolean {
  switch (b) {
    case 'all':
      return true
    case 'new':
      return !o.reviewed_at
    case 'suspended':
      return o.status === 'suspended'
    case 'trial':
      return o.status === 'active' && liveTrials(o).length > 0
    case 'paid':
      return o.status === 'active' && o.entitlements.some((e) => e.status === 'active' && isLive(e, o.status))
    case 'expired':
      return o.status === 'active' && !hasLive(o)
  }
}

/** The TV limit the pairing check uses: the largest limit among live plans (0 if none). */
export const tvLimitOf = (o: { entitlements: AdminEnt[]; status: OrgStatus }) =>
  o.entitlements.reduce((m, e) => (isLive(e, o.status) ? Math.max(m, e.tv_limit) : m), 0)

// ───────── Quick plan presets ─────────

export type PresetId = 'trial' | 'extend' | 'internal' | 'standard' | 'cancel'
export const PRESETS: { id: PresetId; label: string }[] = [
  { id: 'trial', label: 'Start 30-day trial (2 TVs)' },
  { id: 'extend', label: 'Extend trial by 14 days' },
  { id: 'internal', label: 'Free internal plan (50 TVs)' },
  { id: 'standard', label: 'Standard (10 TVs)' },
  { id: 'cancel', label: 'Cancel plan' },
]

export type EntRow = {
  organization_id: string
  module: string
  status: Entitlement['status']
  tv_limit: number
  plan: string
  current_period_end: string | null
  grace_ends_at: string | null
}

/** The row a preset would write for one module (null = leave this module alone). */
export function applyPreset(id: PresetId, orgId: string, module: string, cur: AdminEnt | undefined): EntRow | null {
  const base: EntRow = {
    organization_id: orgId,
    module,
    status: cur?.status ?? 'active',
    tv_limit: cur?.tv_limit ?? 0,
    plan: cur?.plan ?? 'standard',
    current_period_end: cur?.current_period_end ?? null,
    grace_ends_at: cur?.grace_ends_at ?? null,
  }
  const now = Date.now()
  switch (id) {
    case 'trial':
      return { ...base, status: 'trialing', tv_limit: 2, plan: 'trial', current_period_end: new Date(now + 30 * DAY).toISOString(), grace_ends_at: null }
    case 'extend': {
      if (cur?.status === 'active') return null // paid or internal plans have no trial to extend
      const from = Math.max(now, cur?.current_period_end ? new Date(cur.current_period_end).getTime() : now)
      return { ...base, status: 'trialing', tv_limit: cur?.tv_limit || 2, plan: cur?.plan ?? 'trial', current_period_end: new Date(from + 14 * DAY).toISOString(), grace_ends_at: null }
    }
    case 'internal':
      return { ...base, status: 'active', tv_limit: 50, plan: 'internal', current_period_end: null, grace_ends_at: null }
    case 'standard':
      return { ...base, status: 'active', tv_limit: 10, plan: 'standard', current_period_end: null, grace_ends_at: null }
    case 'cancel':
      return cur ? { ...base, status: 'canceled' } : null
  }
}

// ───────── Audit entries in plain words ─────────

type PlanSnap = { status?: string; tv_limit?: number; plan?: string; current_period_end?: string | null }
const snap = (s: unknown): string => {
  const p = s as PlanSnap | null
  if (!p) return ''
  const end = p.current_period_end ? ` until ${fmtDate(p.current_period_end)}` : ''
  return `${p.status ?? '?'} ${p.tv_limit ?? 0} TV${p.tv_limit === 1 ? '' : 's'}${end}`
}

export function describeAudit(a: AuditEntry, moduleName: (id: string) => string): string {
  const d = (a.detail ?? {}) as Record<string, unknown>
  switch (a.action) {
    case 'plan_insert':
      return `${moduleName(String(d.module))}: added ${snap(d.to)}`
    case 'plan_update':
      return `${moduleName(String(d.module))}: ${snap(d.from)} -> ${snap(d.to)}`
    case 'plan_delete':
      return `${moduleName(String(d.module))}: removed (was ${snap(d.from)})`
    case 'church_suspended':
      return `Suspended${d.reason ? `: ${String(d.reason)}` : ''}`
    case 'church_reactivated':
      return 'Reactivated'
    case 'church_reviewed':
      return 'Marked reviewed'
    case 'ndi_enabled':
      return 'Experimental NDI sources switched ON'
    case 'ndi_disabled':
      return 'Experimental NDI sources switched OFF'
    default:
      return a.action
  }
}

export const AUDIT_ACTIONS = ['plan_insert', 'plan_update', 'plan_delete', 'church_suspended', 'church_reactivated', 'church_reviewed', 'ndi_enabled', 'ndi_disabled']

/** Date for <input type="date"> in the browser's time zone. */
export function toDateInput(iso: string | null) {
  if (!iso) return ''
  const d = new Date(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

/** End of that local day, as an ISO string (null for empty). */
export const fromDateInput = (v: string) => (v ? new Date(`${v}T23:59:59`).toISOString() : null)
