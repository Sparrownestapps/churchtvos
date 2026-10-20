import { useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { DeckSchedule } from '../slidesTypes'
import type { DeckRef } from '../slidesPages.types'
import { attempt, fmtWhen, locationLabel, must, nextSundayAt, toLocalInput, useLoad } from '../lib'
import { ReadOnlyNote } from '../ui'
import DeckSeriesManager from './DeckSeriesManager'
import LocationPicker, { LocationHint, isSlidesLocation } from './LocationPicker'

export default function SlidesSchedulePage() {
  const { org, mySites, locations, sites, canEditContent } = useApp()
  const canEdit = mySites.some((s) => canEditContent('slides', s.id))
  const [deckId, setDeckId] = useState('')
  const [locationIds, setLocationIds] = useState<string[]>([])
  const [start, setStart] = useState(toLocalInput(nextSundayAt(9)))
  const [end, setEnd] = useState('')

  const { data, reload } = useLoad(async () => {
    const [decks, schedules] = await Promise.all([
      supabase.from('decks').select('id, name, site_id').eq('organization_id', org.id).order('name'),
      supabase.from('deck_schedules').select('*').eq('organization_id', org.id).or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`).order('starts_at'),
    ])
    return { decks: must(decks) as DeckRef[], schedules: must(schedules) as DeckSchedule[] }
  }, [org.id])

  const decks = data?.decks ?? []
  const deck = decks.find((d) => d.id === deckId)
  // A site-only deck can only go to that site's locations.
  const visibleSites = mySites.filter((s) => (!deck?.site_id || deck.site_id === s.id) && canEditContent('slides', s.id))
  const offered = locations.filter((l) => isSlidesLocation(l) && visibleSites.some((s) => s.id === l.site_id))
  const allOffered = locations.filter(isSlidesLocation)

  async function create() {
    const chosen = locationIds.filter((id) => offered.some((l) => l.id === id))
    if (!deckId) return alert('Choose a deck.')
    if (chosen.length === 0) return alert('Choose at least one location.')
    if (!start) return alert('Choose a start time.')
    if (end && new Date(end) <= new Date(start)) return alert('The end time must be after the start time.')
    const rows = chosen.map((location_id) => ({
      organization_id: org.id,
      location_id,
      deck_id: deckId,
      starts_at: new Date(start).toISOString(),
      ends_at: end ? new Date(end).toISOString() : null,
    }))
    if (await attempt(async () => must(await supabase.from('deck_schedules').insert(rows)))) {
      setLocationIds([])
      reload()
    }
  }

  async function remove(s: DeckSchedule) {
    if (!confirm('Remove this from the schedule?')) return
    if (await attempt(async () => must(await supabase.from('deck_schedules').delete().eq('id', s.id).eq('organization_id', org.id)))) reload()
  }

  // Same rule as the TV: in each location, the latest schedule that has started is the one showing; the first one after is next.
  const now = Date.now()
  const schedules = (data?.schedules ?? []).filter((s) => locations.some((l) => l.id === s.location_id))
  const showing = new Map<string, string>()
  const next = new Map<string, string>()
  for (const s of schedules) {
    if (new Date(s.starts_at).getTime() <= now) showing.set(s.location_id, s.id)
    else if (!next.has(s.location_id)) next.set(s.location_id, s.id)
  }

  return (
    <div className="stack">
      {!canEdit && <ReadOnlyNote />}
      {canEdit && (
        <div className="card stack-sm">
          <h3>Schedule a deck</h3>
          <div className="row wrap">
            <label className="field grow">
              <span>Deck</span>
              <select value={deckId} onChange={(e) => setDeckId(e.target.value)}>
                <option value="">Choose…</option>
                {decks.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.name}
                  </option>
                ))}
              </select>
            </label>
            <label className="field">
              <span>Starts</span>
              <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} />
            </label>
            <label className="field">
              <span>Ends (optional)</span>
              <input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} />
            </label>
          </div>
          <div className="field">
            <span>Locations</span>
            <LocationPicker sites={visibleSites} locations={offered} value={locationIds} onChange={setLocationIds} />
            <LocationHint offered={allOffered} />
          </div>
          <div>
            <button className="btn primary" onClick={create}>
              Add to schedule
            </button>
          </div>
          <p className="muted">
            A deck stays on a location's TV until its end time, or until the next scheduled deck starts. TVs download everything scheduled in the next 14 days ahead of time. Times are in your browser's time zone.
          </p>
        </div>
      )}

      <div className="card">
        <h3>Current &amp; upcoming</h3>
        {schedules.length === 0 ? (
          <p className="muted empty-state">Nothing scheduled yet. Choose a deck, a start time and the locations above to put it on the TVs. For something that repeats every week, use Repeating schedules below.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>When</th>
                <th>Location</th>
                <th>Deck</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {schedules.map((s) => {
                const started = new Date(s.starts_at).getTime() <= now
                const status = showing.get(s.location_id) === s.id ? 'Showing now' : started ? 'Replaced' : next.get(s.location_id) === s.id ? 'Up next' : 'Upcoming'
                const site = sites.find((x) => x.id === locations.find((l) => l.id === s.location_id)?.site_id)
                return (
                  <tr key={s.id} className={status === 'Replaced' ? 'faded' : ''}>
                    <td>
                      {fmtWhen(s.starts_at)}
                      {s.ends_at && <span className="muted"> → {fmtWhen(s.ends_at)}</span>}
                    </td>
                    <td>{locationLabel(locations.find((l) => l.id === s.location_id), sites)}</td>
                    <td>{decks.find((d) => d.id === s.deck_id)?.name ?? '—'}</td>
                    <td>
                      <span className={`status ${status === 'Showing now' ? 'live' : ''}`}>{status}</span>
                    </td>
                    <td>
                      {canEditContent('slides', site?.id ?? null) && (
                        <button className="link danger" onClick={() => remove(s)}>
                          Remove
                        </button>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        )}
      </div>

      <div className="card stack-sm">
        <h3>Repeating schedules</h3>
        <p className="muted">Weekly schedules with a rotation of decks: Week 1 plays one deck, Week 2 the next, and so on.</p>
        <DeckSeriesManager decks={decks} />
      </div>
    </div>
  )
}
