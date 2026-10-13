import { useApp } from './context'
import type { Module } from './types'

/** Which site a piece of content belongs to. Only people with all-sites access can share with all sites. */
export function ScopeSelect({ value, onChange }: { value: string | null; onChange: (v: string | null) => void }) {
  const { allSites, mySites } = useApp()
  return (
    <select value={value ?? ''} onChange={(e) => onChange(e.target.value || null)}>
      {allSites && <option value="">All sites</option>}
      {mySites.map((s) => (
        <option key={s.id} value={s.id}>
          {s.name} only
        </option>
      ))}
    </select>
  )
}

/** <option>s for every location the user can see, grouped by site. */
export function LocationOptions() {
  const { mySites, locations } = useApp()
  return (
    <>
      {mySites.map((site) => (
        <optgroup key={site.id} label={site.name}>
          {locations
            .filter((l) => l.site_id === site.id)
            .map((l) => (
              <option key={l.id} value={l.id}>
                {l.name}
              </option>
            ))}
        </optgroup>
      ))}
    </>
  )
}

/** Default site for new content: all sites if allowed, otherwise the member's first site. */
export function useDefaultScope() {
  const { allSites, mySites } = useApp()
  return allSites ? null : mySites[0]?.id ?? null
}

const MODULE_TITLE: Record<Module, string> = { kids: 'Kids', signage: 'Signage' }

/** Friendly notice for a module the church's plan doesn't include. */
export function ModuleOff({ module }: { module: Module }) {
  return (
    <div className="card stack-sm">
      <h3>{MODULE_TITLE[module]} isn't enabled for your church</h3>
      <p className="muted">
        This church doesn't have the {MODULE_TITLE[module]} module switched on right now. If you think it should be,
        ask your church's owner or the Church TV OS team to enable it.
      </p>
    </div>
  )
}

/** Shown in place of editing controls for people who can only view. */
export function ReadOnlyNote() {
  return <p className="muted">You have view-only access here.</p>
}
