import { useState, type FormEvent } from 'react'
import './../admin.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { attempt, fmtBytes, fmtWhen, must, roleLabel, timeAgo, useLoad } from '../lib'
import type { Membership, ModuleDef, Role, Screen } from '../types'
import AuditList from './AuditList'
import {
  ONLINE_MS,
  PRESETS,
  applyPreset,
  daysLeft,
  fmtDate,
  fromDateInput,
  isLive,
  relDays,
  toDateInput,
  tvLimitOf,
  type AdminEnt,
  type AdminOrg,
  type AuditEntry,
  type EntRow,
  type PresetId,
} from './logic'

type Props = { org: AdminOrg; modules: ModuleDef[]; onBack: () => void; onChanged: () => void }

export default function ChurchDetail({ org, modules, onBack, onChanged }: Props) {
  const { switchOrg, reloadOrgs, isPlatformAdmin } = useApp()
  const [busy, setBusy] = useState(false)
  if (!isPlatformAdmin) return null // never call the admin RPCs for anyone else

  const moduleName = (id: string) => modules.find((m) => m.id === id)?.name ?? id.charAt(0).toUpperCase() + id.slice(1)

  async function adminUpdate(args: { p_status?: string; p_reason?: string; p_notes?: string; p_reviewed?: boolean }) {
    return attempt(async () => {
      setBusy(true)
      try {
        must(await supabase.rpc('admin_update_organization', { p_org: org.id, ...args }))
      } finally {
        setBusy(false)
      }
      onChanged()
    })
  }

  function openChurch() {
    location.hash = 'screens'
    switchOrg(org.id)
  }

  return (
    <div className="stack">
      <div className="card stack-sm">
        <button className="link" onClick={onBack}>
          ← All churches
        </button>
        <div className="row spread wrap-sm">
          <div>
            <h2 className="adm-title">
              {org.name} {!org.reviewed_at && <span className="adm-badge new">New</span>}{' '}
              <span className={`adm-badge ${org.status === 'suspended' ? 'bad' : 'ok'}`}>{org.status === 'suspended' ? 'Suspended' : 'Active'}</span>
            </h2>
            <span className="muted">
              {org.slug} · signed up {relDays(org.created_at)} ({fmtDate(org.created_at)}) · {org.owner_emails.join(', ') || 'no owner yet'}
            </span>
          </div>
          <span className="row wrap-sm">
            <button className="btn" onClick={openChurch}>
              Open this church
            </button>
            {!org.reviewed_at && (
              <button className="btn primary" disabled={busy} onClick={() => adminUpdate({ p_reviewed: true })}>
                Mark reviewed
              </button>
            )}
          </span>
        </div>
        {org.status === 'suspended' && org.suspended_reason && <p className="error">Suspended: {org.suspended_reason}</p>}
      </div>

      <PlanSection org={org} modules={modules} moduleName={moduleName} onChanged={onChanged} />
      <SuspendSection org={org} busy={busy} onSubmit={adminUpdate} />
      <PeopleSection org={org} modules={modules} onChanged={onChanged} />
      <ScreensSection org={org} />
      <UsageSection org={org} />
      <NotesSection org={org} onSave={(notes) => adminUpdate({ p_notes: notes })} />
      <ActivitySection org={org} moduleName={moduleName} />
      <DangerSection org={org} onDeleted={() => (reloadOrgs(), onChanged(), onBack())} />
    </div>
  )
}

// ───────── Plan & permissions ─────────

