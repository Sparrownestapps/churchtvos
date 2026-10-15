import { useEffect, type ReactNode } from 'react'
import { moveItem } from '../lib'
import type { NamedRow } from '../calendarTypes'
import '../calendar.css'

/** Side panel on desktop, bottom sheet on phones. */
export function Drawer({ title, onClose, children, wide }: { title: string; onClose: () => void; children: ReactNode; wide?: boolean }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <>
      <div className="cal-scrim" onClick={onClose} />
      <aside className={`cal-panel ${wide ? 'wide' : ''}`} role="dialog" aria-label={title}>
        <div className="cal-panel-head">
          <h3>{title}</h3>
          <button className="icon" aria-label="Close" onClick={onClose}>
            ✕
          </button>
        </div>
        <div className="cal-panel-body stack-sm">{children}</div>
      </aside>
    </>
  )
}

export type Choice = { label: string; hint?: string; danger?: boolean; run: () => void | Promise<void> }
export type DialogState = { title: string; message?: string; choices: Choice[]; onCancel?: () => void }

/** A small "this one or the whole series?" style question. */
export function ChoiceDialog({ dialog, close }: { dialog: DialogState; close: () => void }) {
  const cancel = () => {
    dialog.onCancel?.()
    close()
  }
  return (
    <div className="modal-scrim cal-dialog-scrim" onClick={cancel}>
      <div className="card modal stack-sm" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={dialog.title}>
        <h3>{dialog.title}</h3>
        {dialog.message && <p className="muted">{dialog.message}</p>}
        {dialog.choices.map((c) => (
          <button
            key={c.label}
            className={`btn cal-choice ${c.danger ? 'danger' : ''}`}
            onClick={async () => {
              close()
              await c.run()
            }}
          >
            <b>{c.label}</b>
            {c.hint && <span className="muted">{c.hint}</span>}
          </button>
        ))}
        <button className="link" onClick={cancel}>
          Cancel
        </button>
      </div>
    </div>
  )
}

/** Ordered list of Kids playlists: "Week 1, Week 2, ..." plus what happens at the end. */
export function RotationEditor({
  value,
  onChange,
  playlists,
  onEnd,
  onEndChange,
  readOnly,
}: {
  value: string[]
  onChange: (v: string[]) => void
  playlists: NamedRow[]
  onEnd: 'stop' | 'loop'
  onEndChange: (v: 'stop' | 'loop') => void
  readOnly?: boolean
}) {
  const nameOf = (id: string) => playlists.find((p) => p.id === id)?.name ?? '—'
  return (
    <div className="stack-sm cal-rotation">
      {value.map((id, i) => (
        <div key={i} className="row">
          <b className="cal-weeklabel">Week {i + 1}</b>
          {readOnly ? (
            <span>{nameOf(id)}</span>
          ) : (
            <>
              <select className="grow" value={id} onChange={(e) => onChange(value.map((v, j) => (j === i ? e.target.value : v)))}>
                <option value="">Choose…</option>
                {playlists.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
              <button type="button" className="icon" aria-label="Move up" disabled={i === 0} onClick={() => onChange(moveItem(value, i, -1))}>
                ↑
              </button>
              <button type="button" className="icon" aria-label="Move down" disabled={i === value.length - 1} onClick={() => onChange(moveItem(value, i, 1))}>
                ↓
              </button>
              <button type="button" className="icon danger" aria-label="Remove" disabled={value.length <= 1} onClick={() => onChange(value.filter((_, j) => j !== i))}>
                ✕
              </button>
            </>
          )}
        </div>
      ))}
      {!readOnly && (
        <div>
          <button type="button" className="link" onClick={() => onChange([...value, value[value.length - 1] ?? ''])}>
            + Add another week
          </button>
        </div>
      )}
      {value.length > 1 && (
        <label className="field">
          <span>After the last week</span>
          {readOnly ? (
            <span>{onEnd === 'loop' ? 'Start again from Week 1' : 'Stop (nothing plays)'}</span>
          ) : (
            <select value={onEnd} onChange={(e) => onEndChange(e.target.value as 'stop' | 'loop')}>
              <option value="loop">Loop: start again from Week 1</option>
              <option value="stop">Stop: nothing plays after Week {value.length}</option>
            </select>
          )}
        </label>
      )}
      {value.length === 1 && <p className="muted">One playlist: it plays every week. Add more weeks for a curriculum rotation.</p>}
    </div>
  )
}
