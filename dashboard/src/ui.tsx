import type { ReactNode } from 'react'
import { useApp } from './context'
import type { Module } from './types'
import { helpUrl, type HelpTopic } from './links'

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

/** <option>s for every location the user can see, grouped by site. Pass `module` to only offer locations tagged for that application. */
export function LocationOptions({ module }: { module?: Module } = {}) {
  const { mySites, locations: all } = useApp()
  const locations = module ? all.filter((l) => l.modules.includes(module)) : all
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

/** Toggle chips for choosing applications (location tags). */
export function ModuleChips({ value, onChange }: { value: Module[]; onChange: (v: Module[]) => void }) {
  const { modules } = useApp()
  return (
    <span className="days">
      {modules.map((m) => {
        const on = value.includes(m.id)
        return (
          <button
            type="button"
            key={m.id}
            className={`day ${on ? 'on' : ''}`}
            aria-pressed={on}
            onClick={() => onChange(on ? value.filter((x) => x !== m.id) : [...value, m.id])}
          >
            {m.name}
          </button>
        )
      })}
    </span>
  )
}

/** Friendly notice for a module the church's plan doesn't include. */
export function ModuleOff({ module }: { module: Module }) {
  const { moduleName } = useApp()
  const title = moduleName(module)
  return (
    <div className="card stack-sm">
      <h3>{title} isn't enabled for your church</h3>
      <p className="muted">
        This church doesn't have the {title} module switched on right now. If you think it should be,
        ask your church's owner or the Church TV OS team to enable it.
      </p>
    </div>
  )
}

/** Shown in place of editing controls for people who can only view. */
export function ReadOnlyNote() {
  return <p className="muted">You have view-only access here.</p>
}

/** Friendly empty state: what this is, the next step, and a link to the matching help page. */
export function EmptyState({ children, help }: { children: ReactNode; help: HelpTopic }) {
  return (
    <p className="muted empty-state">
      {children}{' '}
      <a href={helpUrl(help)} target="_blank" rel="noreferrer">
        Learn more
      </a>
    </p>
  )
}