function PlanSection({ org, modules, moduleName, onChanged }: { org: AdminOrg; modules: ModuleDef[]; moduleName: (id: string) => string; onChanged: () => void }) {
  const { reloadOrg, org: current } = useApp()
  const [ticked, setTicked] = useState<string[]>([])
  const [scope, setScope] = useState<'all' | 'ticked'>('all')
  const byModule = new Map(org.entitlements.map((e) => [e.module, e]))
  // Modules this church has a row for that are no longer in the registry still show up.
  const ids = [...modules.map((m) => m.id), ...org.entitlements.map((e) => e.module).filter((id) => !modules.some((m) => m.id === id))]

  const saved = () => {
    onChanged()
    if (current.id === org.id) reloadOrg() // keep the church's own dashboard in step if we are viewing it
  }

  async function runPreset(id: PresetId) {
    const targets = scope === 'all' ? org.entitlements.map((e) => e.module) : ticked
    if (targets.length === 0) return alert(scope === 'all' ? 'This church has no modules yet. Tick modules and choose "Only ticked modules".' : 'Tick at least one module first.')
    const rows = targets.map((m) => applyPreset(id, org.id, m, byModule.get(m))).filter((r): r is EntRow => r !== null)
    const label = PRESETS.find((p) => p.id === id)?.label ?? id
    if (rows.length === 0) return alert(`"${label}" doesn't apply to ${targets.map(moduleName).join(', ')}.`)
    if (!confirm(`${label}\n\nApply to: ${rows.map((r) => moduleName(r.module)).join(', ')}?`)) return
    if (await attempt(async () => must(await supabase.from('entitlements').upsert(rows, { onConflict: 'organization_id,module' })))) saved()
  }

  return (
    <div className="card stack-sm">
      <h3>Plan and permissions</h3>
      <div className="stack-sm adm-presets">
        <div className="row wrap-sm">
          <b>Quick presets for</b>
          <label className="check">
            <input type="radio" checked={scope === 'all'} onChange={() => setScope('all')} /> All modules this church has
          </label>
          <label className="check">
            <input type="radio" checked={scope === 'ticked'} onChange={() => setScope('ticked')} /> Only ticked modules
          </label>
        </div>
        <div className="row wrap-sm">
          {PRESETS.map((p) => (
            <button key={p.id} className="btn" onClick={() => runPreset(p.id)}>
              {p.label}
            </button>
          ))}
        </div>
      </div>

      {ids.map((id) => {
        const def = modules.find((m) => m.id === id)
        const cur = byModule.get(id)
        return (
          <EntitlementEditor
            key={`${id}:${cur ? JSON.stringify(cur) : 'none'}`}
            orgId={org.id}
            orgStatus={org.status}
            module={id}
            name={moduleName(id)}
            released={def ? def.available : false}
            current={cur}
            ticked={ticked.includes(id)}
            onTick={(on) => setTicked(on ? [...ticked, id] : ticked.filter((x) => x !== id))}
            onSaved={saved}
          />
        )
      })}

      <p className="muted">
        <b>What the TV limit means:</b> it is the number of TVs this church may have paired at once. When a church already has that many
        paired and tries to pair another, the pairing is refused with a plan-limit message. If several modules are live, the largest limit
        applies. Lowering the limit does not unpair TVs that are already paired.
      </p>
      <p className="muted">
        <b>When is a module live?</b> Active plans are live. A trial is live until its end date (live indefinitely if there is no date). A past-due plan
        is live until its grace date. Nothing is live while the church is suspended. A module that is not live stops showing on the TVs and shows as
        locked in the church's dashboard.
      </p>
    </div>
  )
}

const STATUSES = ['trialing', 'active', 'past_due', 'canceled'] as const

