import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Location, Module, Site } from '../types'
import { attempt, must } from '../lib'
import { EmptyState, ModuleChips } from '../ui'

const zones: string[] = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : []

type LocationEdit = { key: string; id: string; name: string; modules: Module[] }

function AddLocation({ site, preset }: { site: Site; preset: Module }) {
  const { org, moduleName, reloadOrg } = useApp()
  const [name, setName] = useState('')
  const [tags, setTags] = useState<Module[]>([preset])
  const add = async () => {
    if (!name.trim()) return
    const ok = await attempt(async () =>
      must(await supabase.from('locations').insert({ organization_id: org.id, site_id: site.id, name: name.trim(), modules: tags })),
    )
    if (ok) {
      setName('')
      reloadOrg()
    }
  }
  return (
    <div className="stack-sm panel">
      <div className="row">
        <input
          className="grow"
          placeholder={`New ${moduleName(preset)} location, e.g. Nursery or Lobby`}
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && add()}
        />
        <button className="btn" onClick={add}>
          Add
        </button>
      </div>
      <div className="row wrap-sm">
        <span className="muted">Used by</span>
        <ModuleChips value={tags} onChange={setTags} />
      </div>
    </div>
  )
}

export default function SitesPage() {
  const { org, sites, locations, mySites, modules, moduleName, isAdmin, reloadOrg } = useApp()
  const [newSite, setNewSite] = useState('')
  const [editing, setEditing] = useState<{ id: string; name: string; timezone: string } | null>(null)
  const [editingLocation, setEditingLocation] = useState<LocationEdit | null>(null)

  async function run(action: () => Promise<unknown>) {
    const ok = await attempt(action)
    if (ok) reloadOrg()
    return ok
  }

  const addSite = () =>
    newSite.trim() &&
    run(async () => {
      must(await supabase.from('sites').insert({ organization_id: org.id, name: newSite.trim() }))
      setNewSite('')
    })

  const saveSite = () =>
    editing &&
    editing.name.trim() &&
    run(async () => {
      must(await supabase.from('sites').update({ name: editing.name.trim(), timezone: editing.timezone.trim() }).eq('id', editing.id))
      setEditing(null)
    })

  async function saveLocation() {
    if (!editingLocation || !editingLocation.name.trim()) return
    const { id, name, modules: tags } = editingLocation
    if (await run(async () => must(await supabase.from('locations').update({ name: name.trim(), modules: tags }).eq('id', id)))) {
      setEditingLocation(null)
    }
  }

  const removeSite = (s: Site) => {
    if (confirm(`Delete the ${s.name} site? All its locations, schedules and site-only content will be deleted.`))
      run(async () => must(await supabase.from('sites').delete().eq('id', s.id)))
  }

  const removeLocation = (l: Location) => {
    if (confirm(`Delete ${l.name}? Its schedules will be removed.`))
      run(async () => must(await supabase.from('locations').delete().eq('id', l.id)))
  }

  /** One location row; shown once per application it is tagged for. */
  function renderLocation(l: Location, section: Module | null) {
    const key = `${section ?? 'none'}:${l.id}`
    const others = l.modules.filter((m) => m !== section && modules.some((d) => d.id === m))
    if (editingLocation?.key === key) {
      return (
        <div key={key} className="stack-sm panel">
          <label className="field">
            <span>Name</span>
            <input value={editingLocation.name} onChange={(e) => setEditingLocation({ ...editingLocation, name: e.target.value })} />
          </label>
          <div className="field">
            <span>Used by</span>
            <ModuleChips value={editingLocation.modules} onChange={(v) => setEditingLocation({ ...editingLocation, modules: v })} />
          </div>
          <div className="row">
            <button className="btn primary" onClick={saveLocation}>
              Save
            </button>
            <button className="btn" onClick={() => setEditingLocation(null)}>
              Cancel
            </button>
          </div>
        </div>
      )
    }
    return (
      <div key={key} className="row spread list-row wrap-sm">
        <span>
          {l.name}
          {others.map((m) => (
            <span key={m} className="badge">
              {section ? `also in ${moduleName(m)}` : moduleName(m)}
            </span>
          ))}
        </span>
        {isAdmin && (
          <span className="row">
            <button className="link" onClick={() => setEditingLocation({ key, id: l.id, name: l.name, modules: l.modules })}>
              Edit
            </button>
            <button className="link danger" onClick={() => removeLocation(l)}>
              Delete
            </button>
          </span>
        )}
      </div>
    )
  }

  return (
    <div className="stack">
      {!isAdmin && <p className="muted">Only owners and admins can change sites and locations.</p>}
      <datalist id="zones">
        {zones.map((z) => (
          <option key={z} value={z} />
        ))}
      </datalist>
      {mySites.map((site) => {
        const here = locations.filter((l) => l.site_id === site.id)
        const unassigned = here.filter((l) => !l.modules.some((m) => modules.some((d) => d.id === m)))
        return (
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

            {modules.map((m) => {
              const inSection = here.filter((l) => l.modules.includes(m.id))
              return (
                <div key={m.id} className="loc-section stack-sm">
                  <span className="tag">{m.name}</span>
                  {inSection.length === 0 && <span className="muted">No {m.name} locations at this site.</span>}
                  {inSection.map((l) => renderLocation(l, m.id))}
                  {isAdmin && <AddLocation site={site} preset={m.id} />}
                </div>
              )
            })}

            {unassigned.length > 0 && (
              <div className="loc-section stack-sm">
                <span className="tag">Unassigned</span>
                <span className="muted">These locations aren't used by any application yet. Edit them to choose one.</span>
                {unassigned.map((l) => renderLocation(l, null))}
              </div>
            )}
          </div>
        )
      })}
      {sites.length === 0 && (
        <EmptyState help="ideas">
          A site is a campus or building. Add your first one below, then add the rooms and areas (locations) where TVs will go.
        </EmptyState>
      )}
      {sites.length > 0 && locations.length === 0 && (
        <EmptyState help="ideas">
          Next, add a location for each room or area that has a TV, like a Nursery or Lobby. Tag it {modules.map((m) => m.name).join(', ').replace(/, ([^,]*)$/, ' or $1')} so the right content can play there.
        </EmptyState>
      )}
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
