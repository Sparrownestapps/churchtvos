import { useEffect, useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { DayPicker } from '../ScheduleRules'
import { attempt, daysLabel, locationLabel, must, shortTime, useLoad } from '../lib'
import type { KidsSeries, NamedRow, SeriesException } from '../calendarTypes'
import { RotationEditor } from './parts'
import { fmtDay } from './tz'
import '../calendar.css'

type Draft = {
  name: string
  days: number[]
  start: string
  end: string
  startDate: string
  endDate: string
  playlists: string[]
  onEnd: 'stop' | 'loop'
}

const toDraft = (s: KidsSeries): Draft => ({
  name: s.name ?? '',
  days: s.days,
  start: s.start_time.slice(0, 5),
  end: s.end_time.slice(0, 5),
  startDate: s.start_date,
  endDate: s.end_date ?? '',
  playlists: s.playlist_ids,
  onEnd: s.on_end,
})

/**
 * Lists the church's repeating Kids schedules (kids_series) with a rotation editor and the skipped / changed
 * dates (kids_series_exceptions). Used by the Calendar's "Repeating schedules" panel and the Kids Schedule page.
 */
export default function SeriesManager({
  locationIds,
  focusId,
  onChanged,
}: {
  /** Only these locations (omit for all the user can see). */
  locationIds?: string[]
  focusId?: string
  onChanged?: () => void
}) {
  const { org, locations, sites, canEditContent } = useApp()
  const [editing, setEditing] = useState<string | null>(focusId ?? null)
  const [draft, setDraft] = useState<Draft | null>(null)

  const { data, reload } = useLoad(async () => {
    const [series, playlists] = await Promise.all([
      supabase.from('kids_series').select('*').eq('organization_id', org.id).order('start_date'),
      supabase.from('playlists').select('id, name, site_id').eq('organization_id', org.id).order('name'),
    ])
    const list = must(series) as KidsSeries[]
    const ex = list.length
      ? must(await supabase.from('kids_series_exceptions').select('*').in('series_id', list.map((s) => s.id)).order('on_date'))
      : []
    return { series: list, playlists: must(playlists) as NamedRow[], exceptions: ex as SeriesException[] }
  })

  const changed = () => {
    reload()
    onChanged?.()
  }
  const startEdit = (s: KidsSeries) => {
    setEditing(s.id)
    setDraft(toDraft(s))
  }
  // Open the focused series straight into its editor once the data is here.
  useEffect(() => {
    const s = data?.series.find((x) => x.id === focusId)
    if (s && editing === s.id && !draft) setDraft(toDraft(s))
  }, [data, focusId, editing, draft])

  if (!data) return <p className="muted">Loading…</p>
  const siteOf = (loc: string) => locations.find((l) => l.id === loc)?.site_id ?? null
  const list = data.series.filter((s) => (!locationIds || locationIds.includes(s.location_id)) && locations.some((l) => l.id === s.location_id))
  const nameOf = (id: string | null) => data.playlists.find((p) => p.id === id)?.name ?? '—'

  async function save(s: KidsSeries) {
    if (!draft) return
    if (draft.days.length === 0) return alert('Choose at least one day.')
    if (draft.end <= draft.start) return alert('The end time must be after the start time.')
    if (draft.playlists.some((p) => !p)) return alert('Choose a playlist for every week.')
    if (draft.endDate && draft.endDate < draft.startDate) return alert('The end date must not be before the start date.')
    const row = {
      name: draft.name.trim() || null,
      days: draft.days,
      start_time: draft.start,
      end_time: draft.end,
      start_date: draft.startDate,
      end_date: draft.endDate || null,
      playlist_ids: draft.playlists,
      on_end: draft.onEnd,
    }
    if (await attempt(async () => must(await supabase.from('kids_series').update(row).eq('id', s.id)))) {
      setEditing(null)
      setDraft(null)
      changed()
    }
  }

  async function remove(s: KidsSeries) {
    if (!confirm('Delete this repeating schedule and all its dates? Nothing will play from it any more.')) return
    if (await attempt(async () => must(await supabase.from('kids_series').delete().eq('id', s.id)))) {
      setEditing(null)
      setDraft(null)
      changed()
    }
  }

  return (
    <div className="stack-sm">
      {list.length === 0 && <p className="muted">No repeating schedules yet. Drag on the calendar and choose "Every week" to make one.</p>}
      {list.map((s) => {
        const canEdit = canEditContent('kids', siteOf(s.location_id))
        const open = editing === s.id
        const ex = data.exceptions.filter((e) => e.series_id === s.id)
        return (
          <div key={s.id} className={`cal-series ${open ? 'open' : ''}`}>
            <div className="row spread">
              <span>
                <b>{s.name || 'Repeating schedule'}</b>
                <span className="muted"> · {locationLabel(locations.find((l) => l.id === s.location_id), sites)}</span>
                <br />
                {daysLabel(s.days)} · {shortTime(s.start_time)}-{shortTime(s.end_time)}
                <span className="muted">
                  {' '}
                  · from {fmtDay(s.start_date)}
                  {s.end_date ? ` to ${fmtDay(s.end_date)}` : ', no end date'}
                </span>
              </span>
              {canEdit ? (
                <span className="row">
                  <button className="link" onClick={() => (open ? (setEditing(null), setDraft(null)) : startEdit(s))}>
                    {open ? 'Close' : 'Edit'}
                  </button>
                  <button className="link danger" onClick={() => remove(s)}>
                    Delete
                  </button>
                </span>
              ) : (
                <span className="muted" title="You can't edit Kids content for this site">
                  🔒
                </span>
              )}
            </div>
            <p className="muted">
              {s.playlist_ids.map((p, i) => `Week ${i + 1}: ${nameOf(p)}`).join(' → ')}
              {s.playlist_ids.length > 1 && (s.on_end === 'loop' ? ', then repeats' : ', then stops')}
            </p>

            {open && draft && canEdit && (
              <div className="stack-sm rule-form">
                <label className="field">
                  <span>Name (optional)</span>
                  <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Fall curriculum" />
                </label>
                <DayPicker value={draft.days} onChange={(days) => setDraft({ ...draft, days })} />
                <div className="row wrap">
                  <label className="field">
                    <span>From</span>
                    <input type="time" value={draft.start} onChange={(e) => setDraft({ ...draft, start: e.target.value })} />
                  </label>
                  <label className="field">
                    <span>Until</span>
                    <input type="time" value={draft.end} onChange={(e) => setDraft({ ...draft, end: e.target.value })} />
                  </label>
                  <label className="field">
                    <span>Starts on</span>
                    <input type="date" value={draft.startDate} onChange={(e) => setDraft({ ...draft, startDate: e.target.value })} />
                  </label>
                  <label className="field">
                    <span>Ends on (optional)</span>
                    <input type="date" value={draft.endDate} onChange={(e) => setDraft({ ...draft, endDate: e.target.value })} />
                  </label>
                </div>
                <span className="field-label">Rotation</span>
                <RotationEditor
                  value={draft.playlists}
                  onChange={(playlists) => setDraft({ ...draft, playlists })}
                  playlists={data.playlists}
                  onEnd={draft.onEnd}
                  onEndChange={(onEnd) => setDraft({ ...draft, onEnd })}
                />
                <p className="muted">
                  Week numbers count only dates that actually happen: a skipped date doesn't use up a week, so the rotation waits.
                  Times are in the site's time zone.
                </p>
                <div className="row">
                  <button className="btn primary" onClick={() => save(s)}>
                    Save series
                  </button>
                  <button className="btn" onClick={() => (setEditing(null), setDraft(null))}>
                    Cancel
                  </button>
                </div>
              </div>
            )}

            {(ex.length > 0 || (open && canEdit)) && (
              <Exceptions series={s} exceptions={ex} playlists={data.playlists} canEdit={canEdit} nameOf={nameOf} onChanged={changed} showAdd={open} />
            )}
          </div>
        )
      })}
    </div>
  )
}

function Exceptions({
  series,
  exceptions,
  playlists,
  canEdit,
  nameOf,
  onChanged,
  showAdd,
}: {
  series: KidsSeries
  exceptions: SeriesException[]
  playlists: NamedRow[]
  canEdit: boolean
  nameOf: (id: string | null) => string
  onChanged: () => void
  showAdd: boolean
}) {
  const [date, setDate] = useState('')
  const [action, setAction] = useState<'skip' | 'playlist'>('skip')
  const [playlist, setPlaylist] = useState('')

  async function add() {
    if (!date) return alert('Choose a date.')
    if (action === 'playlist' && !playlist) return alert('Choose a playlist.')
    const row = { series_id: series.id, on_date: date, action, playlist_id: action === 'playlist' ? playlist : null }
    if (await attempt(async () => must(await supabase.from('kids_series_exceptions').upsert(row, { onConflict: 'series_id,on_date' })))) {
      setDate('')
      onChanged()
    }
  }
  async function remove(e: SeriesException) {
    if (await attempt(async () => must(await supabase.from('kids_series_exceptions').delete().eq('series_id', e.series_id).eq('on_date', e.on_date)))) onChanged()
  }

  return (
    <div className="stack-sm cal-exceptions">
      {exceptions.length > 0 && <span className="field-label">Skipped and changed dates</span>}
      {exceptions.map((e) => (
        <div key={e.on_date} className="row spread list-row">
          <span>
            {fmtDay(e.on_date)}: {e.action === 'skip' ? 'skipped' : `plays ${nameOf(e.playlist_id)}`}
          </span>
          {canEdit && (
            <button className="link danger" onClick={() => remove(e)}>
              Remove
            </button>
          )}
        </div>
      ))}
      {showAdd && canEdit && (
        <div className="row wrap">
          <label className="field">
            <span>Date</span>
            <input type="date" value={date} onChange={(e) => setDate(e.target.value)} />
          </label>
          <label className="field">
            <span>On that date</span>
            <select value={action} onChange={(e) => setAction(e.target.value as 'skip' | 'playlist')}>
              <option value="skip">Skip (nothing plays)</option>
              <option value="playlist">Play a different playlist</option>
            </select>
          </label>
          {action === 'playlist' && (
            <label className="field grow">
              <span>Playlist</span>
              <select value={playlist} onChange={(e) => setPlaylist(e.target.value)}>
                <option value="">Choose…</option>
                {playlists.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </label>
          )}
          <button className="btn align-end" onClick={add}>
            Add
          </button>
        </div>
      )}
    </div>
  )
}
