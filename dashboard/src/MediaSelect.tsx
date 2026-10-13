import type { Media, MediaFolder } from './types'
import { folderPath } from './lib'

/**
 * <select> of library files, grouped by folder path ("Curriculum / Fall 2026") so big libraries stay usable.
 * Files in the top level are listed first, without a group.
 */
export function MediaSelect({
  media,
  folders,
  kind,
  value,
  onChange,
}: {
  media: Media[]
  folders: MediaFolder[]
  kind: Media['kind']
  value: string
  onChange: (id: string) => void
}) {
  const byId = new Map(folders.map((f) => [f.id, f]))
  const groups = new Map<string, Media[]>()
  for (const m of media) {
    if (m.kind !== kind) continue
    // A file whose folder isn't visible to this member is shown at the top level.
    const path = m.folder_id && byId.has(m.folder_id) ? folderPath(m.folder_id, byId) : ''
    groups.set(path, [...(groups.get(path) ?? []), m])
  }
  const paths = [...groups.keys()].sort((a, b) => a.localeCompare(b))
  const known = media.some((m) => m.id === value)
  const option = (m: Media) => (
    <option key={m.id} value={m.id}>
      {m.title}
    </option>
  )
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)}>
      <option value="">Choose…</option>
      {/* A file picked earlier that is no longer listed (moved to another module, or deleted). */}
      {value && !known && <option value={value}>(current file)</option>}
      {(groups.get('') ?? []).map(option)}
      {paths
        .filter((p) => p !== '')
        .map((p) => (
          <optgroup key={p} label={p}>
            {groups.get(p)!.map(option)}
          </optgroup>
        ))}
    </select>
  )
}