function EntitlementEditor({
  orgId,
  orgStatus,
  module,
  name,
  released,
  current,
  ticked,
  onTick,
  onSaved,
}: {
  orgId: string
  orgStatus: AdminOrg['status']
  module: string
  name: string
  released: boolean
  current?: AdminEnt
  ticked: boolean
  onTick: (on: boolean) => void
  onSaved: () => void
}) {
  const [status, setStatus] = useState<AdminEnt['status']>(current?.status ?? 'active')
  const [limit, setLimit] = useState(current?.tv_limit ?? 2)
  const [plan, setPlan] = useState(current?.plan ?? 'standard')
  const [end, setEnd] = useState(toDateInput(current?.current_period_end ?? null))
  const [grace, setGrace] = useState(toDateInput(current?.grace_ends_at ?? null))

  const preview = { module, status, tv_limit: limit, plan, current_period_end: fromDateInput(end), grace_ends_at: fromDateInput(grace), live: false }
  const live = isLive(preview, orgStatus)
  const liveSaved = current ? isLive(current, orgStatus) : false
  const left = current?.status === 'trialing' ? daysLeft(current.current_period_end) : null

  async function save() {
    const row: EntRow = { organization_id: orgId, module, status, tv_limit: Math.max(0, Math.floor(limit) || 0), plan: plan.trim() || 'standard', current_period_end: preview.current_period_end, grace_ends_at: preview.grace_ends_at }
    if (await attempt(async () => must(await supabase.from('entitlements').upsert(row, { onConflict: 'organization_id,module' })))) onSaved()
  }
  async function remove() {
    if (!confirm(`Remove ${name} from this church? It will lose access to the module.`)) return
    if (await attempt(async () => must(await supabase.from('entitlements').delete().eq('organization_id', orgId).eq('module', module)))) onSaved()
  }

  return (
    <div className="adm-ent">
      <div className="row spread wrap-sm">
        <label className="check">
          <input type="checkbox" checked={ticked} onChange={(e) => onTick(e.target.checked)} aria-label={`Select ${name}`} />
          <b>{name}</b>
          {!released && <span className="adm-badge off">not released</span>}
        </label>
        {current ? (
          <span className={`adm-badge ${liveSaved ? 'ok' : 'bad'}`}>
            {liveSaved ? 'LIVE now' : orgStatus === 'suspended' ? 'Not live (suspended)' : 'NOT live'}
            {left !== null && liveSaved ? ` · ${Math.max(left, 0)}d left` : ''}
          </span>
        ) : (
          <span className="adm-badge off">Not included</span>
        )}
      </div>
      <div className="row wrap">
        <label className="field">
          <span>Status</span>
          <select value={status} onChange={(e) => setStatus(e.target.value as AdminEnt['status'])}>
            {STATUSES.map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>TV limit</span>
          <input type="number" min={0} className="adm-num" value={limit} onChange={(e) => setLimit(Number(e.target.value))} />
        </label>
        <label className="field">
          <span>Plan name</span>
          <input className="adm-plan" value={plan} onChange={(e) => setPlan(e.target.value)} />
        </label>
        <label className="field">
          <span>Trial / period ends</span>
          <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} />
        </label>
        <label className="field">
          <span>Grace ends</span>
          <input type="date" value={grace} onChange={(e) => setGrace(e.target.value)} />
        </label>
        <button className="btn primary" onClick={save}>
          {current ? 'Save' : 'Add'}
        </button>
        {current && (
          <button className="btn danger" onClick={remove}>
            Remove
          </button>
        )}
      </div>
      <p className="muted">
        {current ? `Saved: ${current.status}, ${current.plan}, ${current.tv_limit} TV${current.tv_limit === 1 ? '' : 's'}${current.current_period_end ? `, ends ${fmtDate(current.current_period_end)}` : ''}${current.grace_ends_at ? `, grace to ${fmtDate(current.grace_ends_at)}` : ''}. ` : ''}
        With these values it would be {live ? 'live' : 'not live'}.
      </p>
    </div>
  )
}

// ───────── Suspend / reactivate ─────────

function SuspendSection({ org, busy, onSubmit }: { org: AdminOrg; busy: boolean; onSubmit: (a: { p_status: string; p_reason?: string }) => Promise<boolean> }) {
  const [reason, setReason] = useState('')
  const suspended = org.status === 'suspended'
  return (
    <div className="card stack-sm">
      <h3>{suspended ? 'Reactivate this church' : 'Suspend this church'}</h3>
      <p className="muted">
        Suspending means TVs stop showing content and members cannot use modules until you reactivate. Their data is kept. Every change is recorded in the activity log.
      </p>
      {suspended ? (
        <div className="row">
          <button
            className="btn primary"
            disabled={busy}
            onClick={async () => {
              if (confirm(`Reactivate ${org.name}?`)) await onSubmit({ p_status: 'active' })
            }}
          >
            Reactivate
          </button>
        </div>
      ) : (
        <form
          className="stack-sm"
          onSubmit={async (e: FormEvent) => {
            e.preventDefault()
            if (!confirm(`Suspend ${org.name}? Their TVs will stop showing content.`)) return
            if (await onSubmit({ p_status: 'suspended', p_reason: reason.trim() })) setReason('')
          }}
        >
          <label className="field">
            <span>Reason (only you see this)</span>
            <textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Unpaid invoice, abuse report" />
          </label>
          <div>
            <button className="btn danger" disabled={busy}>
              Suspend
            </button>
          </div>
        </form>
      )}
    </div>
  )
}

// ───────── People ─────────

const ROLE_OPTIONS: Role[] = ['owner', 'admin', 'editor', 'operator']

