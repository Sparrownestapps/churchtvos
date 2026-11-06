// A searchable picker for Kids playlists, Signage playlists and Slides decks in the calendar. Lists what's already on the
// TV being shown first, then recently used, then everything else by folder; limited to that TV's site unless switched off.
import { createContext, useContext, useEffect, useMemo, useRef, useState } from 'react'
import { pickerSections, readRecent, rememberRecent, type PickerFolder, type PickerItem } from './pickerGroups'

export type PickerKind = 'kids' | 'signage' | 'slides'

export type PickerContextValue = {
  orgId: string
  folders: Record<PickerKind, PickerFolder[]>
  inUse: Record<PickerKind, Set<string>>
  siteIds: string[]
}

export const PickerContext = createContext<PickerContextValue | null>(null)

const EMPTY = new Set<string>()

export default function PlaylistPicker({
  kind,
  items,
  value,
  onChange,
  disabled,
  placeholder = 'Choose…',
  className,
}: {
  kind: PickerKind
  items: PickerItem[]
  value: string
  onChange: (id: string) => void
  disabled?: boolean
  placeholder?: string
  className?: string
}) {
  const ctx = useContext(PickerContext)
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState('')
  const [otherSites, setOtherSites] = useState(false)
  const [active, setActive] = useState(0)
  const box = useRef<HTMLDivElement>(null)
  const search = useRef<HTMLInputElement>(null)
  const list = useRef<HTMLDivElement>(null)

  const recent = useMemo(() => (ctx && open ? readRecent(ctx.orgId, kind) : []), [ctx, kind, open])
  const { sections, hiddenBySite } = pickerSections({
    items,
    folders: ctx?.folders[kind] ?? [],
    inUse: ctx?.inUse[kind] ?? EMPTY,
    recent,
    siteIds: ctx?.siteIds ?? [],
    includeOtherSites: otherSites,
    query,
    selected: value,
  })
  const flat = sections.flatMap((s) => s.items)
  const current = items.find((p) => p.id === value)

  // Close on a click outside.
  useEffect(() => {
    if (!open) return
    const onDown = (e: MouseEvent) => {
      if (box.current && !box.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDown)
    return () => document.removeEventListener('mousedown', onDown)
  }, [open])

  useEffect(() => {
    if (open) {
      setQuery('')
      const i = flat.findIndex((p) => p.id === value)
      setActive(i >= 0 ? i : 0)
      setTimeout(() => search.current?.focus(), 0)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open])

  useEffect(() => {
    list.current?.querySelector<HTMLElement>(`[data-i="${active}"]`)?.scrollIntoView({ block: 'nearest' })
  }, [active])

  function choose(id: string) {
    if (ctx) rememberRecent(ctx.orgId, kind, id)
    onChange(id)
    setOpen(false)
  }

  function onKey(e: React.KeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setActive((i) => Math.min(flat.length - 1, i + 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setActive((i) => Math.max(0, i - 1))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      if (flat[active]) choose(flat[active].id)
    } else if (e.key === 'Escape') {
      // Close just the picker, not the side panel it sits in.
      e.preventDefault()
      e.stopPropagation()
      setOpen(false)
    }
  }

  let i = -1
  return (
    <div className={`picker ${className ?? ''}`} ref={box}>
      <button type="button" className="picker-button" disabled={disabled} onClick={() => setOpen((o) => !o)} aria-haspopup="listbox" aria-expanded={open}>
        <span className={current ? '' : 'muted'}>{current ? current.name : placeholder}</span>
        <span className="picker-caret">▾</span>
      </button>
      {open && (
        <div className="picker-pop" onKeyDown={onKey}>
          <input
            ref={search}
            type="search"
            placeholder={`Search ${kind === 'slides' ? 'decks' : 'playlists'} or folders`}
            value={query}
            onChange={(e) => {
              setQuery(e.target.value)
              setActive(0)
            }}
          />
          <div className="picker-list" role="listbox" ref={list}>
            {sections.map((s) => (
              <div key={s.title} className="picker-section">
                <div className="picker-title">{s.title}</div>
                {s.items.map((p) => {
                  i++
                  const idx = i
                  return (
                    <button
                      type="button"
                      key={p.id}
                      data-i={idx}
                      role="option"
                      aria-selected={p.id === value}
                      className={`picker-option ${idx === active ? 'active' : ''} ${p.id === value ? 'chosen' : ''}`}
                      onMouseEnter={() => setActive(idx)}
                      onClick={() => choose(p.id)}
                    >
                      <span className="picker-check">{p.id === value ? '✓' : ''}</span>
                      {p.name}
                      {p.archived_at && <span className="badge">archived</span>}
                    </button>
                  )
                })}
              </div>
            ))}
            {flat.length === 0 && <p className="muted picker-empty">Nothing matches.</p>}
          </div>
          {(hiddenBySite > 0 || otherSites) && (
            <label className="picker-sites">
              <input type="checkbox" checked={otherSites} onChange={(e) => setOtherSites(e.target.checked)} />
              Include other sites{hiddenBySite > 0 ? ` (${hiddenBySite} more)` : ''}
            </label>
          )}
        </div>
      )}
    </div>
  )
}
