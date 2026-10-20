import { lazy, Suspense, useMemo, useState } from 'react'
import './../admin.css'
import { useApp } from '../context'
import { fmtBytes, timeAgo, useLoad } from '../lib'
import {
  fmtDate,
  hasLive,
  inBucket,
  loadAdminOrgs,
  loadAllModules,
  planChip,
  relDays,
  trialEndingSoon,
  tvLimitOf,
  type AdminOrg,
  type Bucket,
} from './logic'

const ChurchDetail = lazy(() => import('./ChurchDetail'))

export default function ChurchesPage() {
  const { isPlatformAdmin } = useApp()
  if (!isPlatformAdmin) return <p className="muted">This page is for the platform administrator.</p>
  return <Churches />
}

const FILTERS: { id: Bucket | 'all'; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'new', label: 'New (unreviewed)' },
  { id: 'trial', label: 'Trial' },
  { id: 'paid', label: 'Active paid or internal' },
  { id: 'expired', label: 'Expired or no plan' },
  { id: 'suspended', label: 'Suspended' },
]
type SortKey = 'created' | 'name' | 'seen' | 'media' | 'members'
const SORTS: { id: SortKey; label: string }[] = [
  { id: 'created', label: 'Signed up' },
  { id: 'name', label: 'Name' },
  { id: 'seen', label: 'Last TV seen' },
  { id: 'media', label: 'Media size' },
  { id: 'members', label: 'Members' },
]

function sortValue(o: AdminOrg, k: SortKey): string | number {
  switch (k) {
    case 'created':
      return new Date(o.created_at).getTime()
    case 'name':
      return o.name.toLowerCase()
    case 'seen':
      return o.last_seen_at ? new Date(o.last_seen_at).getTime() : 0
    case 'media':
      return o.storage_bytes
    case 'members':
      return o.member_count
  }
}

