import { useEffect, useState, type FormEvent } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Orientation, Screen, ScreenGroup, ScreenModule, ScreenSchedule, SignagePlaylist } from '../types'
import { MODULE_NAME, attempt, locationLabel, must, summarizeRules, timeAgo, useLoad } from '../lib'
import { LocationOptions } from '../ui'
import ScheduleRules from '../ScheduleRules'

const ORIENTATION: Record<Orientation, string> = {
  landscape: 'Landscape',
  portrait: 'Portrait',
  portrait_flipped: 'Portrait (flipped)',
}

const isOnline = (s: Screen) => !!s.last_seen_at && Date.now() - new Date(s.last_seen_at).getTime() < 90_000

export default function ScreensPage() {
  const { org, isAdmin, hasModule } = useApp()
  const [tab, setTab] = useState<'screens' | 'groups'>('screens')

  const { data, reload } = useLoad(async () => {
    const [screens, groups, schedules, playlists, limit] = await Promise.all([
      supabase.from('screens').select('*').eq('organization_id', org.id).order('created_at'),
      supabase.from('screen_groups').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('screen_schedules').select('*').eq('organization_id', org.id),
      hasModule('signage')
        ? supabase.from('signage_playlists').select('id, name').eq('organization_id', org.id).order('name')
        : Promise.resolve({ data: [], error: null }),
      supabase.rpc('tv_limit', { p_org: org.id }),
    ])
    return {
      screens: must(screens) as Screen[],
      groups: must(groups) as ScreenGroup[],
      schedules: must(schedules) as ScreenSchedule[],
      playlists: must(playlists) as Pick<SignagePlaylist, 'id' | 'name'>[],
      limit: typeof limit.data === 'number' ? limit.data : null,
    }
  })

  // Keep the online/offline dots fresh.
  useEffect(() => {
    const timer = setInterval(reload, 15_000)
    return () => clearInterval(timer)
  }, [reload])

  if (!data) return null

  return (
    <div className="stack">
      <div className="segmented">
        <button className={tab === 'screens' ? 'on' : ''} onClick={() => setTab('screens')}>
          Screens
        </button>
        <button className={tab === 'groups' ? 'on' : ''} onClick={() => setTab('groups')}>
          Groups
        </button>
      </div>
      {tab === 'screens' ? (
        <ScreensTab data={data} reload={reload} isAdmin={isAdmin} />
      ) : (
        <GroupsTab data={data} reload={reload} isAdmin={isAdmin} />
      )}
    </div>
  )
}

type Data = {
  screens: Screen[]
  groups: ScreenGroup[]
  schedules: ScreenSchedule[]
  playlists: Pick<SignagePlaylist, 'id' | 'name'>[]
  limit: number | null
}
type TabProps = { data: Data; reload: () => void; isAdmin: boolean }

function ScreensTab({ data, reload, isAdmin }: TabProps) {
  const { sites, locations, mySites } = useApp()
  const [code, setCode] = useState('')
  const [locationId, setLocationId] = useState('')
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [openId, setOpenId] = useState<string | null>(null)

  async function pair(e: FormEvent) {
    e.preventDefault()
    setError(null)
    setMessage(null)
    const { error } = await supabase.rpc('claim_screen', {
      p_code: code.replace(/\s/g, ''),
      p_location_id: locationId,
      p_name: name.trim() || null,
    })
    if (error) return setError(error.message)
    setMessage(`Paired with ${locationLabel(locations.find((l) => l.id === locationId), sites)}. The TV will update in a few seconds.`)
    setCode('')
    setName('')
    reload()
  }

  return (
    <>
      {isAdmin && (
        <form className="card stack-sm" onSubmit={pair}>
          <h3>Pair a TV</h3>
          <p className="muted">
            Open the Church TV OS app on the TV. It shows a 6-character code; enter it here and choose where the TV is.
            New TV?{' '}
            <a href="/install.html" target="_blank" rel="noreferrer">
              Setup instructions
            </a>
          </p>
          <div className="row wrap">
            <label className="field">
              <span>Code on the TV</span>
              <input
                className="code-input"
                value={code}
                maxLength={7}
                onChange={(e) => setCode(e.target.value.toUpperCase())}
                placeholder="ABC 123"
                autoCapitalize="characters"
                autoComplete="off"
                required
              />
            </label>
            <label className="field grow">
              <span>Location</span>
              <select value={locationId} onChange={(e) => setLocationId(e.target.value)} required>
                <option value="">Choose…</option>
                <LocationOptions />
              </select>
            </label>
            <label className="field grow">
              <span>Name (optional)</span>
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Lobby left" />
            </label>
            <button className="btn primary align-end">Pair TV</button>
          </div>
          {mySites.length > 0 && locations.length === 0 && <p className="muted">Add a location under Sites & Locations first.</p>}
          {error && <p className="error">{error}</p>}
          {message && <p className="notice">{message}</p>}
        </form>
      )}

      <p className="muted">
        {data.screens.length} screen{data.screens.length === 1 ? '' : 's'}
        {data.limit !== null && ` of ${data.limit} allowed on your plan`}
      </p>
      {data.screens.length === 0 && <p className="muted">No screens paired yet.</p>}
      {data.screens.map((s) => (
        <ScreenCard
          key={s.id}
          screen={s}
          data={data}
          isAdmin={isAdmin}
          open={openId === s.id}
          onToggle={() => setOpenId(openId === s.id ? null : s.id)}
          reload={reload}
        />
      ))}
    </>
  )
}

