import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { DayPicker } from '../ScheduleRules'
import { MODULE_NAME, attempt, daysLabel, must } from '../lib'
import type { Block, Domain, NamedRow, PanelState, Prefill, ResolvedTarget } from '../calendarTypes'
import { DOMAINS, exceptionRow, locationRuns } from './domain'
import type { Screen, ScreenGroup, ScreenSchedule, ScreenModule, SignageSlot } from '../types'
import { RotationEditor } from './parts'
import { DAY_NAMES, addDays, fmtClock, fmtDay, fromWall, hm, safeTz, toWall, wallOf, weekStartOf, ymd } from './tz'
import '../calendar.css'

export type CalCtx = {
  tz: string
  target: ResolvedTarget
  screens: Screen[]
  groups: ScreenGroup[]
  kidsPlaylists: NamedRow[]
  decks: NamedRow[]
  signagePlaylists: NamedRow[]
  slots: SignageSlot[]
  rules: ScreenSchedule[]
  reload: () => void
  openPanel: (p: PanelState | null) => void
}

const screenName = (s: Screen) => s.name || `Screen ${s.id.slice(0, 6)}`
const toRuleEnd = (t: string) => (t >= '23:59' ? '23:59:59' : t.length === 5 ? `${t}:00` : t)
const dowOf = (date: string) => wallOf(date).getUTCDay()

/** Do two weekly rules overlap (shared day and overlapping times)? */
function overlaps(a: { days: number[]; start_time: string; end_time: string }, b: { days: number[]; start_time: string; end_time: string }) {
  return a.days.some((d) => b.days.includes(d)) && a.start_time < b.end_time && b.start_time < a.end_time
}

// ───────────────────────── Create ─────────────────────────

