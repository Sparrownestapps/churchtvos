import { useState, type ReactNode } from 'react'
import '../slides.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { DayPicker } from '../ScheduleRules'
import { RotationEditor } from '../calendar/parts'
import type { DeckOccurrence, DeckSeries, DeckSeriesException } from '../slidesTypes'
import type { DeckRef } from '../slidesPages.types'
import { attempt, daysLabel, locationLabel, must, nextSundayAt, shortTime, useLoad } from '../lib'
import LocationPicker, { LocationHint, isSlidesLocation } from './LocationPicker'

type Draft = {
  name: string
  days: number[]
  start: string
  end: string
  startDate: string
  endDate: string
  decks: string[]
  onEnd: 'stop' | 'loop'
}

const ymdLocal = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

const newDraft = (): Draft => ({ name: '', days: [0], start: '08:00', end: '13:00', startDate: ymdLocal(nextSundayAt(8)), endDate: '', decks: [''], onEnd: 'loop' })

const toDraft = (s: DeckSeries): Draft => ({
  name: s.name ?? '',
  days: s.days,
  start: s.start_time.slice(0, 5),
  end: s.end_time.slice(0, 5),
  startDate: s.start_date,
  endDate: s.end_date ?? '',
  decks: s.deck_ids,
  onEnd: s.on_end,
})

/** "Sun, Nov 1" for a date string (no time zone shifting: it is a calendar date). */
const fmtDay = (date: string) => {
  const [y, m, d] = date.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' })
}

function validate(d: Draft): string | null {
  if (d.days.length === 0) return 'Choose at least one day.'
  if (!d.start || !d.end) return 'Choose a start and end time.'
  if (d.end <= d.start) return 'The end time must be after the start time.'
  if (d.decks.some((x) => !x)) return 'Choose a deck for every week.'
  if (!d.startDate) return 'Choose the first date.'
  if (d.endDate && d.endDate < d.startDate) return 'The end date must not be before the start date.'
  return null
}

const rowOf = (d: Draft) => ({
  name: d.name.trim() || null,
  days: d.days,
  start_time: d.start,
  end_time: d.end,
  start_date: d.startDate,
  end_date: d.endDate || null,
  deck_ids: d.decks,
  on_end: d.onEnd,
})

function SeriesForm({ draft, setDraft, decks, children }: { draft: Draft; setDraft: (d: Draft) => void; decks: { id: string; name: string }[]; children?: ReactNode }) {
  return (
    <div className="stack-sm rule-form">
      <label className="field">
        <span>Name (optional)</span>
        <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Sunday pre-service loop" />
      </label>
      {children}
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
      <RotationEditor value={draft.decks} onChange={(d) => setDraft({ ...draft, decks: d })} playlists={decks} onEnd={draft.onEnd} onEndChange={(onEnd) => setDraft({ ...draft, onEnd })} />
      <p className="muted">
        Week numbers count only dates that actually happen: a skipped date doesn't use up a week, so the rotation waits. Times are in the site's time zone.
      </p>
    </div>
  )
}

/**
 * Repeating deck schedules (deck_series) with a rotation of decks and the skipped / changed dates (deck_series_exceptions).
 * Same rules as the Kids repeating schedules. Upcoming dates come from the deck_series_occurrences() function.
 */