function PeopleSection({ org, modules, onChanged }: { org: AdminOrg; modules: ModuleDef[]; onChanged: () => void }) {
  const [email, setEmail] = useState('')
  const [role, setRole] = useState<Role>('owner')
  const { data: people, error, reload } = useLoad(
    async () => must(await supabase.from('memberships').select('*').eq('organization_id', org.id).order('email')) as Membership[],
    [org.id],
  )

  async function add(e: FormEvent) {
    e.preventDefault()
    const row = {
      organization_id: org.id,
      email: email.trim().toLowerCase(),
      role,
      modules: modules.filter((m) => m.available).map((m) => m.id),
      site_ids: null,
    }
    if (await attempt(async () => must(await supabase.from('memberships').insert(row)))) {
      setEmail('')
      reload()
      onChanged()
    }
  }
  async function remove(m: Membership) {
    if (!confirm(`Remove ${m.email} from ${org.name}?`)) return
    if (await attempt(async () => must(await supabase.from('memberships').delete().eq('id', m.id).eq('organization_id', org.id)))) {
      reload()
      onChanged()
    }
  }

  return (
    <div className="card stack-sm">
      <h3>People</h3>
      {error && <p className="error">{error}</p>}
      {(people ?? []).map((m) => (
        <div key={m.id} className="row spread wrap-sm list-row">
          <div>
            <b>{m.email}</b>
            <div className="muted">
              {roleLabel(m.role)} · {m.role === 'owner' || m.role === 'admin' ? 'all modules' : m.modules.join(', ') || 'no modules'} ·{' '}
              {m.user_id ? 'has signed in' : 'not signed in yet'}
            </div>
          </div>
          <button className="link danger" onClick={() => remove(m)}>
            Remove
          </button>
        </div>
      ))}
      {people && people.length === 0 && <p className="muted">Nobody has access yet.</p>}
      <form className="row wrap panel" onSubmit={add}>
        <label className="field adm-grow">
          <span>Add a person by email</span>
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} placeholder="name@church.org" />
        </label>
        <label className="field">
          <span>Role</span>
          <select value={role} onChange={(e) => setRole(e.target.value as Role)}>
            {ROLE_OPTIONS.map((r) => (
              <option key={r} value={r}>
                {roleLabel(r)}
              </option>
            ))}
          </select>
        </label>
        <button className="btn primary">Add</button>
      </form>
      <p className="muted">No email is sent. They sign in or create an account with this same address and the church appears. New people get every released module and all sites. The last owner cannot be removed.</p>
    </div>
  )
}

// ───────── Screens ─────────

function ScreensSection({ org }: { org: AdminOrg }) {
  const { data, error } = useLoad(async () => {
    const [screens, locations] = await Promise.all([
      supabase.from('screens').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('locations').select('id,name').eq('organization_id', org.id),
    ])
    return {
      screens: must(screens) as Screen[],
      locations: new Map((must(locations) as { id: string; name: string }[]).map((l) => [l.id, l.name])),
    }
  }, [org.id])
  const orient = { landscape: 'Landscape', portrait: 'Portrait', portrait_flipped: 'Portrait (flipped)' }
  return (
    <div className="card stack-sm">
      <h3>Screens ({data?.screens.length ?? org.screen_count})</h3>
      {error && <p className="error">{error}</p>}
      {data?.screens.length === 0 && <p className="muted">No TVs paired.</p>}
      {data?.screens.map((s) => {
        const online = !!s.last_seen_at && Date.now() - new Date(s.last_seen_at).getTime() < ONLINE_MS
        return (
          <div key={s.id} className="row spread wrap-sm list-row">
            <div>
              <b>{s.name || 'Unnamed TV'}</b>
              <div className="muted">
                {(s.location_id && data.locations.get(s.location_id)) || 'No location'} · {orient[s.orientation]} · app {s.app_version ?? 'unknown'}
                {s.model ? ` · ${s.model}` : ''}
              </div>
            </div>
            <span className={`adm-badge ${online ? 'ok' : 'off'}`}>
              {online ? 'Online' : 'Offline'} · seen {timeAgo(s.last_seen_at)}
            </span>
          </div>
        )
      })}
    </div>
  )
}

// ───────── Usage ─────────

