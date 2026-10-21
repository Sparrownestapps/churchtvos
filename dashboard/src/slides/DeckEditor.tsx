import { useEffect, useMemo, useRef, useState, type DragEvent, type KeyboardEvent } from 'react'
import '../slides.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Deck, DeckSlide, SlideBackground, SlideTheme } from '../slidesTypes'
import type { SlidesLibrary, SongForSlides } from '../slidesPages.types'
import { attempt, moveItem, must, scopeLabel } from '../lib'
import { ScopeSelect, useDefaultScope } from '../ui'
import BackgroundPicker from './BackgroundPicker'
import DeckPreview, { useDefaultColor, useLogoFor } from './DeckPreview'
import SlideEditor from './SlideEditors'
import SlideFrame from './SlideFrame'
import { KIND_NAME, blankSlide, cleanSlide, firstProblem, framesFor, newSlideId, resolveBackground, resolveTheme, slideLabel, type NewKind } from './render'
import { setUnsaved, useUnsavedGuard } from './unsaved'

const KINDS: NewKind[] = ['text', 'media', 'song', 'countdown', 'stream', 'ndi', 'blank']
const KIND_HINT: Record<NewKind, string> = {
  text: 'Title and words',
  media: 'A picture or a video file',
  song: 'Lyrics from the Songs library',
  countdown: 'A timer counting down',
  stream: 'A live HLS video feed',
  ndi: 'Experimental: a camera or computer on the same network',
  blank: 'A plain colour screen',
}

function bgSummary(b: SlideBackground | null) {
  if (!b) return 'Using the theme background'
  return b.type === 'color' ? 'Colour' : b.type === 'gradient' ? 'Gradient' : b.type === 'image' ? (b.url ? 'Image' : 'Image (none chosen)') : b.url ? 'Video' : 'Video (none chosen)'
}

/** One thumbnail in the strip: a small live render of the slide. */
function Thumb({ slide, index, deckBg, theme, songs, fallback, title }: { slide: DeckSlide; index: number; deckBg: SlideBackground | null; theme: SlideTheme | undefined; songs: Map<string, SongForSlides>; fallback: string; title: string }) {
  const frame = framesFor(slide, songs)[0]
  const bg = resolveBackground(slide, deckBg, theme?.config.background, fallback)
  const logo = useLogoFor(bg)
  const resolved = useMemo(() => resolveTheme(theme?.config), [theme])
  return (
    <>
      <span className="sl-num">{index + 1}</span>
      <SlideFrame frame={frame} theme={resolved} background={bg} logo={logo} />
      <span className="sl-thumb-label" title={title}>
        {title}
      </span>
    </>
  )
}