export default function DeckSeriesManager({ decks }: { decks: DeckRef[] }) {
  const { org, locations, sites, mySites, canEditContent } = useApp()
  const [editing, setEditing] = useState<string | null>(null)
  const [draft, setDraft] = useState<Draft | null>(null)
  const [creating, setCreating] = useState<Draft | null>(null)
  const [createLocs, setCreateLocs] = useState<string[]>([])

  const { data, reload } = useLoad(async () => {
    const series = must(await supabase.from('deck_series').select('*').eq('organization_id', org.id).order('start_date')) as DeckSeries[]
    const ex = series.length ? must(await supabase.from('deck_series_exceptions').select('*').in('series_id', series.map((s) => s.id)).order('on_date')) : []
    // Upcoming dates are a nicety: if the function fails the list still works.
    const from = new Date()
    const to = new Date(from.getTime() + 60 * 86_400_000)
    const occ = await supabase.rpc('deck_series_occurrences', { p_org: org.id, p_from: from.toISOString(), p_to: to.toISOString(), p_location: null })
    return { series, exceptions: ex as DeckSeriesException[], occurrences: occ.error ? [] : ((occ.data ?? []) as DeckOccurrence[]) }
  }, [org.id])

  if (!data) return <p className="muted">Loading…</p>

  const siteOf = (loc: string) => locations.find((l) => l.id === loc)?.site_id ?? null
  const tzOf = (loc: string) => sites.find((s) => s.id === siteOf(loc))?.timezone
  const list = data.series.filter((s) => locations.some((l) => l.id === s.location_id))
  const deckName = (id: string | null) => decks.find((d) => d.id === id)?.name ?? '—'
  const deckOptions = decks.map((d) => ({ id: d.id, name: d.site_id ? `${d.name} (${sites.find((s) => s.id === d.site_id)?.name ?? 'one site'} only)` : d.name }))
  const editableSites = mySites.filter((s) => canEditContent('slides', s.id))
  const offered = locations.filter((l) => isSlidesLocation(l) && editableSites.some((s) => s.id === l.site_id))

  const when = (iso: string, tz: string | undefined) => {
    const opts: Intl.DateTimeFormatOptions = { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZone: tz }
    try {
      return new Date(iso).toLocaleString(undefined, opts)
    } catch {
      return new Date(iso).toLocaleString(undefined, { ...opts, timeZone: undefined })
    }
  }

  const close = () => (setEditing(null), setDraft(null))

  async function create() {
    if (!creating) return
    const problem = validate(creating)
    if (problem) return alert(problem)
    const chosen = createLocs.filter((id) => offered.some((l) => l.id === id))
    if (chosen.length === 0) return alert('Choose at least one location.')
    const rows = chosen.map((location_id) => ({ organization_id: org.id, location_id, ...rowOf(creating) }))
    if (await attempt(async () => must(await supabase.from('deck_series').insert(rows)))) {
      setCreating(null)
      setCreateLocs([])
      reload()
    }
  }

  async function save(s: DeckSeries) {
    if (!draft) return
    const problem = validate(draft)
    if (problem) return alert(problem)
    if (await attempt(async () => must(await supabase.from('deck_series').update(rowOf(draft)).eq('id', s.id).eq('organization_id', org.id)))) {
      close()
      reload()
    }
  }

  async function remove(s: DeckSeries) {
    if (!confirm('Delete this repeating schedule and all its dates? Nothing will play from it any more.')) return
    if (await attempt(async () => must(await supabase.from('deck_series').delete().eq('id', s.id).eq('organization_id', org.id)))) {
      close()
      reload()
    }
  }

  return (
    <div className="stack-sm">
      {editableSites.length > 0 &&
        (creating ? (
          <div className="stack-sm">
            <SeriesForm draft={creating} setDraft={setCreating} decks={deckOptions}>
              <div className="field">
                <span>Locations</span>
                <LocationPicker sites={editableSites} locations={offered} value={createLocs} onChange={setCreateLocs} />
                <LocationHint offered={locations.filter(isSlidesLocation)} />
              </div>
            </SeriesForm>
            <div className="row">
              <button className="btn primary" onClick={create}>
                Create repeating schedule
              </button>
              <button className="btn" onClick={() => setCreating(null)}>
                Cancel
              </button>
            </div>
          </div>
        ) : (
          <div>
            <button className="btn" onClick={() => setCreating(newDraft())} disabled={decks.length === 0} title={decks.length === 0 ? 'Make a deck first' : undefined}>
              + New repeating schedule
            </button>
          </div>
        ))}

      {list.length === 0 && !creating && <p className="muted">No repeating schedules yet.</p>}
      {list.map((s) => {
        const canEdit = canEditContent('slides', siteOf(s.location_id))
        const open = editing === s.id
        const ex = data.exceptions.filter((e) => e.series_id === s.id)
        const occ = data.occurrences.filter((o) => o.series_id === s.id)
        const tz = tzOf(s.location_id)
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
                  <button className="link" onClick={() => (open ? close() : (setEditing(s.id), setDraft(toDraft(s))))}>
                    {open ? 'Close' : 'Edit'}
                  </button>
                  <button className="link danger" onClick={() => remove(s)}>
                    Delete
                  </button>
                </span>
              ) : (
                <span className="muted" title="You can't edit Slides content for this site">
                  🔒
                </span>
              )}
            </div>
            <p className="muted">
              {s.deck_ids.map((d, i) => `Week ${i + 1}: ${deckName(d)}`).join(' → ')}
              {s.deck_ids.length > 1 && (s.on_end === 'loop' ? ', then repeats' : ', then stops')}
            </p>

            {open && draft && canEdit && (
              <div className="stack-sm">
                <SeriesForm draft={draft} setDraft={setDraft} decks={deckOptions} />
                <div className="row">
                  <button className="btn primary" onClick={() => save(s)}>
                    Save schedule
                  </button>
                  <button className="btn" onClick={close}>
                    Cancel
                  </button>
                </div>
              </div>
            )}

            {occ.length > 0 && (
              <div className="stack-sm">
                <span className="field-label">{open ? 'Next dates' : 'Next'}</span>
                {occ.slice(0, open ? 8 : 1).map((o) => (
                  <div key={o.on_date} className="list-row">
                    {when(o.starts_at, tz)} · {deckName(o.deck_id)}
                    {o.is_override && <span className="badge">changed date</span>}
                  </div>
                ))}
              </div>
            )}

            {(ex.length > 0 || (open && canEdit)) && (
              <Exceptions series={s} exceptions={ex} decks={deckOptions} canEdit={canEdit} nameOf={deckName} onChanged={reload} showAdd={open} />
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
  decks,
  canEdit,
  nameOf,
  onChanged,
  showAdd,
}: {
  series: DeckSeries
  exceptions: DeckSeriesException[]
  decks: { id: string; name: string }[]
  canEdit: boolean
  nameOf: (id: string | null) => string
  onChanged: () => void
  showAdd: boolean
}) {
  const [date, setDate] = useState('')
  const [action, setAction] = useState<'skip' | 'deck'>('skip')
  const [deck, setDeck] = useState('')

  async function add() {
    if (!date) return alert('Choose a date.')
    if (action === 'deck' && !deck) return alert('Choose a deck.')
    const row = { series_id: series.id, on_date: date, action, deck_id: action === 'deck' ? deck : null }
    if (await attempt(async () => must(await supabase.from('deck_series_exceptions').upsert(row, { onConflict: 'series_id,on_date' })))) {
      setDate('')
      onChanged()
    }
  }
  async function remove(e: DeckSeriesException) {
    if (await attempt(async () => must(await supabase.from('deck_series_exceptions').delete().eq('series_id', e.series_id).eq('on_date', e.on_date)))) onChanged()
  }

  return (
    <div className="stack-sm cal-exceptions">
      {exceptions.length > 0 && <span className="field-label">Skipped and changed dates</span>}
      {exceptions.map((e) => (
        <div key={e.on_date} className="row spread list-row">
          <span>
            {fmtDay(e.on_date)}: {e.action === 'skip' ? 'skipped' : `plays ${nameOf(e.deck_id)}`}
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
            <select value={action} onChange={(e) => setAction(e.target.value as 'skip' | 'deck')}>
              <option value="skip">Skip (nothing plays)</option>
              <option value="deck">Play a different deck</option>
            </select>
          </label>
          {action === 'deck' && (
            <label className="field grow">
              <span>Deck</span>
              <select value={deck} onChange={(e) => setDeck(e.target.value)}>
                <option value="">Choose…</option>
                {decks.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.name}
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