function ScreenCard({
  screen: s,
  data,
  isAdmin,
  open,
  onToggle,
  reload,
}: {
  screen: Screen
  data: Data
  isAdmin: boolean
  open: boolean
  onToggle: () => void
  reload: () => void
}) {
  const { sites, locations, modules } = useApp()
  const online = isOnline(s)
  const group = data.groups.find((g) => g.id === s.group_id)
  const own = data.schedules.filter((r) => r.screen_id === s.id)
  const inherited = data.schedules.filter((r) => s.group_id && r.group_id === s.group_id)
  const [form, setForm] = useState({
    name: s.name ?? '',
    location_id: s.location_id ?? '',
    orientation: s.orientation,
    default_module: s.default_module,
    group_id: s.group_id ?? '',
    signage_default_playlist_id: s.signage_default_playlist_id ?? '',
  })
  const set = <K extends keyof typeof form>(k: K, v: (typeof form)[K]) => setForm((f) => ({ ...f, [k]: v }))

  async function save() {
    const ok = await attempt(async () =>
      must(
        await supabase
          .from('screens')
          .update({
            name: form.name.trim() || null,
            location_id: form.location_id || null,
            orientation: form.orientation,
            default_module: form.default_module,
            group_id: form.group_id || null,
            signage_default_playlist_id: form.signage_default_playlist_id || null,
          })
          .eq('id', s.id),
      ),
    )
    if (ok) reload()
  }

  async function unpair() {
    if (!confirm(`Remove ${s.name || 'this TV'}? The TV will forget this church and show a new pairing code.`)) return
    if (await attempt(async () => must(await supabase.rpc('release_screen', { p_screen_id: s.id })))) reload()
  }

  return (
    <div className="card stack-sm">
      <div className="row spread wrap-sm">
        <div>
          <h3>
            <span className={`dot ${online ? 'on' : ''}`} /> {s.name || `Screen ${s.id.slice(0, 6)}`}
          </h3>
          <span className="muted">
            {online ? 'Online' : 'Offline'} · seen {timeAgo(s.last_seen_at)}
          </span>
        </div>
        <button className="btn" onClick={onToggle}>
          {open ? 'Close' : isAdmin ? 'Edit & schedule' : 'Details'}
        </button>
      </div>
      <div className="facts">
        <span>
          <b>Location</b> {locationLabel(locations.find((l) => l.id === s.location_id), sites)}
        </span>
        <span>
          <b>Orientation</b> {ORIENTATION[s.orientation]}
        </span>
        <span>
          <b>Default</b> {MODULE_NAME[s.default_module]}
        </span>
        <span>
          <b>Group</b> {group?.name ?? 'None'}
        </span>
        <span>
          <b>App</b> {s.app_version ? `v${s.app_version}` : '—'}
          {s.model ? ` · ${s.model}` : ''}
        </span>
      </div>
      {s.orientation !== 'landscape' && (
        <p className="note">
          Portrait screen: use portrait media (1080 x 1920). YouTube items do not rotate on portrait screens.
        </p>
      )}
      <p className="muted">
        Schedule: {summarizeRules([...inherited, ...own], s.default_module)}
        {inherited.length > 0 && ' (includes group rules)'}
      </p>

      {open && (
        <div className="stack-sm panel">
          {isAdmin && (
            <>
              <div className="row wrap">
                <label className="field grow">
                  <span>Name</span>
                  <input value={form.name} onChange={(e) => set('name', e.target.value)} />
                </label>
                <label className="field grow">
                  <span>Location</span>
                  <select value={form.location_id} onChange={(e) => set('location_id', e.target.value)}>
                    <LocationOptions />
                  </select>
                </label>
              </div>
              <div className="row wrap">
                <label className="field">
                  <span>Orientation</span>
                  <select value={form.orientation} onChange={(e) => set('orientation', e.target.value as Orientation)}>
                    {(Object.keys(ORIENTATION) as Orientation[]).map((o) => (
                      <option key={o} value={o}>
                        {ORIENTATION[o]}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field">
                  <span>Default module</span>
                  <select value={form.default_module} onChange={(e) => set('default_module', e.target.value as ScreenModule)}>
                    {modules.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.name}
                      </option>
                    ))}
                    <option value="off">Off (black screen)</option>
                  </select>
                </label>
                <label className="field">
                  <span>Group</span>
                  <select value={form.group_id} onChange={(e) => set('group_id', e.target.value)}>
                    <option value="">None</option>
                    {data.groups.map((g) => (
                      <option key={g.id} value={g.id}>
                        {g.name}
                      </option>
                    ))}
                  </select>
                </label>
                <label className="field grow">
                  <span>Signage default playlist</span>
                  <select
                    value={form.signage_default_playlist_id}
                    onChange={(e) => set('signage_default_playlist_id', e.target.value)}
                  >
                    <option value="">None (black screen)</option>
                    {data.playlists.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              <div className="row">
                <button className="btn primary" onClick={save}>
                  Save changes
                </button>
                <button className="btn danger" onClick={unpair}>
                  Remove / unpair
                </button>
              </div>
            </>
          )}
          <h3>Module schedule</h3>
          {inherited.length > 0 && <p className="muted">Also applies from its group: {summarizeRules(inherited)}</p>}
          <ScheduleRules kind="module" rules={own} target={{ screen_id: s.id }} canEdit={isAdmin} onChanged={reload} />
        </div>
      )}
    </div>
  )
}

function GroupsTab({ data, reload, isAdmin }: TabProps) {
  const { org } = useApp()
  const [name, setName] = useState('')
  const [openId, setOpenId] = useState<string | null>(null)

  async function add() {
    if (!name.trim()) return
    if (await attempt(async () => must(await supabase.from('screen_groups').insert({ organization_id: org.id, name: name.trim() })))) {
      setName('')
      reload()
    }
  }

  async function rename(g: ScreenGroup) {
    const next = prompt('Rename group', g.name)?.trim()
    if (next && next !== g.name && (await attempt(async () => must(await supabase.from('screen_groups').update({ name: next }).eq('id', g.id))))) reload()
  }

  async function remove(g: ScreenGroup) {
    if (!confirm(`Delete the "${g.name}" group? Its screens stay, but the group's schedules and slots are deleted.`)) return
    if (await attempt(async () => must(await supabase.from('screen_groups').delete().eq('id', g.id)))) reload()
  }

  return (
    <>
      {isAdmin && (
        <div className="card row">
          <input
            className="grow"
            placeholder="New group name, e.g. Lobby screens"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && add()}
          />
          <button className="btn" onClick={add}>
            Add group
          </button>
        </div>
      )}
      {data.groups.length === 0 && <p className="muted">No groups yet. Groups let several screens share a schedule.</p>}
      {data.groups.map((g) => {
        const rules = data.schedules.filter((r) => r.group_id === g.id)
        const members = data.screens.filter((s) => s.group_id === g.id)
        return (
          <div key={g.id} className="card stack-sm">
            <div className="row spread wrap-sm">
              <div>
                <h3>{g.name}</h3>
                <span className="muted">
                  {members.length} screen{members.length === 1 ? '' : 's'}
                  {members.length > 0 && `: ${members.map((s) => s.name || s.id.slice(0, 6)).join(', ')}`}
                </span>
              </div>
              <div className="row">
                <button className="btn" onClick={() => setOpenId(openId === g.id ? null : g.id)}>
                  {openId === g.id ? 'Close' : 'Schedule'}
                </button>
                {isAdmin && (
                  <>
                    <button className="btn" onClick={() => rename(g)}>
                      Rename
                    </button>
                    <button className="btn danger" onClick={() => remove(g)}>
                      Delete
                    </button>
                  </>
                )}
              </div>
            </div>
            <p className="muted">Schedule: {summarizeRules(rules)}</p>
            {openId === g.id && (
              <div className="panel">
                <ScheduleRules kind="module" rules={rules} target={{ group_id: g.id }} canEdit={isAdmin} onChanged={reload} />
              </div>
            )}
          </div>
        )
      })}
    </>
  )
}