function UsageSection({ org }: { org: AdminOrg }) {
  const limit = tvLimitOf(org)
  const items: [string, string][] = [
    ['Media', `${org.media_count} files, ${fmtBytes(org.storage_bytes) || '0 KB'}`],
    ['Songs', String(org.song_count)],
    ['Decks', String(org.deck_count)],
    ['Playlists', String(org.playlist_count)],
    ['TVs', `${org.screen_count} of ${limit} allowed`],
    ['Members', String(org.member_count)],
  ]
  return (
    <div className="card stack-sm">
      <h3>Usage</h3>
      <div className="adm-usage">
        {items.map(([k, v]) => (
          <div key={k} className={k === 'TVs' && org.screen_count > limit ? 'bad' : ''}>
            <span className="muted">{k}</span>
            <b>{v}</b>
          </div>
        ))}
      </div>
      {org.screen_count > limit && <p className="error">More TVs are paired than the current limit allows. Existing TVs keep working; new pairing is refused.</p>}
    </div>
  )
}

// ───────── Notes ─────────

function NotesSection({ org, onSave }: { org: AdminOrg; onSave: (notes: string) => Promise<boolean> }) {
  const [notes, setNotes] = useState(org.admin_notes ?? '')
  const [savedAt, setSavedAt] = useState<Date | null>(null)
  return (
    <div className="card stack-sm">
      <h3>Internal notes</h3>
      <p className="muted">Only platform administrators can see these. They are never shown to the church.</p>
      <textarea rows={4} value={notes} onChange={(e) => setNotes(e.target.value)} />
      <div className="row">
        <button
          className="btn primary"
          onClick={async () => {
            if (await onSave(notes)) setSavedAt(new Date())
          }}
        >
          Save notes
        </button>
        {savedAt && <span className="notice">Saved {savedAt.toLocaleTimeString()}</span>}
      </div>
    </div>
  )
}

// ───────── Activity ─────────

function ActivitySection({ org, moduleName }: { org: AdminOrg; moduleName: (id: string) => string }) {
  const { data, error } = useLoad(
    async () =>
      must(await supabase.from('admin_audit_log').select('*').eq('organization_id', org.id).order('at', { ascending: false }).limit(50)) as AuditEntry[],
    [org.id],
  )
  return (
    <div className="card stack-sm">
      <h3>Activity</h3>
      {error && <p className="error">{error}</p>}
      {data && <AuditList entries={data} moduleName={moduleName} />}
    </div>
  )
}

// ───────── Danger zone ─────────

function DangerSection({ org, onDeleted }: { org: AdminOrg; onDeleted: () => void }) {
  const [typed, setTyped] = useState('')
  const [files, setFiles] = useState<string | null>(null)

  async function countFiles() {
    const { data, error } = await supabase.storage.from('media').list(org.id, { limit: 1000 })
    setFiles(error ? `Couldn't list files: ${error.message}` : `${data.length}${data.length === 1000 ? '+' : ''} item(s) under media/${org.id}/ right now.`)
  }
  async function del() {
    if (typed !== org.slug) return
    if (!confirm(`Permanently delete ${org.name} and all of its data? This cannot be undone.`)) return
    const ok = await attempt(async () => must(await supabase.from('organizations').delete().eq('id', org.id)))
    if (ok) {
      alert(`${org.name} was deleted.\n\nIts uploaded files were NOT removed. Delete the folder "${org.id}/" in the "media" storage bucket (Supabase dashboard, Storage) to reclaim the space.`)
      onDeleted()
    }
  }

  return (
    <div className="card stack-sm adm-danger">
      <h3>Danger zone: delete this church</h3>
      <p className="muted">
        Deletes the church and everything stored in the database for it: people, sites, TVs, playlists, songs, decks and plans. This cannot be undone.
        Uploaded media files are <b>not</b> removed automatically; they stay in the "media" storage bucket under the folder <code>{org.id}/</code> and must be cleaned up by hand.
      </p>
      <div className="row wrap-sm">
        <button className="btn" onClick={countFiles}>
          Check stored files
        </button>
        {files && <span className="muted">{files}</span>}
      </div>
      <label className="field">
        <span>Type the short name "{org.slug}" to confirm</span>
        <input value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" />
      </label>
      <div>
        <button className="btn danger" disabled={typed !== org.slug} onClick={del}>
          Delete this church
        </button>
      </div>
      <span className="muted">Last TV seen {timeAgo(org.last_seen_at)} · created {fmtWhen(org.created_at)}</span>
    </div>
  )
}
