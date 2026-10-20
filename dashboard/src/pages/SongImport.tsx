import { useRef, useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Song } from '../types'
import { attempt, must } from '../lib'
import { SONG_FILE_EXTENSIONS, parsePlainText, parseSongFile, type ParsedSong } from '../songParsers'

type Action = 'import' | 'skip' | 'replace' | 'copy'
type Entry = { key: number; source: 'paste' | 'file'; fileName: string; song: ParsedSong; action: Action }

const norm = (s: string) => s.trim().toLowerCase()
const MAX_BYTES = 1024 * 1024

/** The existing library song this entry would duplicate: same CCLI number, or same title. */
function findDup(song: ParsedSong, library: Song[]): Song | null {
  const ccli = song.ccli_number.trim()
  return (
    library.find((x) => (ccli && (x.ccli_number ?? '').trim() === ccli) || (norm(song.title) && norm(x.title) === norm(song.title))) ?? null
  )
}

/** What will actually happen to an entry (a duplicate defaults to being skipped). */
function effective(e: Entry, dup: Song | null): Action {
  if (dup) return e.action === 'import' ? 'skip' : e.action
  return e.action === 'skip' ? 'skip' : 'import'
}

export default function SongImport({ library, initialTab, onClose, onSaved }: { library: Song[]; initialTab: 'paste' | 'files'; onClose: () => void; onSaved: () => void }) {
  const { org } = useApp()
  const [tab, setTab] = useState(initialTab)
  const [entries, setEntries] = useState<Entry[]>([])
  const [pasteTitle, setPasteTitle] = useState('')
  const [pasteText, setPasteText] = useState('')
  const [notes, setNotes] = useState<string[]>([])
  const [dragging, setDragging] = useState(false)
  const [saving, setSaving] = useState(false)
  const nextKey = useRef(1)
  const fileInput = useRef<HTMLInputElement>(null)

  function addPasted() {
    if (!pasteText.trim()) return
    const song = parsePlainText(pasteText, pasteTitle)
    if (!song.title) song.title = 'Untitled song'
    setEntries((l) => [...l, { key: nextKey.current++, source: 'paste', fileName: '', song, action: 'import' }])
    setPasteTitle('')
    setPasteText('')
  }

  async function addFiles(files: FileList | File[]) {
    const added: Entry[] = []
    const skipped: string[] = []
    for (const f of Array.from(files)) {
      const ext = (/\.([a-z0-9]+)$/i.exec(f.name)?.[1] ?? '').toLowerCase()
      if (!SONG_FILE_EXTENSIONS.includes(ext)) {
        skipped.push(`${f.name}: not a .txt, .usr, .cho, .chordpro or .pro file`)
        continue
      }
      if (f.size > MAX_BYTES) {
        skipped.push(`${f.name}: too big for a lyric file`)
        continue
      }
      try {
        const song = parseSongFile(f.name, await f.text())
        if (song.sections.length === 0) {
          skipped.push(`${f.name}: no lyrics found`)
          continue
        }
        added.push({ key: nextKey.current++, source: 'file', fileName: f.name, song, action: 'import' })
      } catch {
        skipped.push(`${f.name}: couldn't be read`)
      }
    }
    setEntries((l) => [...l, ...added])
    setNotes(skipped)
  }

  const patch = (key: number, p: Partial<Entry>) => setEntries((l) => l.map((e) => (e.key === key ? { ...e, ...p } : e)))
  const patchSong = (key: number, p: Partial<ParsedSong>) =>
    setEntries((l) => l.map((e) => (e.key === key ? { ...e, song: { ...e.song, ...p } } : e)))

  const plan = entries.map((e) => {
    const dup = findDup(e.song, library)
    return { e, dup, act: effective(e, dup) }
  })
  const toAdd = plan.filter((p) => (p.act === 'import' || p.act === 'copy') && p.e.song.title.trim())
  const toReplace = plan.filter((p) => p.act === 'replace' && p.dup && p.e.song.title.trim())

  async function save() {
    setSaving(true)
    const ok = await attempt(async () => {
      if (toAdd.length) {
        const rows = toAdd.map(({ e, dup, act }) => ({
          organization_id: org.id,
          title: act === 'copy' && dup && norm(dup.title) === norm(e.song.title) ? `${e.song.title.trim()} (copy)` : e.song.title.trim(),
          authors: e.song.authors.trim() || null,
          ccli_number: e.song.ccli_number.trim() || null,
          copyright: e.song.copyright.trim() || null,
          sections: e.song.sections,
          arrangement: null,
          lines_per_slide: 0,
          source: e.source,
        }))
        must(await supabase.from('songs').insert(rows)) // one batch insert
      }
      for (const { e, dup } of toReplace) {
        must(
          await supabase
            .from('songs')
            .update({
              title: e.song.title.trim(),
              authors: e.song.authors.trim() || null,
              ccli_number: e.song.ccli_number.trim() || null,
              copyright: e.song.copyright.trim() || null,
              sections: e.song.sections,
              arrangement: null, // section ids change, so the old play order no longer applies
              source: e.source,
            })
            .eq('id', dup!.id),
        )
      }
    })
    setSaving(false)
    if (ok) onSaved()
  }

  const total = toAdd.length + toReplace.length

  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="modal wide card stack" role="dialog" aria-label="Import songs" onClick={(e) => e.stopPropagation()}>
        <div className="row spread">
          <h3>Import songs</h3>
          <button className="link" onClick={onClose}>
            Close
          </button>
        </div>
        <p className="note">Only add lyrics your church is licensed to display (for example with a CCLI licence).</p>

        <div className="segmented">
          <button className={tab === 'paste' ? 'on' : ''} onClick={() => setTab('paste')}>
            Paste lyrics
          </button>
          <button className={tab === 'files' ? 'on' : ''} onClick={() => setTab('files')}>
            Import files
          </button>
        </div>

        {tab === 'paste' ? (
          <div className="stack-sm">
            <label className="field">
              <span>Title (optional: a first line followed by a blank line is used otherwise)</span>
              <input value={pasteTitle} onChange={(e) => setPasteTitle(e.target.value)} />
            </label>
            <label className="field">
              <span>Lyrics · section names like Verse 1 or Chorus start a new section, otherwise blank lines do</span>
              <textarea rows={10} value={pasteText} onChange={(e) => setPasteText(e.target.value)} />
            </label>
            <div>
              <button className="btn primary" onClick={addPasted} disabled={!pasteText.trim()}>
                Add to review
              </button>
            </div>
          </div>
        ) : (
          <div className="stack-sm">
            <div
              className={`drop small ${dragging ? 'dragging' : ''}`}
              onClick={() => fileInput.current?.click()}
              onDragOver={(e) => (e.preventDefault(), setDragging(true))}
              onDragLeave={() => setDragging(false)}
              onDrop={(e) => {
                e.preventDefault()
                setDragging(false)
                void addFiles(e.dataTransfer.files)
              }}
            >
              <b>Drop lyric files here, or tap to choose</b>
              <span className="muted">.txt, .usr (CCLI SongSelect), .cho / .chordpro / .pro (ChordPro)</span>
            </div>
            <input
              ref={fileInput}
              type="file"
              multiple
              hidden
              accept={SONG_FILE_EXTENSIONS.map((x) => `.${x}`).join(',')}
              onChange={(e) => {
                if (e.target.files) void addFiles(e.target.files)
                e.target.value = ''
              }}
            />
          </div>
        )}
        {notes.length > 0 && (
          <div className="note warn">
            {notes.map((n) => (
              <div key={n}>{n}</div>
            ))}
          </div>
        )}

        {entries.length > 0 && (
          <div className="stack-sm">
            <h3>Review</h3>
            <div className="import-head">
              <span>Title</span>
              <span>Authors</span>
              <span>CCLI #</span>
              <span>Sections</span>
              <span>What to do</span>
            </div>
            {plan.map(({ e, dup, act }) => (
              <div key={e.key} className={`import-row ${act === 'skip' ? 'skipped' : ''}`}>
                <label className="c-title">
                  <span className="lbl">Title</span>
                  <input style={{ width: '100%' }} value={e.song.title} onChange={(ev) => patchSong(e.key, { title: ev.target.value })} />
                </label>
                <label>
                  <span className="lbl">Authors</span>
                  <input style={{ width: '100%' }} value={e.song.authors} onChange={(ev) => patchSong(e.key, { authors: ev.target.value })} />
                </label>
                <label>
                  <span className="lbl">CCLI #</span>
                  <input style={{ width: '100%' }} value={e.song.ccli_number} onChange={(ev) => patchSong(e.key, { ccli_number: ev.target.value })} />
                </label>
                <span>
                  <span className="lbl">Sections</span>
                  {e.song.sections.length}
                </span>
                <label className="c-action">
                  <span className="lbl">What to do</span>
                  <select style={{ width: '100%' }} value={act} onChange={(ev) => patch(e.key, { action: ev.target.value as Action })}>
                    {dup ? (
                      <>
                        <option value="skip">Skip (already in the library)</option>
                        <option value="replace">Replace the existing song</option>
                        <option value="copy">Import as a copy</option>
                      </>
                    ) : (
                      <>
                        <option value="import">Import</option>
                        <option value="skip">Skip</option>
                      </>
                    )}
                  </select>
                </label>
                {(e.fileName || dup) && (
                  <div className="import-file">
                    {e.fileName && <span>{e.fileName}</span>}
                    {dup && <span className="dup-flag"> · Matches "{dup.title}" in your library</span>}
                  </div>
                )}
                <details>
                  <summary>
                    Sections found{e.song.copyright ? ` · ${e.song.copyright}` : ''}
                  </summary>
                  <pre>{e.song.sections.map((s) => `${s.label}: ${s.text.split('\n')[0]}${s.text.includes('\n') ? ' …' : ''}`).join('\n')}</pre>
                </details>
              </div>
            ))}
            <div className="row wrap">
              <button className="btn primary" onClick={save} disabled={saving || total === 0}>
                {saving ? 'Saving…' : total === 0 ? 'Nothing to save' : `Save ${total} ${total === 1 ? 'song' : 'songs'}`}
              </button>
              <button className="btn" onClick={() => setEntries([])} disabled={saving}>
                Clear
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
