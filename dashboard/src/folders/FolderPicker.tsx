/** Dialog for choosing a destination folder (media library, playlists, decks). */
export default function FolderPicker({
  title,
  folders,
  exclude,
  currentId,
  onPick,
  onClose,
  rootLabel = 'Library',
}: {
  title: string
  folders: { id: string; parent_id: string | null; name: string }[]
  /** Folders that can't be chosen (a folder and everything inside it). */
  exclude: Set<string>
  currentId?: string | null
  onPick: (id: string | null) => void
  onClose: () => void
  /** Name of the top level, e.g. 'Library' or 'Playlists'. */
  rootLabel?: string
}) {
  const children = (parent: string | null) =>
    folders.filter((f) => f.parent_id === parent).sort((a, b) => a.name.localeCompare(b.name))
  const rows: { id: string | null; name: string; depth: number }[] = [{ id: null, name: `${rootLabel} (top level)`, depth: 0 }]
  const walk = (parent: string | null, depth: number) => {
    for (const f of children(parent)) {
      if (exclude.has(f.id)) continue
      rows.push({ id: f.id, name: f.name, depth })
      walk(f.id, depth + 1)
    }
  }
  walk(null, 1)
  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="modal card stack-sm" role="dialog" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="row spread">
          <h3>{title}</h3>
          <button className="link" onClick={onClose}>
            Cancel
          </button>
        </div>
        <div className="picker-list">
          {rows.map((r) => (
            <button
              key={r.id ?? 'root'}
              className="picker-row"
              style={{ paddingLeft: 12 + r.depth * 18 }}
              disabled={r.id === currentId}
              onClick={() => onPick(r.id)}
            >
              {r.id ? '📁 ' : ''}
              {r.name}
              {r.id === currentId && <span className="muted"> (current)</span>}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
