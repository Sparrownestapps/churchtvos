import { Suspense, lazy, useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Playlist, Schedule } from '../types'
import { attempt, fmtWhen, must, nextSundayAt, locationLabel, toLocalInput, useLoad } from '../lib'
import { ReadOnlyNote } from '../ui'

const SeriesManager = lazy(() => import('../calendar/SeriesManager'))

export default function SchedulePage() {
  const { org, mySites, locations, sites, canEditContent } = useApp()
  const canEdit = mySites.some((s) => canEditContent('kids', s.id))
  const [playlistId, setPlaylistId] = useState('')
  const [locationIds, setLocationIds] = useState<string[]>([])
  const [start, setStart] = useState(toLocalInput(nextSundayAt(8)))
  const [end, setEnd] = useState('')

  const { data, reload } = useLoad(async () => {
    const [playlists, schedules] = await Promise.all([
      supabase.from('playlists').select('id, name, site_id').eq('organization_id', org.id).order('name'),
      supabase
        .from('schedules')
        .select('*')
        .eq('organization_id', org.id)
        .or(`ends_at.is.null,ends_at.gt.${new Date().toISOString()}`)
        .order('starts_at'),
    ])
    return { playlists: must(playlists) as Playlist[], schedules: must(schedules) as Schedule[] }
  })

  const playlists = data?.playlists ?? []
  const playlist = playlists.find((p) => p.id === playlistId)
  // A site-only playlist can only go to that site's locations.
  const visibleSites = mySites.filter((s) => (!playlist?.site_id || playlist.site_id === s.id) && canEditContent('kids', s.id))
  // Only rooms tagged for Kids can run a Kids schedule.
  const visibleLocations = locations.filter((l) => l.modules.includes('kids') && visibleSites.some((s) => s.id === l.site_id))

  const toggle = (id: string) => setLocationIds((ids) => (ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id]))

  async function create() {
    const chosen = locationIds.filter((id) => visibleLocations.some((l) => l.id === id))
    if (!playlistId) return alert('Choose a playlist.')
    if (chosen.length === 0) return alert('Choose at least one location.')
    if (end && new Date(end) <= new Date(start)) return alert('The end time must be after the start time.')
    const rows = chosen.map((location_id) => ({
      organization_id: org.id,
      location_id,
      playlist_id: playlistId,
      starts_at: new Date(start).toISOString(),
      ends_at: end ? new Date(end).toISOString() : null,
    }))
    if (await attempt(async () => must(await supabase.from('schedules').insert(rows)))) {
      setLocationIds([])
      reload()
    }
  }

  async function remove(s: Schedule) {
    if (!confirm('Remove this from the schedule?')) return
    if (await attempt(async () => must(await supabase.from('schedules').delete().eq('id', s.id)))) reload()
  }

  // Same rule as the TV: in each location, the latest schedule that has started is the one showing.
  const now = Date.now()
  const showing = new Map<string, string>()
  for (const s of data?.schedules ?? []) {
    if (new Date(s.starts_at).getTime() <= now) showing.set(s.location_id, s.id)
  }
  const schedules = (data?.schedules ?? []).filter((s) => locations.some((l) => l.id === s.location_id))

  return (
    <div className="stack">
      {!canEdit && <ReadOnlyNote />}
      {canEdit && <div className="card stack-sm">
        <h3>Schedule a playlist</h3>
        <div className="row wrap">
          <label className="field grow">
            <span>Playlist</span>
            <select value={playlistId} onChange={(e) => setPlaylistId(e.target.value)}>
              <option value="">Choose…</option>
              {playlists.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
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
          <div className="room-picker">
            {visibleSites.map((site) => {
              const siteLocations = visibleLocations.filter((l) => l.site_id === site.id)
              if (siteLocations.length === 0) return null
              const allOn = siteLocations.every((l) => locationIds.includes(l.id))
              return (
                <div key={site.id} className="room-group">
                  <div className="row spread">
                    <b>{site.name}</b>
                    <button
                      className="link"
                      onClick={() =>
                        setLocationIds((ids) =>
                          allOn
                            ? ids.filter((id) => !siteLocations.some((l) => l.id === id))
                            : [...new Set([...ids, ...siteLocations.map((l) => l.id)])],
                        )
                      }
                    >
                      {allOn ? 'None' : 'All'}
                    </button>
                  </div>
                  {siteLocations.map((l) => (
                    <label key={l.id} className="check">
                      <input type="checkbox" checked={locationIds.includes(l.id)} onChange={() => toggle(l.id)} />
                      {l.name}
                    </label>
                  ))}
                </div>
              )
            })}
          </div>
          {visibleLocations.length === 0 && (
            <p className="muted">No locations are tagged for Kids yet. Tag them under Sites & Locations.</p>
          )}
        </div>
        <div>
          <button className="btn primary" onClick={create}>
            Add to schedule
          </button>
        </div>
        <p className="muted">
          A playlist stays on a location's TV until its end time, or until the next scheduled playlist starts. TVs
          download everything scheduled in the next 14 days ahead of time.
        </p>
      </div>}

      <div className="card">
        <h3>Current & upcoming</h3>
        {schedules.length === 0 ? (
          <p className="muted">Nothing scheduled.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>When</th>
                <th>Location</th>
                <th>Playlist</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {schedules.map((s) => {
                const started = new Date(s.starts_at).getTime() <= now
                const status = showing.get(s.location_id) === s.id ? 'Showing now' : started ? 'Replaced' : 'Upcoming'
                return (
                  <tr key={s.id} className={status === 'Replaced' ? 'faded' : ''}>
                    <td>
                      {fmtWhen(s.starts_at)}
                      {s.ends_at && <span className="muted"> → {fmtWhen(s.ends_at)}</span>}
                    </td>
                    <td>{locationLabel(locations.find((l) => l.id === s.location_id), sites)}</td>
                    <td>{data?.playlists.find((p) => p.id === s.playlist_id)?.name ?? '—'}</td>
                    <td>
                      <span className={`status ${status === 'Showing now' ? 'live' : ''}`}>{status}</span>
                    </td>
                    <td>
                      {canEdit && (
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
        <p className="muted">Weekly schedules with a playlist rotation. They are also drawn on the Calendar.</p>
        <Suspense fallback={<p className="muted">Loading…</p>}>
          <SeriesManager />
        </Suspense>
      </div>
    </div>
  )
}