function Churches() {
  const { data, error, reload } = useLoad(async () => {
    const [orgs, modules] = await Promise.all([loadAdminOrgs(), loadAllModules()])
    return { orgs, modules }
  })
  const [openId, setOpenId] = useState<string | null>(null)
  const [q, setQ] = useState('')
  const [filter, setFilter] = useState<Bucket | 'all'>('all')
  const [sort, setSort] = useState<SortKey>('created')
  const [desc, setDesc] = useState(true)

  const orgs = data?.orgs
  const stats = useMemo(() => {
    const o = orgs ?? []
    return {
      total: o.length,
      fresh: o.filter((x) => !x.reviewed_at).length,
      ending: o.filter(trialEndingSoon).length,
      expired: o.filter((x) => x.status === 'active' && !hasLive(x)).length,
      suspended: o.filter((x) => x.status === 'suspended').length,
      tvs: o.reduce((n, x) => n + x.screen_count, 0),
      bytes: o.reduce((n, x) => n + x.storage_bytes, 0),
    }
  }, [orgs])

  const rows = useMemo(() => {
    const needle = q.trim().toLowerCase()
    const list = (orgs ?? []).filter(
      (o) =>
        inBucket(o, filter) &&
        (!needle || o.name.toLowerCase().includes(needle) || o.slug.toLowerCase().includes(needle) || o.owner_emails.some((e) => e.toLowerCase().includes(needle))),
    )
    list.sort((a, b) => {
      const x = sortValue(a, sort)
      const y = sortValue(b, sort)
      return (x < y ? -1 : x > y ? 1 : 0) * (desc ? -1 : 1)
    })
    return list
  }, [orgs, q, filter, sort, desc])

  const open = orgs?.find((o) => o.id === openId)
  if (open && data)
    return (
      <Suspense fallback={<p className="muted">Loading…</p>}>
        <ChurchDetail org={open} modules={data.modules} onBack={() => setOpenId(null)} onChanged={reload} />
      </Suspense>
    )

  return (
    <div className="stack">
      {error && (
        <p className="error">
          Couldn't load churches: {error} <button className="link" onClick={reload}>Try again</button>
        </p>
      )}
      <div className="adm-stats">
        <Stat label="Churches" value={stats.total} />
        <Stat label="New, not reviewed" value={stats.fresh} tone={stats.fresh ? 'warn' : undefined} onClick={() => setFilter('new')} />
        <Stat label="Trials ending in 7 days" value={stats.ending} tone={stats.ending ? 'warn' : undefined} />
        <Stat label="Expired or no live plan" value={stats.expired} tone={stats.expired ? 'bad' : undefined} onClick={() => setFilter('expired')} />
        <Stat label="Suspended" value={stats.suspended} onClick={() => setFilter('suspended')} />
        <Stat label="TVs paired" value={stats.tvs} />
        <Stat label="Storage used" value={fmtBytes(stats.bytes) || '0 KB'} />
      </div>

      <div className="card stack-sm">
        <div className="row wrap">
          <label className="field adm-grow">
            <span>Search</span>
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Name, short name or owner email" />
          </label>
          <label className="field">
            <span>Sort by</span>
            <select value={sort} onChange={(e) => setSort(e.target.value as SortKey)}>
              {SORTS.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </label>
          <button className="btn" onClick={() => setDesc(!desc)} aria-label="Reverse the sort order">
            {desc ? '↓ Z-A / newest' : '↑ A-Z / oldest'}
          </button>
        </div>
        <div className="adm-chips">
          {FILTERS.map((f) => (
            <button key={f.id} className={`day ${filter === f.id ? 'on' : ''}`} aria-pressed={filter === f.id} onClick={() => setFilter(f.id)}>
              {f.label}
              {orgs && <span className="adm-count">{orgs.filter((o) => inBucket(o, f.id)).length}</span>}
            </button>
          ))}
        </div>
      </div>

      {!orgs ? (
        !error && <p className="muted">Loading churches…</p>
      ) : rows.length === 0 ? (
        <p className="muted">No churches match.</p>
      ) : (
        <div className="adm-table" role="table">
          <div className="adm-head" role="row">
            <span>Church</span>
            <span>Owner</span>
            <span>Signed up</span>
            <span>Plan</span>
            <span>Last TV seen</span>
            <span>Members</span>
            <span>Media</span>
            <span>Status</span>
          </div>
          {rows.map((o) => (
            <button key={o.id} className="adm-row" role="row" onClick={() => setOpenId(o.id)}>
              <span className="adm-cell adm-name" data-label="Church">
                <b>{o.name}</b>
                {!o.reviewed_at && <span className="adm-badge new">New</span>}
                <span className="muted">{o.slug}</span>
              </span>
              <span className="adm-cell" data-label="Owner">
                {o.owner_emails.length ? o.owner_emails.join(', ') : <span className="muted">none</span>}
              </span>
              <span className="adm-cell" data-label="Signed up">
                {relDays(o.created_at)}
                <span className="muted">{fmtDate(o.created_at)}</span>
              </span>
              <span className="adm-cell" data-label="Plan">
                <PlanChips org={o} />
              </span>
              <span className="adm-cell" data-label="Last TV seen">
                {timeAgo(o.last_seen_at)}
              </span>
              <span className="adm-cell" data-label="Members">
                {o.member_count}
              </span>
              <span className="adm-cell" data-label="Media">
                {o.media_count ? `${fmtBytes(o.storage_bytes)} (${o.media_count})` : '—'}
              </span>
              <span className="adm-cell" data-label="Status">
                <span className={`adm-badge ${o.status === 'suspended' ? 'bad' : 'ok'}`}>{o.status === 'suspended' ? 'Suspended' : 'Active'}</span>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

function Stat({ label, value, tone, onClick }: { label: string; value: number | string; tone?: 'warn' | 'bad'; onClick?: () => void }) {
  const inner = (
    <>
      <span className="adm-stat-value">{value}</span>
      <span className="adm-stat-label">{label}</span>
    </>
  )
  return onClick ? (
    <button className={`adm-stat ${tone ?? ''}`} onClick={onClick}>
      {inner}
    </button>
  ) : (
    <div className={`adm-stat ${tone ?? ''}`}>{inner}</div>
  )
}

export function PlanChips({ org }: { org: AdminOrg }) {
  const { moduleName } = useApp()
  const limit = tvLimitOf(org)
  if (org.entitlements.length === 0) return <span className="adm-chip bad">No plan</span>
  return (
    <span className="adm-chipset">
      {org.entitlements.map((e) => {
        const c = planChip(e, org.status)
        return (
          <span key={e.module} className={`adm-chip ${c.tone}`} title={`${moduleName(e.module)}: ${e.status}, plan ${e.plan}, up to ${e.tv_limit} TVs`}>
            {moduleName(e.module)}: {c.text}
          </span>
        )
      })}
      <span className="muted">
        {org.screen_count}/{limit} TVs
      </span>
    </span>
  )
}
