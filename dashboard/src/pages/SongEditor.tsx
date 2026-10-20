import { useMemo, useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Song } from '../types'
import { attempt, moveItem, must } from '../lib'
import { expandSong, newSectionId, type SongSection } from '../songParsers'

const QUICK_LABELS = ['Verse 1', 'Verse 2', 'Verse 3', 'Verse 4', 'Pre-Chorus', 'Chorus', 'Bridge', 'Tag', 'Intro', 'Outro', 'Ending']
const LINES_CHOICES: { value: number; label: string }[] = [
  { value: 0, label: 'Whole section' },
  { value: 2, label: '2 lines' },
  { value: 3, label: '3 lines' },
  { value: 4, label: '4 lines' },
  { value: 6, label: '6 lines' },
]

/** Small 16:9 cards showing the slides a song will produce (a preview: the database decides what the TV gets). */
export function SlidePreview({ slides }: { slides: { label: string; text: string }[] }) {
  return (
    <div className="slide-grid">
      {slides.map((s, i) => (
        <div key={i} className="slide-card" title={s.label}>
          <span className="slide-tag">
            {i + 1}. {s.label}
          </span>
          <div className="slide-text">{s.text}</div>
        </div>
      ))}
    </div>
  )
}

export default function SongEditor({ song, onDone }: { song: Song | null; onDone: () => void }) {
  const { org } = useApp()
  const [title, setTitle] = useState(song?.title ?? '')
  const [authors, setAuthors] = useState(song?.authors ?? '')
  const [ccli, setCcli] = useState(song?.ccli_number ?? '')
  const [copyright, setCopyright] = useState(song?.copyright ?? '')
  const [lps, setLps] = useState(song?.lines_per_slide ?? 0)
  const [sections, setSections] = useState<SongSection[]>(
    song?.sections?.length ? song.sections : [{ id: 's1', label: 'Verse 1', text: '' }],
  )
  // null = default (every section once, in order)
  const [arrangement, setArrangement] = useState<string[] | null>(song?.arrangement?.length ? song.arrangement : null)
  const [saving, setSaving] = useState(false)

  const byId = useMemo(() => new Map(sections.map((s) => [s.id, s])), [sections])
  const order = arrangement ?? sections.map((s) => s.id)
  const slides = useMemo(
    () => expandSong({ sections, arrangement, lines_per_slide: lps }),
    [sections, arrangement, lps],
  )

  const patchSection = (id: string, patch: Partial<SongSection>) =>
    setSections((list) => list.map((s) => (s.id === id ? { ...s, ...patch } : s)))

  function addSection() {
    const used = new Set(sections.map((s) => s.label))
    const label = QUICK_LABELS.find((l) => !used.has(l)) ?? `Section ${sections.length + 1}`
    setSections((list) => [...list, { id: newSectionId(list), label, text: '' }])
  }

  function duplicateSection(i: number) {
    setSections((list) => {
      const copy = { ...list[i], id: newSectionId(list) }
      return [...list.slice(0, i + 1), copy, ...list.slice(i + 1)]
    })
  }

  function removeSection(id: string) {
    setSections((list) => list.filter((s) => s.id !== id))
    setArrangement((a) => (a ? a.filter((x) => x !== id) : a))
  }

  const setOrder = (next: string[]) => setArrangement(next)

  async function save() {
    if (!title.trim()) return alert('Give the song a title.')
    if (!sections.some((s) => s.text.trim())) return alert('Add some words to at least one section.')
    // An arrangement that is just every section once, in order, is stored as the default (null).
    const valid = arrangement?.filter((id) => byId.has(id)) ?? null
    const isDefault = !valid?.length || (valid.length === sections.length && valid.every((id, i) => id === sections[i].id))
    const row = {
      organization_id: org.id,
      title: title.trim(),
      authors: authors.trim() || null,
      ccli_number: ccli.trim() || null,
      copyright: copyright.trim() || null,
      sections: sections.map((s) => ({ id: s.id, label: s.label.trim() || 'Section', text: s.text.replace(/\s+$/g, '') })),
      arrangement: isDefault ? null : valid,
      lines_per_slide: lps,
      source: song?.source ?? 'manual',
    }
    setSaving(true)
    const ok = await attempt(async () =>
      must(song ? await supabase.from('songs').update(row).eq('id', song.id) : await supabase.from('songs').insert(row)),
    )
    setSaving(false)
    if (ok) onDone()
  }

  const missing = arrangement ? sections.filter((s) => !arrangement.includes(s.id)) : []

  return (
    <div className="stack">
      <div className="card stack-sm">
        <div className="row wrap">
          <label className="field grow">
            <span>Title</span>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Amazing Grace" autoFocus={!song} />
          </label>
          <label className="field grow">
            <span>Authors</span>
            <input value={authors} onChange={(e) => setAuthors(e.target.value)} placeholder="Writers, separated by commas" />
          </label>
        </div>
        <div className="row wrap">
          <label className="field">
            <span>CCLI song number</span>
            <input value={ccli} onChange={(e) => setCcli(e.target.value)} inputMode="numeric" style={{ width: 160 }} />
          </label>
          <label className="field grow">
            <span>Copyright line</span>
            <input value={copyright} onChange={(e) => setCopyright(e.target.value)} placeholder="e.g. © 2004 Example Music" />
          </label>
          <label className="field">
            <span>Lines per slide</span>
            <select value={lps} onChange={(e) => setLps(Number(e.target.value))}>
              {LINES_CHOICES.map((c) => (
                <option key={c.value} value={c.value}>
                  {c.label}
                </option>
              ))}
              {!LINES_CHOICES.some((c) => c.value === lps) && <option value={lps}>{lps} lines</option>}
            </select>
          </label>
        </div>
      </div>

      <div className="card stack-sm">
        <h3>Sections</h3>
        <p className="help">Each section is a verse, chorus and so on. Put one line of the song on each line.</p>
        {sections.map((s, i) => (
          <div key={s.id} className="section-card">
            <div className="section-head">
              <input value={s.label} onChange={(e) => patchSection(s.id, { label: e.target.value })} aria-label="Section name" placeholder="Section name" />
              <button className="icon" onClick={() => setSections((l) => moveItem(l, i, -1))} disabled={i === 0} title="Move up">
                ↑
              </button>
              <button className="icon" onClick={() => setSections((l) => moveItem(l, i, 1))} disabled={i === sections.length - 1} title="Move down">
                ↓
              </button>
              <button className="icon" onClick={() => duplicateSection(i)} title="Duplicate section">
                ⧉
              </button>
              <button className="icon danger" onClick={() => removeSection(s.id)} title="Delete section">
                ✕
              </button>
            </div>
            <div className="quick-picks">
              {QUICK_LABELS.map((l) => (
                <button key={l} type="button" className={`chip-sm ${s.label === l ? 'on' : ''}`} onClick={() => patchSection(s.id, { label: l })}>
                  {l}
                </button>
              ))}
            </div>
            <textarea
              rows={Math.max(5, s.text.split('\n').length + 1)}
              value={s.text}
              onChange={(e) => patchSection(s.id, { text: e.target.value })}
              placeholder="Words for this section"
            />
          </div>
        ))}
        <div>
          <button className="btn" onClick={addSection}>
            + Add section
          </button>
        </div>
      </div>

      <div className="card stack-sm">
        <div className="row spread">
          <h3>Play order</h3>
          {arrangement && (
            <button className="link" onClick={() => setArrangement(null)}>
              Reset to every section once
            </button>
          )}
        </div>
        <p className="help">
          The order the sections are sung in. Add the chorus again wherever it repeats. {arrangement ? '' : 'Right now every section plays once, in order.'}
        </p>
        <div className="arr">
          {order.length === 0 && <span className="muted">Nothing in the play order yet.</span>}
          {order.map((id, i) => {
            const sec = byId.get(id)
            return (
              <span key={`${id}-${i}`} className="arr-chip">
                <span>{sec ? sec.label || 'Section' : '(removed)'}</span>
                <button title="Move earlier" disabled={i === 0} onClick={() => setOrder(moveItem(order, i, -1))}>
                  ←
                </button>
                <button title="Move later" disabled={i === order.length - 1} onClick={() => setOrder(moveItem(order, i, 1))}>
                  →
                </button>
                <button title="Repeat this section after it" onClick={() => setOrder([...order.slice(0, i + 1), id, ...order.slice(i + 1)])}>
                  ⧉
                </button>
                <button className="danger" title="Remove from the play order" onClick={() => setOrder(order.filter((_, j) => j !== i))}>
                  ✕
                </button>
              </span>
            )
          })}
        </div>
        <div className="row wrap-sm">
          <span className="muted">Add to the end:</span>
          {sections.map((s) => (
            <button key={s.id} className="chip-sm" onClick={() => setOrder([...order, s.id])}>
              + {s.label || 'Section'}
            </button>
          ))}
        </div>
        {missing.length > 0 && <p className="note">Not in the play order, so not shown: {missing.map((m) => m.label).join(', ')}.</p>}
      </div>

      <div className="card stack-sm">
        <h3>Preview · {slides.length} {slides.length === 1 ? 'slide' : 'slides'}</h3>
        <SlidePreview slides={slides} />
        {slides.length === 0 && <span className="muted">Add some words and the slides appear here.</span>}
        <p className="help">
          A preview only: the Church TV OS server builds the real slides. When "Show song title first" is on in a playlist, the song name appears as its own slide before these.
        </p>
      </div>

      <div className="row">
        <button className="btn primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : 'Save song'}
        </button>
        <button className="btn" onClick={onDone}>
          Cancel
        </button>
      </div>
    </div>
  )
}
