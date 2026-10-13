import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Location, Site } from '../types'
import { attempt, must } from '../lib'

const zones: string[] = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : []

export default function SitesPage() {
  const { org, sites, locations, mySites, isAdmin, reloadOrg } = useApp()
  const [newSite, setNewSite] = useState('')
  const [newLocations, setNewLocations] = useState<Record<string, string>>({})
  const [editing, setEditing] = useState<{ id: string; name: string; timezone: string } | null>(null)

  async function run(action: () => Promise<unknown>) {
    if (await attempt(action)) reloadOrg()
  }

  const addSite = () =>
    newSite.trim() &&
    run(async () => {
      must(await supabase.from('sites').insert({ organization_id: org.id, name: newSite.trim() }))
      setNewSite('')
    })

  const addLocation = (site: Site) => {
    const name = newLocations[site.id]?.trim()
    if (!name) return
    run(async () => {
      must(await supabase.from('locations').insert({ organization_id: org.id, site_id: site.id, name }))
      setNewLocations((r) => ({ ...r, [site.id]: '' }))
    })
  }

  const saveSite = () =>
    editing &&
    editing.name.trim() &&
    run(async () => {
      must(await supabase.from('sites').update({ name: editing.name.trim(), timezone: editing.timezone.trim() }).eq('id', editing.id))
      setEditing(null)
    })

  const renameLocation = (l: Location) => {
    const name = prompt('New name', l.name)?.trim()
    if (name && name !== l.name) run(async () => must(await supabase.from('locations').update({ name }).eq('id', l.id)))
  }

  const removeSite = (s: Site) => {
    if (confirm(`Delete the ${s.name} site? All its locations, schedules and site-only content will be deleted.`))
      run(async () => must(await supabase.from('sites').delete().eq('id', s.id)))
  }

  const removeLocation = (l: Location) => {
    if (confirm(`Delete ${l.name}? Its schedules will be removed.`))
      run(async () => must(await supabase.from('locations').delete().eq('id', l.id)))
  }

  return (
    <div className="stack">
      {!isAdmin && <p className="muted">Only owners and admins can change sites and locations.</p>}
      <datalist id="zones">
        {zones.map((z) => (
          <option key={z} value={z} />
        ))}
      </datalist>
      {mySites.map((site) => (
        <div key={site.id} className="card stack-sm">
          <div className="row spread wrap-sm">
            <div>
              <h3>{site.name}</h3>
              <span className="muted">Time zone: {site.timezone}</span>
            </div>
            {isAdmin && (
              <span className="row">
                <button className="link" onClick={() => setEditing({ id: site.id, name: site.name, timezone: site.timezone })}>
                  Edit
                </button>
                <button className="link danger" onClick={() => removeSite(site)}>
                  Delete
                </button>
              </span>
            )}
          </div>
          {editing?.id === site.id && (
            <div className="row wrap panel">
              <label className="field grow">
                <span>Name</span>
                <input value={editing.name} onChange={(e) => setEditing({ ...editing, name: e.target.value })} />
              </label>
              <label className="field grow">
                <span>Time zone</span>
                <input list="zones" value={editing.timezone} onChange={(e) => setEditing({ ...editing, timezone: e.target.value })} />
              </label>
              <button className="btn primary align-end" onClick={saveSite}>
                Save
              </button>
              <button className="btn align-end" onClick={() => setEditing(null)}>
                Cancel
              </button>
            </div>
          )}
          {locations
            .filter((l) => l.site_id === site.id)
            .map((l) => (
              <div key={l.id} className="row spread list-row">
                <span>{l.name}</span>
                {isAdmin && (
                  <span className="row">
                    <button className="link" onClick={() => renameLocation(l)}>
                      Rename
                    </button>
                    <button className="link danger" onClick={() => removeLocation(l)}>
                      Delete
                    </button>
                  </span>
                )}
              </div>
            ))}
          {isAdmin && (
            <div className="row">
              <input
                className="grow"
                placeholder="New location, e.g. Nursery or Lobby"
                value={newLocations[site.id] ?? ''}
                onChange={(e) => setNewLocations((r) => ({ ...r, [site.id]: e.target.value }))}
                onKeyDown={(e) => e.key === 'Enter' && addLocation(site)}
              />
              <button className="btn" onClick={() => addLocation(site)}>
                Add location
              </button>
            </div>
          )}
        </div>
      ))}
      {sites.length === 0 && <p className="muted">No sites yet.</p>}
      {isAdmin && (
        <div className="card row">
          <input
            className="grow"
            placeholder="New site (campus) name"
            value={newSite}
            onChange={(e) => setNewSite(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && addSite()}
          />
          <button className="btn" onClick={addSite}>
            Add site
          </button>
        </div>
      )}
    </div>
  )
}