export function CreatePanel({ ctx, state, onClose }: { ctx: CalCtx; state: Extract<PanelState, { mode: 'create' }>; onClose: () => void }) {
  const { org, isAdmin, canEditContent, locations, sites, modules, moduleName, hasModule } = useApp()
  const { target, screens, groups, kidsPlaylists, decks, signagePlaylists } = ctx
  const pf: Prefill = state.prefill ?? {}

  const siteTz = (locId: string) => safeTz(sites.find((s) => s.id === locations.find((l) => l.id === locId)?.site_id)?.timezone)
  const slidesListed = hasModule('slides') && modules.some((m) => m.id === 'slides')
  const kidsLocs = locations.filter((l) => l.modules.includes('kids') && canEditContent('kids', l.site_id))
  const slidesLocs = slidesListed ? locations.filter((l) => locationRuns('slides', l) && canEditContent('slides', l.site_id)) : []
  type Type = 'kids' | 'slides' | 'signage' | 'module'
  const available: Type[] = [
    ...(canEditContent('signage', null) ? (['signage'] as const) : []),
    ...(kidsLocs.length ? (['kids'] as const) : []),
    ...(slidesLocs.length ? (['slides'] as const) : []),
    ...(isAdmin ? (['module'] as const) : []),
  ]
  const firstType: Type | undefined = target.kind === 'location' && (available.includes('kids') || available.includes('slides')) ? (available.includes('kids') ? 'kids' : 'slides') : available[0]
  const dated = (t: Type): t is Domain => t === 'kids' || t === 'slides'

  const defaultKeys = (t: string): string[] => {
    if (t === 'kids' || t === 'slides') return [target.kind === 'screen' ? `screen:${target.id}` : target.kind === 'group' ? `group:${target.id}` : `loc:${target.id}`]
    if (target.kind === 'location') return screens.filter((s) => s.location_id === target.id).map((s) => `screen:${s.id}`)
    return [`${target.kind}:${target.id}`]
  }

  const [type, setTypeState] = useState<Type>(pf.type ?? firstType ?? 'kids')
  const [keys, setKeys] = useState<string[]>(pf.keys ?? defaultKeys(pf.type ?? firstType ?? 'kids'))
  const [playlistId, setPlaylistId] = useState(pf.playlistId ?? '')
  const [moduleId, setModuleId] = useState<ScreenModule>((pf.module as ScreenModule) ?? 'kids')
  const [date, setDate] = useState(state.date)
  const [start, setStart] = useState(state.start)
  const [end, setEnd] = useState(state.end)
  const [repeat, setRepeat] = useState<'once' | 'weekly'>(dated(type) ? 'once' : 'weekly')
  const [days, setDays] = useState<number[]>(pf.days ?? [dowOf(state.date)])
  const [endDate, setEndDate] = useState('')
  const [extra, setExtra] = useState<string[]>([])
  const [onEnd, setOnEnd] = useState<'stop' | 'loop'>('loop')
  const [name, setName] = useState('')
  const [higher, setHigher] = useState(false)
  const [busy, setBusy] = useState(false)

  if (available.length === 0) {
    return <p className="muted">You have view-only access, so you can't add anything to the calendar.</p>
  }

  function setType(t: Type) {
    setTypeState(t)
    setKeys(defaultKeys(t))
    setPlaylistId('')
    setExtra([])
    setRepeat(dated(t) ? 'once' : 'weekly')
  }

  const toggleKey = (k: string) => setKeys((ks) => (ks.includes(k) ? ks.filter((x) => x !== k) : [...ks, k]))

  // Kids playlists and Slides decks play per location, so every chosen screen / group resolves to its location(s), de-duplicated.
  const locIds = new Set<string>()
  for (const k of keys) {
    const [kind, id] = k.split(':')
    if (kind === 'loc') locIds.add(id)
    if (kind === 'screen') {
      const l = screens.find((s) => s.id === id)?.location_id
      if (l) locIds.add(l)
    }
    if (kind === 'group') for (const s of screens) if (s.group_id === id && s.location_id) locIds.add(s.location_id)
  }
  const dom: Domain | null = dated(type) ? type : null
  const dn = DOMAINS[dom ?? 'kids']
  const playlist = (dom === 'slides' ? decks : kidsPlaylists).find((p) => p.id === playlistId)
  const okLocs: string[] = []
  const skipped: string[] = []
  for (const id of locIds) {
    const l = locations.find((x) => x.id === id)
    if (!l) continue
    const why = !locationRuns(dom ?? 'kids', l)
      ? dom === 'slides'
        ? 'not tagged for Slides or Kids'
        : 'not a Kids room'
      : !canEditContent(dom ?? 'kids', l.site_id)
        ? `you can't edit ${dn.label} here`
        : playlist?.site_id && playlist.site_id !== l.site_id
          ? `the ${dn.item} is for another site`
          : ''
    if (why) skipped.push(`${l.name} (${why})`)
    else okLocs.push(id)
  }
  const locName = (id: string) => locations.find((l) => l.id === id)?.name ?? '—'

  // Signage / module rules: a selected group covers its screens, so those screens don't get their own row.
  const groupKeys = keys.filter((k) => k.startsWith('group:')).map((k) => k.slice(6))
  const screenTargets = keys
    .filter((k) => k.startsWith('screen:'))
    .map((k) => k.slice(7))
    .filter((id) => !groupKeys.includes(screens.find((s) => s.id === id)?.group_id ?? ''))
  const ruleTargets: ({ screen_id: string } | { group_id: string })[] = [...groupKeys.map((group_id) => ({ group_id })), ...screenTargets.map((screen_id) => ({ screen_id }))]

  async function submit() {
    if (!date) return alert('Choose a date.')
    if (end <= start) return alert('The end time must be after the start time.')
    if (type !== 'module' && !playlistId) return alert(`Choose a ${dn.item}.`)
    const weeklyDays = days
    if (weeklyDays.length === 0) return alert('Choose at least one day.')
    if (endDate && endDate < date) return alert('The end date must not be before the start date.')

    setBusy(true)
    const ok = await attempt(async () => {
      if (dom) {
        if (okLocs.length === 0) throw new Error(`Choose at least one ${dom === 'slides' ? 'Slides' : 'Kids'} location you can edit.`)
        if (repeat === 'once') {
          const monday = weekStartOf(wallOf(date))
          const dates = weeklyDays.map((d) => ymd(addDays(monday, (d + 6) % 7)))
          const rows = okLocs.flatMap((location_id) =>
            dates.map((dt) => ({
              organization_id: org.id,
              location_id,
              [dn.schedCol]: playlistId,
              starts_at: fromWall(wallOf(dt, start), siteTz(location_id)).toISOString(),
              ends_at: fromWall(wallOf(dt, end), siteTz(location_id)).toISOString(),
            })),
          )
          must(await supabase.from(dn.schedTable).insert(rows))
        } else {
          const rotation = [playlistId, ...extra]
          if (rotation.some((p) => !p)) throw new Error(`Choose a ${dn.item} for every week of the rotation.`)
          const rows = okLocs.map((location_id) => ({
            organization_id: org.id,
            location_id,
            name: name.trim() || null,
            days: weeklyDays,
            start_time: start,
            end_time: end,
            start_date: date,
            end_date: endDate || null,
            [dn.seriesCol]: rotation,
            on_end: onEnd,
          }))
          must(await supabase.from(dn.seriesTable).insert(rows))
        }
        return
      }

      if (ruleTargets.length === 0) throw new Error('Choose at least one screen or group.')
      const table = type === 'signage' ? 'signage_slots' : 'screen_schedules'
      const pool: { screen_id: string | null; group_id: string | null; days: number[]; start_time: string; end_time: string; priority: number }[] =
        type === 'signage' ? ctx.slots : ctx.rules
      const candidate = { days: weeklyDays, start_time: start, end_time: toRuleEnd(end) }
      const rows = ruleTargets.map((t) => {
        const sid = 'screen_id' in t ? t.screen_id : null
        const gid = 'group_id' in t ? t.group_id : null
        const groupOfScreen = sid ? screens.find((s) => s.id === sid)?.group_id : null
        const rivals = pool.filter(
          (r) => (sid ? r.screen_id === sid || (!!groupOfScreen && r.group_id === groupOfScreen) : r.group_id === gid) && overlaps(r, candidate),
        )
        const priority = higher && rivals.length ? Math.max(...rivals.map((r) => r.priority)) + 1 : 0
        return {
          organization_id: org.id,
          ...t,
          days: weeklyDays,
          start_time: start,
          end_time: toRuleEnd(end),
          priority,
          ...(type === 'signage' ? { playlist_id: playlistId } : { module: moduleId }),
        }
      })
      must(await supabase.from(table).insert(rows))
    })
    setBusy(false)
    if (ok) {
      ctx.reload()
      onClose()
    }
  }

  const screensByLoc = (locId: string | null) => screens.filter((s) => s.location_id === locId)
  const playlistsForType = type === 'kids' ? kidsPlaylists : type === 'slides' ? decks : signagePlaylists

  return (
    <div className="stack-sm">
      <div className="segmented cal-type">
        {available.map((t) => (
          <button key={t} className={type === t ? 'on' : ''} onClick={() => setType(t)}>
            {t === 'kids' ? 'Kids playlist' : t === 'slides' ? 'Slides deck' : t === 'signage' ? 'Signage playlist' : 'Switch module'}
          </button>
        ))}
      </div>

      {type === 'module' ? (
        <label className="field">
          <span>Switch the screens to</span>
          <select value={moduleId} onChange={(e) => setModuleId(e.target.value)}>
            {modules.map((m) => (
              <option key={m.id} value={m.id}>
                {moduleName(m.id)}
              </option>
            ))}
            <option value="off">Off (black screen)</option>
          </select>
        </label>
      ) : (
        <label className="field">
          <span>{dom && repeat === 'weekly' ? `Week 1 ${dn.item}` : dom === 'slides' ? 'Deck' : 'Playlist'}</span>
          <select value={playlistId} onChange={(e) => setPlaylistId(e.target.value)}>
            <option value="">Choose…</option>
            {playlistsForType.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </label>
      )}

      <div className="row wrap">
        <label className="field">
          <span>{repeat === 'weekly' ? 'Starting' : 'Date'}</span>
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
        </label>
        <label className="field">
          <span>From</span>
          <input type="time" step={900} value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <label className="field">
          <span>Until</span>
          <input type="time" step={900} value={end} onChange={(e) => setEnd(e.target.value)} />
        </label>
      </div>

      <div className="field">
        <span>{dom ? `Where (${dn.label} ${dn.item}s play per location)` : 'Which screens'}</span>
        <div className="cal-targets">
          {groups.length > 0 && (
            <div className="room-group">
              <b>Screen groups</b>
              {groups.map((g) => (
                <label key={g.id} className="check">
                  <input type="checkbox" checked={keys.includes(`group:${g.id}`)} onChange={() => toggleKey(`group:${g.id}`)} />
                  {g.name}
                </label>
              ))}
            </div>
          )}
          {(type === 'kids' ? kidsLocs : type === 'slides' ? slidesLocs : locations.filter((l) => screensByLoc(l.id).length > 0)).map((l) => (
            <div key={l.id} className="room-group">
              {dom ? (
                <label className="check">
                  <input type="checkbox" checked={keys.includes(`loc:${l.id}`)} onChange={() => toggleKey(`loc:${l.id}`)} />
                  <b>{l.name}</b>
                  <span className="muted">{sites.find((s) => s.id === l.site_id)?.name}</span>
                </label>
              ) : (
                <b>{l.name}</b>
              )}
              {screensByLoc(l.id).map((s) => (
                <label key={s.id} className="check cal-indent">
                  <input type="checkbox" checked={keys.includes(`screen:${s.id}`)} onChange={() => toggleKey(`screen:${s.id}`)} />
                  {screenName(s)}
                </label>
              ))}
            </div>
          ))}
        </div>
        {dom ? (
          <p className="muted">
            Plays in: {okLocs.length ? okLocs.map(locName).join(', ') : 'nowhere yet'}.
            {skipped.length > 0 && <span className="notice warn"> Skipped: {skipped.join('; ')}.</span>}
          </p>
        ) : (
          <p className="muted">
            {ruleTargets.length} target{ruleTargets.length === 1 ? '' : 's'}: one rule is created for each. A group covers all its screens.
          </p>
        )}
      </div>

      <div className="field">
        <span>Repeat</span>
        {dom ? (
          <div className="segmented">
            <button className={repeat === 'once' ? 'on' : ''} onClick={() => setRepeat('once')}>
              This week only
            </button>
            <button className={repeat === 'weekly' ? 'on' : ''} onClick={() => setRepeat('weekly')}>
              Every week
            </button>
          </div>
        ) : (
          <p className="muted">
            Signage playlists and module switches repeat every week on the days you choose (there is no one-time version).
          </p>
        )}
      </div>
      <div className="field">
        <span>{repeat === 'once' ? 'Days this week' : 'Days'}</span>
        <DayPicker value={days} onChange={setDays} />
      </div>
      {repeat === 'weekly' && (
        <label className="field">
          <span>Ends on (optional){!dom ? ' — not available for this type' : ''}</span>
          <input type="date" value={endDate} disabled={!dom} onChange={(e) => setEndDate(e.target.value)} />
        </label>
      )}

      {dom && repeat === 'weekly' && (
        <>
          <label className="field">
            <span>Name (optional)</span>
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Fall curriculum" />
          </label>
          <span className="field-label">Rotation (later weeks)</span>
          <RotationEditor
            value={[playlistId, ...extra]}
            onChange={(v) => {
              setPlaylistId(v[0] ?? '')
              setExtra(v.slice(1))
            }}
            playlists={dom === 'slides' ? decks : kidsPlaylists}
            itemName={dn.item}
            onEnd={onEnd}
            onEndChange={setOnEnd}
          />
        </>
      )}

      {!dom && (
        <label className="check">
          <input type="checkbox" checked={higher} onChange={(e) => setHigher(e.target.checked)} />
          Add as higher priority than anything it overlaps
        </label>
      )}
      <p className="muted">
        {dom
          ? "Times are in each location's site time zone. A one-time block replaces any repeating one it overlaps."
          : "Times are in the screen's site time zone. When blocks overlap, the highest priority wins, then the newest."}
      </p>
      <button className="btn primary wide" disabled={busy} onClick={submit}>
        {busy ? 'Saving…' : repeat === 'weekly' ? 'Create repeating schedule' : 'Add to calendar'}
      </button>
    </div>
  )
}

// ───────────────────────── Edit ─────────────────────────

export function EditPanel({ ctx, block, onClose }: { ctx: CalCtx; block: Block; onClose: () => void }) {
  const done = () => {
    ctx.reload()
    onClose()
  }
  return (
    <div className="stack-sm">
      {!block.editable && <p className="notice warn">🔒 {block.lockReason ?? "You can't edit this."}</p>}
      {block.warn && <p className="cal-warnline">⚠ {block.warn}</p>}
      {block.kind === 'oneoff' && <OneOffEdit ctx={ctx} block={block} done={done} />}
      {block.kind === 'series' && <SeriesOccEdit ctx={ctx} block={block} done={done} />}
      {(block.kind === 'slot' || block.kind === 'module') && <RuleEdit ctx={ctx} block={block} done={done} />}
    </div>
  )
}

function OneOffEdit({ ctx, block, done }: { ctx: CalCtx; block: Extract<Block, { kind: 'oneoff' }>; done: () => void }) {
  const { locations, sites } = useApp()
  const row = block.row
  const loc = locations.find((l) => l.id === row.location_id)
  const tz = safeTz(sites.find((s) => s.id === loc?.site_id)?.timezone)
  const s0 = toWall(Date.parse(row.starts_at), tz)
  const e0 = row.ends_at ? toWall(Date.parse(row.ends_at), tz) : null
  const dn = DOMAINS[block.domain]
  const itemList = block.domain === 'slides' ? ctx.decks : ctx.kidsPlaylists
  const [playlistId, setPlaylistId] = useState(row.playlist_id)
  const [date, setDate] = useState(ymd(s0))
  const [start, setStart] = useState(hm(s0))
  const [end, setEnd] = useState(e0 ? hm(e0) : '')
  const ro = !block.editable

  async function save() {
    if (end && (end <= start)) return alert('The end time must be after the start time.')
    const patch = {
      [dn.schedCol]: playlistId,
      starts_at: fromWall(wallOf(date, start), tz).toISOString(),
      ends_at: end ? fromWall(wallOf(date, end), tz).toISOString() : null,
    }
    if (await attempt(async () => must(await supabase.from(dn.schedTable).update(patch).eq('id', row.id)))) done()
  }
  async function del() {
    if (!confirm('Remove this from the schedule?')) return
    if (await attempt(async () => must(await supabase.from(dn.schedTable).delete().eq('id', row.id)))) done()
  }

  return (
    <>
      <p className="muted">
        {dn.label} one-time schedule · {loc?.name ?? 'Unknown location'}
      </p>
      <label className="field">
        <span>{block.domain === 'slides' ? 'Deck' : 'Playlist'}</span>
        <select value={playlistId} disabled={ro} onChange={(e) => setPlaylistId(e.target.value)}>
          {itemList.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
      </label>
      <div className="row wrap">
        <label className="field">
          <span>Date</span>
          <input type="date" value={date} disabled={ro} onChange={(e) => setDate(e.target.value)} />
        </label>
        <label className="field">
          <span>From</span>
          <input type="time" step={900} value={start} disabled={ro} onChange={(e) => setStart(e.target.value)} />
        </label>
        <label className="field">
          <span>Until (optional)</span>
          <input type="time" step={900} value={end} disabled={ro} onChange={(e) => setEnd(e.target.value)} />
        </label>
      </div>
      {!end && <p className="muted">No end time: it plays until the next scheduled {dn.item} starts.</p>}
      {!ro && (
        <div className="row wrap-sm">
          <button className="btn primary" onClick={save}>
            Save
          </button>
          <button
            className="btn"
            onClick={() => ctx.openPanel({ mode: 'create', date, start, end: end || hm(new Date(wallOf(date, start).getTime() + 3_600_000)), prefill: { type: block.domain, playlistId, keys: [`loc:${row.location_id}`] } })}
          >
            Duplicate…
          </button>
          <button className="btn danger" onClick={del}>
            Delete
          </button>
        </div>
      )}
    </>
  )
}

function SeriesOccEdit({ ctx, block, done }: { ctx: CalCtx; block: Extract<Block, { kind: 'series' }>; done: () => void }) {
  const { occ, series } = block
  const [playlistId, setPlaylistId] = useState(occ.playlist_id)
  const ro = !block.editable
  const dn = DOMAINS[block.domain]
  const itemList = block.domain === 'slides' ? ctx.decks : ctx.kidsPlaylists
  const nameOf = (id: string) => itemList.find((p) => p.id === id)?.name ?? '—'

  const upsert = (action: 'skip' | 'playlist') =>
    attempt(async () =>
      must(await supabase.from(dn.excTable).upsert(exceptionRow(block.domain, series.id, occ.on_date, action, playlistId), { onConflict: 'series_id,on_date' })),
    )
  async function clear() {
    if (await attempt(async () => must(await supabase.from(dn.excTable).delete().eq('series_id', series.id).eq('on_date', occ.on_date)))) done()
  }
  async function deleteSeries() {
    if (!confirm('Delete the whole repeating schedule, including every other date? This cannot be undone.')) return
    if (await attempt(async () => must(await supabase.from(dn.seriesTable).delete().eq('id', series.id)))) done()
  }

  return (
    <>
      <p>
        <b>
          {occ.is_override ? 'Changed date' : `Week ${occ.occurrence_no}`}: {nameOf(occ.playlist_id)}
        </b>
        <br />
        <span className="muted">
          {fmtDay(occ.on_date)} · {fmtClock(series.start_time)}-{fmtClock(series.end_time)} · {series.name || 'Repeating schedule'}
        </span>
      </p>
      <span className="field-label">This date only</span>
      {ro ? (
        <p className="muted">View only.</p>
      ) : (
        <div className="stack-sm cal-section">
          <div className="row wrap">
            <label className="field grow">
              <span>Play a different {dn.item}</span>
              <select value={playlistId} onChange={(e) => setPlaylistId(e.target.value)}>
                {itemList.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </label>
            <button
              className="btn align-end"
              disabled={playlistId === occ.playlist_id}
              onClick={async () => (await upsert('playlist')) && done()}
            >
              Change this date
            </button>
          </div>
          <div className="row wrap-sm">
            <button className="btn" onClick={async () => (await upsert('skip')) && done()}>
              Skip this date
            </button>
            {occ.is_override && (
              <button className="btn" onClick={clear}>
                Back to the rotation
              </button>
            )}
          </div>
          <p className="muted">Skipping makes the rotation wait: the skipped week's {dn.item} moves to the next date. A changed date still uses up its week.</p>
        </div>
      )}
      <span className="field-label">The whole series</span>
      <p className="muted">
        {daysLabel(series.days)} · {series.playlist_ids.map((p, i) => `Week ${i + 1}: ${nameOf(p)}`).join(', ')}
      </p>
      <div className="row wrap-sm">
        <button className="btn" onClick={() => ctx.openPanel({ mode: 'series', focusId: series.id })}>
          {ro ? 'View series' : 'Edit series…'}
        </button>
        {!ro && (
          <button className="btn danger" onClick={deleteSeries}>
            Delete series
          </button>
        )}
      </div>
    </>
  )
}

function RuleEdit({ ctx, block, done }: { ctx: CalCtx; block: Extract<Block, { kind: 'slot' | 'module' }>; done: () => void }) {
  const row = block.row
  const isSlot = block.kind === 'slot'
  const table = isSlot ? 'signage_slots' : 'screen_schedules'
  const ro = !block.editable
  const [playlistId, setPlaylistId] = useState(isSlot ? (row as SignageSlot).playlist_id : '')
  const [moduleId, setModuleId] = useState<ScreenModule>(isSlot ? 'kids' : (row as ScreenSchedule).module)
  const [days, setDays] = useState(row.days)
  const [start, setStart] = useState(row.start_time.slice(0, 5))
  const [end, setEnd] = useState(row.end_time.slice(0, 5))
  const [priority, setPriority] = useState(row.priority)
  const { modules } = useApp()
  const thisDow = dowOf(block.date)
  const targetLabel = row.screen_id
    ? screenName(ctx.screens.find((s) => s.id === row.screen_id) ?? ({ id: row.screen_id, name: null } as Screen))
    : `Group: ${ctx.groups.find((g) => g.id === row.group_id)?.name ?? '—'} (all its screens)`

  const what = isSlot ? { playlist_id: playlistId } : { module: moduleId }

  async function save() {
    if (days.length === 0) return alert('Choose at least one day.')
    if (end <= start) return alert('The end time must be after the start time.')
    if (isSlot && !playlistId) return alert('Choose a playlist.')
    const patch = { ...what, days, start_time: start, end_time: toRuleEnd(end), priority }
    if (await attempt(async () => must(await supabase.from(table).update(patch).eq('id', row.id)))) done()
  }
  async function removeDay() {
    const rest = row.days.filter((d) => d !== thisDow)
    const res = rest.length
      ? supabase.from(table).update({ days: rest }).eq('id', row.id)
      : supabase.from(table).delete().eq('id', row.id)
    if (await attempt(async () => must(await res))) done()
  }
  async function del() {
    if (!confirm('Delete this rule for every day it covers?')) return
    if (await attempt(async () => must(await supabase.from(table).delete().eq('id', row.id)))) done()
  }

  return (
    <>
      <p className="muted">
        {isSlot ? 'Signage slot' : 'Module switch'} · {targetLabel}
        <br />
        Repeats every week on {daysLabel(row.days)}.
      </p>
      {isSlot ? (
        <label className="field">
          <span>Playlist</span>
          <select value={playlistId} disabled={ro} onChange={(e) => setPlaylistId(e.target.value)}>
            {ctx.signagePlaylists.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </label>
      ) : (
        <label className="field">
          <span>Run</span>
          <select value={moduleId} disabled={ro} onChange={(e) => setModuleId(e.target.value)}>
            {modules.map((m) => (
              <option key={m.id} value={m.id}>
                {m.name}
              </option>
            ))}
            <option value="off">{MODULE_NAME.off}</option>
          </select>
        </label>
      )}
      <div className="row wrap">
        <label className="field">
          <span>From</span>
          <input type="time" step={900} value={start} disabled={ro} onChange={(e) => setStart(e.target.value)} />
        </label>
        <label className="field">
          <span>Until</span>
          <input type="time" step={900} value={end} disabled={ro} onChange={(e) => setEnd(e.target.value)} />
        </label>
        <label className="field">
          <span>Priority</span>
          <input type="number" value={priority} disabled={ro} style={{ width: 80 }} onChange={(e) => setPriority(Number(e.target.value))} />
        </label>
      </div>
      {ro ? (
        <p className="muted">Days: {daysLabel(row.days)}</p>
      ) : (
        <>
          <DayPicker value={days} onChange={setDays} />
          <div className="row wrap-sm">
            <button className="btn primary" onClick={save}>
              Save rule
            </button>
            <button
              className="btn"
              onClick={() =>
                ctx.openPanel({
                  mode: 'create',
                  date: block.date,
                  start,
                  end,
                  prefill: {
                    type: isSlot ? 'signage' : 'module',
                    playlistId,
                    module: moduleId,
                    days,
                    keys: [row.screen_id ? `screen:${row.screen_id}` : `group:${row.group_id}`],
                  },
                })
              }
            >
              Duplicate…
            </button>
          </div>
          <div className="row wrap-sm">
            {row.days.length > 1 && (
              <button className="btn danger" onClick={removeDay}>
                Remove just {DAY_NAMES[thisDow]}
              </button>
            )}
            <button className="btn danger" onClick={del}>
              Delete rule{row.days.length > 1 ? ` (all ${row.days.length} days)` : ''}
            </button>
          </div>
        </>
      )}
      <p className="muted">
        This rule repeats weekly, so changes apply to every week. When rules overlap, the higher priority wins, then the newest.
      </p>
    </>
  )
}

