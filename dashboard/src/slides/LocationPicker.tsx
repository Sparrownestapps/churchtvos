import '../slides.css'
import { useApp } from '../context'
import type { Location, Site } from '../types'

/**
 * Locations that can run Slides: tagged 'slides', or tagged 'kids' (existing churches have not tagged anything for Slides yet,
 * so their Kids rooms are offered too).
 */
export const isSlidesLocation = (l: Location) => l.modules.includes('slides') || l.modules.includes('kids')
const slidesOnly = (l: Location) => l.modules.includes('slides')

/** Hint under a location picker: explains why Kids rooms are listed and links to the tagging page. */
export function LocationHint({ offered }: { offered: Location[] }) {
  const { locations } = useApp()
  const tagged = locations.filter(slidesOnly).length
  return (
    <p className="muted">
      {offered.length === 0
        ? 'No locations are tagged for Slides (or Kids) yet. '
        : tagged === 0
          ? "No locations are tagged for Slides yet, so rooms tagged Kids are listed too (marked Kids). "
          : 'Rooms tagged Slides are listed, and so are rooms tagged Kids (marked Kids). '}
      Tag a room for Slides under <a href="#sites">Sites &amp; Locations</a>.
    </p>
  )
}

/** Checkbox list of locations grouped by site (same look as the Kids schedule page). */
export default function LocationPicker({
  sites,
  locations,
  value,
  onChange,
}: {
  sites: Site[]
  locations: Location[]
  value: string[]
  onChange: (ids: string[]) => void
}) {
  const toggle = (id: string) => onChange(value.includes(id) ? value.filter((x) => x !== id) : [...value, id])
  return (
    <div className="room-picker">
      {sites.map((site) => {
        const here = locations.filter((l) => l.site_id === site.id)
        if (here.length === 0) return null
        const allOn = here.every((l) => value.includes(l.id))
        return (
          <div key={site.id} className="room-group">
            <div className="row spread">
              <b>{site.name}</b>
              <button type="button" className="link" onClick={() => onChange(allOn ? value.filter((id) => !here.some((l) => l.id === id)) : [...new Set([...value, ...here.map((l) => l.id)])])}>
                {allOn ? 'None' : 'All'}
              </button>
            </div>
            {here.map((l) => (
              <label key={l.id} className="check">
                <input type="checkbox" checked={value.includes(l.id)} onChange={() => toggle(l.id)} />
                {l.name}
                {!slidesOnly(l) && <span className="muted"> (Kids)</span>}
              </label>
            ))}
          </div>
        )
      })}
    </div>
  )
}