export default function DeckEditor({
  deck,
  lib,
  themes,
  songs,
  onDone,
}: {
  deck: Deck | null
  lib: SlidesLibrary | undefined
  themes: SlideTheme[]
  songs: SongForSlides[]
  onDone: () => void
}) {
  const { org, sites, allSites, mySites, canEditContent } = useApp()
  const defaultScope = useDefaultScope()
  const fallback = useDefaultColor()
  const [deckId, setDeckId] = useState<string | null>(deck?.id ?? null)
  const [name, setName] = useState(deck?.name ?? '')
  const [scope, setScope] = useState<string | null>(deck ? deck.site_id : defaultScope)
  const [themeId, setThemeId] = useState<string>(deck?.theme_id && themes.some((t) => t.id === deck.theme_id) ? deck.theme_id : '')
  const [background, setBackground] = useState<SlideBackground | null>(deck?.background ?? null)
  const [loops, setLoops] = useState(deck?.loops ?? false)
  const [slides, setSlides] = useState<DeckSlide[]>(deck?.slides ?? [])
  const [selectedId, setSelectedId] = useState<string | null>(deck?.slides?.[0]?.id ?? null)
  const [saving, setSaving] = useState(false)
  const [savedAt, setSavedAt] = useState<string | null>(null)
  const [menu, setMenu] = useState(false)
  const [drag, setDrag] = useState<{ from: number; over: number } | null>(null)
  const stripRef = useRef<HTMLDivElement>(null)

  const readOnly = !canEditContent('slides', deck ? deck.site_id : scope)
  const songMap = useMemo(() => new Map(songs.map((s) => [s.id, s])), [songs])
  const theme = themes.find((t) => t.id === themeId)

  const snapshot = (n: string, sc: string | null, t: string, b: SlideBackground | null, l: boolean, s: DeckSlide[]) => JSON.stringify([n, sc, t, b, l, s])
  const baseline = useRef(snapshot(name, scope, themeId, background, loops, slides))
  const dirty = !readOnly && snapshot(name, scope, themeId, background, loops, slides) !== baseline.current

  // Unsaved-changes protection: the nav (App.tsx) asks canLeave(); closing the tab asks the browser.
  useUnsavedGuard(dirty)

  const selIndex = Math.max(0, slides.findIndex((s) => s.id === selectedId))
  const selected: DeckSlide | undefined = slides.find((s) => s.id === selectedId)

  // Keep the selected thumbnail in view.
  useEffect(() => {
    if (selectedId) stripRef.current?.querySelector<HTMLElement>(`[data-id="${selectedId}"]`)?.scrollIntoView({ block: 'nearest', inline: 'nearest' })
  }, [selectedId])

  const mediaTitle = (id: string) => lib?.media.find((m) => m.id === id)?.title
  const setSlide = (next: DeckSlide) => setSlides((list) => list.map((s) => (s.id === next.id ? next : s)))

  function add(kind: NewKind) {
    const s = blankSlide(kind, slides)
    setSlides((list) => {
      const at = selected ? list.findIndex((x) => x.id === selected.id) + 1 : list.length
      return [...list.slice(0, at), s, ...list.slice(at)]
    })
    setSelectedId(s.id)
    setMenu(false)
  }

  function duplicate(i: number) {
    const copy = { ...slides[i], id: newSlideId(slides) } as DeckSlide
    setSlides((list) => [...list.slice(0, i + 1), copy, ...list.slice(i + 1)])
    setSelectedId(copy.id)
  }

  function remove(i: number, ask = true) {
    if (ask && !confirm(`Delete slide ${i + 1} (${slideLabel(slides[i], songMap, mediaTitle)})?`)) return
    const next = slides.filter((_, j) => j !== i)
    setSlides(next)
    setSelectedId(next[Math.min(i, next.length - 1)]?.id ?? null)
  }

  const move = (i: number, by: number) => {
    if (i + by < 0 || i + by >= slides.length) return
    setSlides((list) => moveItem(list, i, by))
  }

  function onStripKey(e: KeyboardEvent) {
    if (slides.length === 0) return
    const go = (i: number) => {
      e.preventDefault()
      setSelectedId(slides[Math.max(0, Math.min(slides.length - 1, i))].id)
    }
    if (e.altKey && (e.key === 'ArrowLeft' || e.key === 'ArrowRight') && !readOnly) {
      e.preventDefault()
      return move(selIndex, e.key === 'ArrowLeft' ? -1 : 1)
    }
    if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') go(selIndex - 1)
    else if (e.key === 'ArrowRight' || e.key === 'ArrowDown') go(selIndex + 1)
    else if (e.key === 'Home') go(0)
    else if (e.key === 'End') go(slides.length - 1)
    else if ((e.key === 'Delete' || e.key === 'Backspace') && !readOnly) {
      e.preventDefault()
      remove(selIndex)
    }
  }

  function onDrop(e: DragEvent, to: number) {
    e.preventDefault()
    if (drag && drag.from !== to) setSlides((list) => moveItem(list, drag.from, to - drag.from))
    setDrag(null)
  }

  function leave() {
    if (dirty && !confirm('You have unsaved changes. Leave without saving?')) return
    setUnsaved(false)
    onDone()
  }

  async function save() {
    if (!name.trim()) return alert('Give the deck a name.')
    const problem = firstProblem(slides, background)
    if (problem) return alert(problem)
    const cleaned = slides.map(cleanSlide)
    const row = { organization_id: org.id, site_id: scope, name: name.trim(), theme_id: themeId || null, background, slides: cleaned, loops }
    setSaving(true)
    const ok = await attempt(async () => {
      if (deckId) {
        const rows = must(await supabase.from('decks').update(row).eq('id', deckId).eq('organization_id', org.id).select('id'))
        if (!rows?.length) throw new Error("Couldn't save this deck. You may not have permission.")
      } else {
        const created = must(await supabase.from('decks').insert(row).select('id').single())
        setDeckId((created as { id: string }).id)
      }
    })
    setSaving(false)
    if (ok) {
      setSlides(cleaned)
      baseline.current = snapshot(row.name, scope, themeId, background, loops, cleaned)
      setName(row.name)
      setSavedAt(new Date().toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }))
    }
  }

  const showScope = allSites || mySites.length > 1

  return (
    <div className="stack">
      <div className="card stack-sm sl-header">
        <div className="row wrap">
          <label className="field grow">
            <span>Deck name</span>
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Sunday welcome loop" disabled={readOnly} autoFocus={!deck} />
          </label>
          <label className="field">
            <span>Theme</span>
            <select value={themeId} onChange={(e) => setThemeId(e.target.value)} disabled={readOnly}>
              <option value="">No theme (default look)</option>
              {themes.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </select>
          </label>
          {showScope && (
            <label className="field">
              <span>Available to</span>
              {readOnly ? <span>{scopeLabel(scope, sites)}</span> : <ScopeSelect value={scope} onChange={setScope} />}
            </label>
          )}
          <label className="check align-end">
            <input type="checkbox" checked={loops} onChange={(e) => setLoops(e.target.checked)} disabled={readOnly} />
            Loop at the end
          </label>
        </div>
        <div className="row wrap">
          {!readOnly && (
            <button className="btn primary" onClick={save} disabled={saving}>
              {saving ? 'Saving…' : 'Save'}
            </button>
          )}
          <button className="btn" onClick={leave}>
            {dirty ? 'Discard and go back' : 'Back to decks'}
          </button>
          <span className="muted" role="status">
            {readOnly ? 'You have view-only access to this deck.' : dirty ? 'Unsaved changes' : savedAt ? `Saved at ${savedAt}` : ''}
          </span>
        </div>
        {loops && <p className="help">When the last slide ends the deck starts again from slide 1. Without this, the TV returns to its home screen.</p>}
        <details className="sl-details">
          <summary>Deck background: {bgSummary(background)}</summary>
          <div className="sl-details-body">
            <BackgroundPicker value={background} onChange={setBackground} lib={lib} inheritLabel="Use theme background" readOnly={readOnly} />
            <p className="help">A slide's own background beats this, and this beats the theme's.</p>
          </div>
        </details>
      </div>

      <div className="card stack-sm">
        <div className="row spread wrap">
          <h3>Slides ({slides.length})</h3>
          {!readOnly && (
            <div className="sl-addwrap">
              <button className="btn primary" aria-haspopup="menu" aria-expanded={menu} onClick={() => setMenu((m) => !m)}>
                + Add slide
              </button>
              {menu && (
                <div className="sl-menu" role="menu" onKeyDown={(e) => e.key === 'Escape' && setMenu(false)}>
                  {KINDS.filter((k) => k !== 'ndi' || org.ndi_enabled).map((k) => (
                    <button key={k} role="menuitem" className="sl-menu-item" onClick={() => add(k)}>
                      <b>{KIND_NAME[k]}</b>
                      <span className="muted">{KIND_HINT[k]}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        {slides.length === 0 ? (
          <p className="muted">No slides yet. {readOnly ? '' : 'Use Add slide to start.'}</p>
        ) : (
          <>
            <div
              ref={stripRef}
              className="sl-strip"
              role="listbox"
              tabIndex={0}
              aria-label="Slides. Arrow keys move between slides, Delete removes the selected slide, Alt plus arrows reorder."
              aria-activedescendant={selected ? `sl-opt-${selected.id}` : undefined}
              onKeyDown={onStripKey}
            >
              {slides.map((s, i) => (
                <div
                  key={s.id}
                  id={`sl-opt-${s.id}`}
                  data-id={s.id}
                  role="option"
                  aria-selected={s.id === selectedId}
                  className={`sl-thumb ${s.id === selectedId ? 'on' : ''} ${drag?.over === i && drag.from !== i ? 'over' : ''} ${drag?.from === i ? 'dragging' : ''}`}
                  draggable={!readOnly}
                  onClick={() => setSelectedId(s.id)}
                  onDragStart={(e) => (e.dataTransfer.setData('text/plain', s.id), (e.dataTransfer.effectAllowed = 'move'), setDrag({ from: i, over: i }))}
                  onDragOver={(e) => drag && (e.preventDefault(), drag.over !== i && setDrag({ ...drag, over: i }))}
                  onDrop={(e) => onDrop(e, i)}
                  onDragEnd={() => setDrag(null)}
                >
                  <Thumb slide={s} index={i} deckBg={background} theme={theme} songs={songMap} fallback={fallback} title={slideLabel(s, songMap, mediaTitle)} />
                </div>
              ))}
            </div>
            {!readOnly && selected && (
              <div className="row wrap sl-tools" role="toolbar" aria-label="Selected slide">
                <button className="btn" onClick={() => move(selIndex, -1)} disabled={selIndex === 0} aria-label={`Move slide ${selIndex + 1} earlier`}>
                  ← Earlier
                </button>
                <button className="btn" onClick={() => move(selIndex, 1)} disabled={selIndex === slides.length - 1} aria-label={`Move slide ${selIndex + 1} later`}>
                  Later →
                </button>
                <button className="btn" onClick={() => duplicate(selIndex)}>
                  Duplicate
                </button>
                <button className="btn danger" onClick={() => remove(selIndex)}>
                  Delete
                </button>
                <span className="muted">Drag thumbnails to reorder.</span>
              </div>
            )}
          </>
        )}
      </div>

      {selected && (
        <div className="sl-work">
          <div className="card">
            <SlideEditor slide={selected} onChange={setSlide} lib={lib} songs={songs} readOnly={readOnly} />
          </div>
          <div className="card sl-preview-card">
            <h3>Preview</h3>
            <DeckPreview slide={selected} deckBackground={background} theme={theme?.config} songs={songMap} />
          </div>
        </div>
      )}

      {!readOnly && slides.length > 0 && (
        <div className="row">
          <button className="btn primary" onClick={save} disabled={saving}>
            {saving ? 'Saving…' : 'Save'}
          </button>
        </div>
      )}
    </div>
  )
}
