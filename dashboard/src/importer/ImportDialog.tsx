import { useCallback, useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import './import.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { DeckSlide } from '../slidesTypes'
import type { Media, PlaylistItem } from '../types'
import { fmtBytes, isHex, must } from '../lib'
import { ScopeSelect, useDefaultScope } from '../ui'
import { helpUrl } from '../links'
import {
  DEFAULT_SECONDS,
  MAX_PAGES,
  MAX_UPLOAD_BYTES,
  baseName,
  deckSlidesFrom,
  fileProblem,
  folderNameForImages,
  naturalCompare,
  pageFileName,
  playlistItemsFrom,
  type Entry,
  type SecondsChoice,
} from './importLogic'
import { mainPicture, parsePptx, pptxFile, type Pptx, type PptxMedia, type PptxSlide } from './pptx'
import type { PdfInfo } from './pdf'
import { createImportFolder, uploadMedia } from './uploadMedia'

type Source = { kind: 'pdf'; file: File; info: PdfInfo } | { kind: 'pptx'; file: File; pptx: Pptx } | { kind: 'images'; files: File[] }

type Row = {
  key: string
  checked: boolean
  enabled: boolean
  label: string
  sub: string
  thumb?: string
  ref: { t: 'pdf'; page: number } | { t: 'file'; file: File } | { t: 'pptx'; slide: PptxSlide }
}

type Status = { key: string; label: string; state: 'wait' | 'busy' | 'ok' | 'fail' | 'skip'; message?: string; percent?: number }

type Where = 'append' | 'insert' | 'new'

/** Where the imported things go when the dialog is opened from inside an editor. */
export type ImportTarget = {
  /** How many slides/items the editor has now */
  count: number
  /** Existing slides (for unique slide ids). Empty for playlists. */
  existing: { id: string }[]
  /** Site the deck/playlist belongs to (media and the folder get the same site limit) */
  scope: string | null
  /** The editor's current 0-based selected position + 1, used as the default for "insert after" */
  after: number
  add: (items: DeckSlide[] | PlaylistItem[], at: number) => void
}

const SECONDS = [5, 10, 15, 20, 30, 45, 60, 120]
const firstLine = (s: string) => s.split('\n').find((l) => l.trim())?.trim() ?? ''
const POOL = 3

async function pool<T>(count: number, size: number, fn: (i: number) => Promise<T>, stop: () => boolean): Promise<void> {
  let next = 0
  const worker = async () => {
    for (;;) {
      if (stop()) return
      const i = next++
      if (i >= count) return
      await fn(i)
    }
  }
  await Promise.all(Array.from({ length: Math.min(size, count) }, worker))
}

export default function ImportDialog({
  mode,
  target,
  onClose,
  onCreated,
}: {
  /** 'deck' = Slides decks (module slides), 'playlist' = Kids playlists (module kids) */
  mode: 'deck' | 'playlist'
  /** Inside an editor: add to it (or make a new one). Absent on a list page: always makes a new one. */
  target?: ImportTarget
  onClose: () => void
  /** A new deck/playlist row was made */
  onCreated?: () => void
}) {
  const { org, canEditContent, moduleOn } = useApp()
  const module = mode === 'deck' ? 'slides' : 'kids'
  const noun = mode === 'deck' ? 'deck' : 'playlist'
  const defaultScope = useDefaultScope()

  const [step, setStep] = useState<'choose' | 'loading' | 'review' | 'importing' | 'done'>('choose')
  const [problem, setProblem] = useState<string | null>(null)
  const [source, setSource] = useState<Source | null>(null)
  const [rows, setRows] = useState<Row[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const [seconds, setSeconds] = useState<SecondsChoice>(DEFAULT_SECONDS[mode])
  const [where, setWhere] = useState<Where>(target ? 'append' : 'new')
  const [after, setAfter] = useState(target ? Math.min(target.count, Math.max(0, target.after)) : 0)
  const [newName, setNewName] = useState('')
  const [folderName, setFolderName] = useState('')
  const [scope, setScope] = useState<string | null>(target ? target.scope : defaultScope)
  const [mediaOn, setMediaOn] = useState<Set<string>>(new Set())
  const [withPictures, setWithPictures] = useState(false)
  const [statuses, setStatuses] = useState<Status[]>([])
  const [summary, setSummary] = useState<string | null>(null)
  const [dropping, setDropping] = useState(false)

  const urls = useRef<string[]>([])
  const alive = useRef(true)
  const cancel = useRef(false)
  const abort = useRef<AbortController | null>(null)
  const pdfRef = useRef<PdfInfo | null>(null)
  const input = useRef<HTMLInputElement>(null)
  const closeRef = useRef<HTMLButtonElement>(null)
  const importing = step === 'importing'

  const siteScope = target ? target.scope : scope
  const allowed = moduleOn(module) && canEditContent(module, siteScope)

  useEffect(() => {
    alive.current = true
    closeRef.current?.focus()
    return () => {
      alive.current = false
      cancel.current = true
      urls.current.forEach((u) => URL.revokeObjectURL(u))
      pdfRef.current?.doc.loadingTask.destroy().catch(() => {})
    }
  }, [])

  const close = useCallback(() => {
    if (importing && !confirm('Stop the import? Pages already uploaded stay in your media library.')) return
    cancel.current = true
    abort.current?.abort()
    onClose()
  }, [importing, onClose])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [close])

  const objectUrl = (b: Blob) => {
    const u = URL.createObjectURL(b)
    urls.current.push(u)
    return u
  }

  // ───────── Choosing and reading the file ─────────

  async function pick(list: FileList | File[]) {
    const files = Array.from(list)
    if (!files.length) return
    setProblem(null)
    for (const f of files) {
      const p = fileProblem(f)
      if (p) return setProblem(`${f.name}: ${p}`)
    }
    const docs = files.filter((f) => /\.(pdf|pptx)$/i.test(f.name))
    if (docs.length > 1 || (docs.length === 1 && files.length > 1)) return setProblem('Import one PDF or PowerPoint at a time, or several picture files together.')
    setStep('loading')
    try {
      if (docs.length === 0) return loadImages(files)
      const file = docs[0]
      if (/\.pdf$/i.test(file.name)) await loadPdf(file)
      else await loadPptx(file)
    } catch (e) {
      if (!alive.current) return
      setProblem((e as Error).message)
      setStep('choose')
    }
  }

  function loadImages(files: File[]) {
    const sorted = [...files].sort((a, b) => naturalCompare(a.name, b.name))
    const capped = sorted.slice(0, MAX_PAGES)
    setNotice(sorted.length > MAX_PAGES ? `You chose ${sorted.length} pictures. Only the first ${MAX_PAGES} can be imported at a time; import the rest in another go.` : null)
    setSource({ kind: 'images', files: capped })
    setFolderName(folderNameForImages(capped.map((f) => f.name)))
    setNewName(folderNameForImages(capped.map((f) => f.name)))
    setRows(
      capped.map((f, i) => ({ key: `i${i}`, checked: true, enabled: true, label: baseName(f.name), sub: fmtBytes(f.size), thumb: objectUrl(f), ref: { t: 'file', file: f } })),
    )
    setStep('review')
  }

  async function loadPdf(file: File) {
    const { openPdf, renderThumb } = await import('./pdf')
    const info = await openPdf(await file.arrayBuffer())
    if (!alive.current) return void info.doc.loadingTask.destroy()
    pdfRef.current = info
    const n = Math.min(info.numPages, MAX_PAGES)
    setNotice(info.numPages > MAX_PAGES ? `This PDF has ${info.numPages} pages. Only the first ${MAX_PAGES} can be imported at a time; split the PDF to import the rest.` : null)
    setSource({ kind: 'pdf', file, info })
    setFolderName(baseName(file.name))
    setNewName(baseName(file.name))
    setRows(Array.from({ length: n }, (_, i) => ({ key: `p${i + 1}`, checked: true, enabled: true, label: `Page ${i + 1}`, sub: '', ref: { t: 'pdf' as const, page: i + 1 } })))
    setStep('review')
    // Thumbnails one at a time, so a big PDF does not freeze the page.
    for (let p = 1; p <= n; p++) {
      if (!alive.current) return
      try {
        const u = await renderThumb(info, p)
        urls.current.push(u)
        if (!alive.current) return
        setRows((list) => list.map((r) => (r.key === `p${p}` ? { ...r, thumb: u } : r)))
      } catch {
        /* a page that cannot be previewed is reported when it is imported */
      }
    }
  }

  async function loadPptx(file: File) {
    const pptx = await parsePptx(file)
    if (!alive.current) return
    if (pptx.slides.length === 0) throw new Error('This PowerPoint has no slides.')
    const slides = pptx.slides.slice(0, MAX_PAGES)
    setNotice(pptx.slides.length > MAX_PAGES ? `This PowerPoint has ${pptx.slides.length} slides. Only the first ${MAX_PAGES} can be imported at a time.` : null)
    setSource({ kind: 'pptx', file, pptx })
    setFolderName(baseName(file.name))
    setNewName(baseName(file.name))
    const media = new Set<string>()
    const out: Row[] = slides.map((s) => {
      const pic = mainPicture(s)
      const enabled = s.kind !== 'empty' || s.media.some((m) => m.supported)
      for (const m of s.media) if (m.supported && (m.size ?? 0) <= MAX_UPLOAD_BYTES) media.add(m.path)
      const bits = [
        s.hidden ? 'Hidden slide' : '',
        s.notes ? 'speaker notes' : '',
        s.kind === 'picture' ? (pic ? 'picture slide' : 'picture format not supported') : '',
        s.kind === 'empty' && !enabled ? 'nothing to import' : '',
      ].filter(Boolean)
      return {
        key: `s${s.number}`,
        checked: enabled && !s.hidden,
        enabled,
        label: `${s.number}. ${s.title ? firstLine(s.title) : firstLine(s.body) || (s.kind === 'picture' ? 'Picture' : 'Empty slide')}`,
        sub: bits.join(' · '),
        ref: { t: 'pptx' as const, slide: s },
      }
    })
    setMediaOn(media)
    setRows(out)
    setStep('review')
    // Previews for picture-only slides.
    for (const s of slides) {
      const pic = s.kind === 'picture' ? mainPicture(s) : null
      if (!pic) continue
      try {
        const blob = await pptx.zip.file(pic.path)!.async('blob')
        if (!alive.current) return
        const u = objectUrl(new Blob([blob], { type: pic.ext === 'jpg' ? 'image/jpeg' : `image/${pic.ext}` }))
        setRows((list) => list.map((r) => (r.key === `s${s.number}` ? { ...r, thumb: u } : r)))
      } catch {
        /* no preview */
      }
    }
  }

  // ───────── Review list ─────────

  const move = (i: number, by: number) =>
    setRows((list) => {
      const j = i + by
      if (j < 0 || j >= list.length) return list
      const next = [...list]
      ;[next[i], next[j]] = [next[j], next[i]]
      return next
    })
  const toggle = (key: string) => setRows((list) => list.map((r) => (r.key === key && r.enabled ? { ...r, checked: !r.checked } : r)))
  const setAll = (on: boolean) => setRows((list) => list.map((r) => ({ ...r, checked: r.enabled && on })))
  const chosen = rows.filter((r) => r.checked)

  const allMedia = useMemo(() => {
    if (source?.kind !== 'pptx') return [] as { slide: PptxSlide; m: PptxMedia }[]
    return rows.flatMap((r) => (r.ref.t === 'pptx' ? r.ref.slide.media.map((m) => ({ slide: (r.ref as { slide: PptxSlide }).slide, m })) : []))
  }, [rows, source])

  // ───────── Importing ─────────

  async function run() {
    if (!source || !allowed) return
    const name = newName.trim()
    if (where === 'new' && !name) return alert(`Give the new ${noun} a name.`)
    if (chosen.length === 0) return alert('Tick at least one page to import.')
    cancel.current = false
    abort.current = new AbortController()
    const signal = abort.current.signal
    setSummary(null)
    const pptx = source.kind === 'pptx' ? source.pptx : null
    const base = source.kind === 'images' ? 'Imported' : baseName(source.file.name)
    const total = source.kind === 'pdf' ? source.info.numPages : 0
    const brandColor = isHex(org.branding.primary_color) ? org.branding.primary_color : '#1f3a5f'

    // Plan: one job per ticked row, in order. Each job gives entries (in order) for the new slides/items.
    type Job = { row: Row; statusKey: string }
    const jobs: Job[] = chosen.map((row) => ({ row, statusKey: row.key }))
    setStatuses(jobs.map((j) => ({ key: j.statusKey, label: j.row.label, state: 'wait' })))
    setStep('importing')

    const patch = (key: string, change: Partial<Status>) => setStatuses((l) => l.map((s) => (s.key === key ? { ...s, ...change } : s)))
    const results: Entry[][] = jobs.map(() => [])
    const failures: string[] = []

    let folderPromise: Promise<{ id: string; name: string }> | null = null
    const folder = () => (folderPromise ??= createImportFolder({ orgId: org.id, module, siteId: siteScope, wanted: folderName.trim() || base }))
    const upload = async (file: File, key: string): Promise<Media> => {
      const f = await folder()
      return uploadMedia({ file, orgId: org.id, module, folderId: f.id, siteId: siteScope, signal, onProgress: (p) => patch(key, { percent: p }) })
    }

    await pool(
      jobs.length,
      POOL,
      async (i) => {
        const { row, statusKey } = jobs[i]
        patch(statusKey, { state: 'busy', percent: 0 })
        const entries: Entry[] = []
        const note: string[] = []
        try {
          if (row.ref.t === 'pdf') {
            const { renderPageFile } = await import('./pdf')
            const page = row.ref.page
            const file = await renderPageFile(source.kind === 'pdf' ? source.info : pdfRef.current!, page, pageFileName(base, page, total, 'jpg'))
            const m = await upload(file, statusKey)
            entries.push({ type: 'image', media_id: m.id, url: m.url, title: m.title })
          } else if (row.ref.t === 'file') {
            const m = await upload(row.ref.file, statusKey)
            entries.push({ type: 'image', media_id: m.id, url: m.url, title: m.title })
          } else if (pptx) {
            const s = row.ref.slide
            const nn = pageFileName(base, s.number, pptx.slides.length, '').slice(0, -1) // 'Name 03'
            const notes = mode === 'deck' && s.notes ? s.notes : undefined
            const addPicture = async (path: string, ext: string, suffix: string, notesFor?: string) => {
              const file = await pptxFile(pptx.zip, path, `${nn}${suffix}.${ext}`)
              if (file.size > MAX_UPLOAD_BYTES) throw new Error(`The picture is over ${MAX_UPLOAD_BYTES / 1048576} MB.`)
              const m = await upload(file, statusKey)
              entries.push({ type: 'image', media_id: m.id, url: m.url, title: m.title, notes: notesFor })
            }
            if (s.kind === 'text') {
              if (mode === 'deck') {
                entries.push({ type: 'text', title: s.title, body: s.body, notes })
              } else {
                const { renderTextSlideFile } = await import('./pdf')
                const file = await renderTextSlideFile({ title: s.title, body: s.body, background: brandColor, aspect: pptx.aspect, name: `${nn}.jpg` })
                const m = await upload(file, statusKey)
                entries.push({ type: 'image', media_id: m.id, url: m.url, title: m.title })
              }
              if (withPictures) {
                let k = 0
                for (const p of s.pictures.filter((x) => x.supported)) await addPicture(p.path, p.ext, ` picture ${++k}`)
              }
            } else if (s.kind === 'picture') {
              const p = mainPicture(s)
              if (!p) throw new Error(`The picture is in a format that can't be imported (${s.pictures[0]?.ext || s.bgPicture?.ext || 'unknown'}). Export the slides as PNG pictures from PowerPoint instead.`)
              await addPicture(p.path, p.ext, '', notes)
            }
            for (const m of s.media) {
              if (!mediaOn.has(m.path)) continue
              const file = await pptxFile(pptx.zip, m.path, `${nn} ${m.path.split('/').pop()}`)
              if (file.size > MAX_UPLOAD_BYTES) {
                note.push(`${m.path.split('/').pop()} is over ${MAX_UPLOAD_BYTES / 1048576} MB and was not imported`)
                continue
              }
              const mm = await upload(file, statusKey)
              if (m.kind === 'video') entries.push({ type: 'video', media_id: mm.id, url: mm.url, title: mm.title })
              else note.push(`${mm.title} added to the media library`)
            }
          }
          results[i] = entries
          patch(statusKey, { state: 'ok', percent: 100, message: note.join('; ') || undefined })
        } catch (e) {
          const msg = (e as Error).message
          results[i] = entries // keep what did succeed
          if (cancel.current && msg === 'Cancelled') patch(statusKey, { state: 'skip', message: 'Stopped' })
          else {
            failures.push(`${row.label}: ${msg}`)
            patch(statusKey, { state: 'fail', message: msg })
          }
        }
      },
      () => cancel.current,
    )

    if (!alive.current) return
    const entries = results.flat()
    setStatuses((l) => l.map((s) => (s.state === 'wait' ? { ...s, state: 'skip', message: 'Not imported' } : s)))
    if (entries.length === 0) {
      setSummary(cancel.current ? 'Stopped before anything was added.' : 'Nothing could be imported. See the messages above.')
      return setStep('done')
    }
    try {
      const noun2 = mode === 'deck' ? 'slide' : 'item'
      const plural = (n: number) => `${n} ${noun2}${n === 1 ? '' : 's'}`
      if (where === 'new' || !target) {
        const items = mode === 'deck' ? deckSlidesFrom(entries, seconds, []) : playlistItemsFrom(entries, seconds)
        must(
          mode === 'deck'
            ? await supabase.from('decks').insert({ organization_id: org.id, site_id: siteScope, name, theme_id: null, background: null, slides: items, loops: false })
            : await supabase.from('playlists').insert({ organization_id: org.id, site_id: siteScope, name, items }),
        )
        onCreated?.()
        setSummary(`Created the ${noun} "${name}" with ${plural(items.length)}. ${target ? `Find it on the ${mode === 'deck' ? 'Decks' : 'Playlists'} page.` : ''}`)
      } else {
        const at = where === 'append' ? target.count : after
        const items = mode === 'deck' ? deckSlidesFrom(entries, seconds, target.existing) : playlistItemsFrom(entries, seconds)
        target.add(items, at)
        setSummary(`Added ${plural(items.length)} ${where === 'append' ? 'at the end' : `after position ${at}`}. They are in the editor now: press Save to keep them.`)
      }
      if (failures.length) setSummary((s) => `${s} ${failures.length} could not be imported.`)
      if (cancel.current) setSummary((s) => `Stopped early. ${s}`)
    } catch (e) {
      setSummary(`The pictures were uploaded to your media library, but the ${noun} could not be saved: ${(e as Error).message}`)
    }
    setStep('done')
  }

  // ───────── Rendering ─────────

  const onDrop = (e: DragEvent) => {
    e.preventDefault()
    setDropping(false)
    void pick(e.dataTransfer.files)
  }

  const pdfOrImages = source?.kind !== 'pptx'
  const overall = statuses.length ? Math.round((statuses.filter((s) => s.state === 'ok' || s.state === 'fail' || s.state === 'skip').length / statuses.length) * 100) : 0

  return (
    <div className="modal-scrim" onClick={importing ? undefined : close}>
      <div className="card imp stack-sm" role="dialog" aria-modal="true" aria-label={`Import into a ${noun}`} onClick={(e) => e.stopPropagation()}>
        <div className="row spread">
          <h3>Import PDF, PowerPoint or pictures</h3>
          <button ref={closeRef} className="link" onClick={close}>
            {step === 'done' ? 'Close' : 'Cancel'}
          </button>
        </div>

        {!allowed && <p className="note warn">You need the {module === 'slides' ? 'Slides' : 'Kids'} module and an editor role to import here.</p>}

        {step === 'choose' && (
          <>
            <div
              className={`imp-drop ${dropping ? 'on' : ''}`}
              onDragOver={(e) => (e.preventDefault(), setDropping(true))}
              onDragLeave={() => setDropping(false)}
              onDrop={onDrop}
            >
              <p>
                <b>Drop a file here</b>, or
              </p>
              <button className="btn primary" onClick={() => input.current?.click()} disabled={!allowed}>
                Choose a file
              </button>
              <input
                ref={input}
                type="file"
                hidden
                multiple
                accept=".pdf,.pptx,application/pdf,image/png,image/jpeg,image/webp,image/gif"
                onChange={(e) => (void pick(e.target.files ?? []), (e.target.value = ''))}
              />
              <p className="muted">A PDF (every page becomes a full-screen picture), a PowerPoint .pptx (text becomes {mode === 'deck' ? 'editable text slides' : 'pictures of the text'}), or several PNG/JPG pictures at once.</p>
            </div>
            {problem && (
              <p className="error" role="alert">
                {problem}
              </p>
            )}
            <div className="note">
              <b>For the exact look of a PowerPoint,</b> in PowerPoint choose <b>File &gt; Export &gt; PDF</b> (or <b>PNG images</b>) and import that. A PDF keeps your fonts, layout and pictures exactly, but not animations or video.{' '}
              <a href={helpUrl(mode === 'deck' ? 'slides' : 'kids')} target="_blank" rel="noreferrer">
                More help
              </a>
            </div>
            <p className="help">
              Up to {MAX_PAGES} pages per import. Files up to 150 MB. Each picture or video uploaded must be under {MAX_UPLOAD_BYTES / 1048576} MB.
            </p>
          </>
        )}

        {step === 'loading' && <p className="muted" role="status">Reading the file…</p>}

        {step === 'review' && source && (
          <div className="imp-body stack-sm">
            <p>
              <b>{source.kind === 'images' ? `${source.files.length} pictures` : source.file.name}</b>
              {source.kind === 'pdf' && <span className="muted"> · {source.info.numPages} pages</span>}
              {source.kind === 'pptx' && <span className="muted"> · {source.pptx.slides.length} slides</span>}
            </p>
            {notice && <p className="note warn">{notice}</p>}

            {source.kind === 'pptx' && (
              <div className="note">
                {mode === 'deck' ? (
                  <>
                    <b>Editable:</b> each slide becomes a text slide (title and words) in your deck's theme; a slide that is only a picture becomes a picture slide; speaker notes go into the slide's notes. Layout, fonts, shapes, charts and animations are not kept.
                  </>
                ) : (
                  <>
                    Kids playlists have no text slide, so each slide's title and words are drawn onto a picture in your church colour. Slides that are only a picture keep their picture. Speaker notes are not kept.
                  </>
                )}{' '}
                <b>For the exact look,</b> export from PowerPoint with File &gt; Export &gt; PDF (or PNG images) and import that instead.
              </div>
            )}

            <div className="row wrap">
              <button className="btn" onClick={() => setAll(true)}>
                Select all
              </button>
              <button className="btn" onClick={() => setAll(false)}>
                Select none
              </button>
              <span className="muted">
                {chosen.length} of {rows.length} ticked
              </span>
            </div>

            <ul className="imp-list" aria-label="Pages to import">
              {rows.map((r, i) => (
                <li key={r.key} className={`imp-row ${r.checked ? '' : 'off'}`}>
                  <label className="imp-check">
                    <input type="checkbox" checked={r.checked} disabled={!r.enabled} onChange={() => toggle(r.key)} aria-label={`Import ${r.label}`} />
                  </label>
                  <div className="imp-thumb">
                    {r.thumb ? (
                      <img src={r.thumb} alt="" loading="lazy" />
                    ) : r.ref.t === 'pptx' && r.ref.slide.kind === 'text' ? (
                      <div className="imp-text-thumb">
                        <b>{firstLine(r.ref.slide.title)}</b>
                        <span>{r.ref.slide.body.split('\n').slice(0, 4).join('\n')}</span>
                      </div>
                    ) : (
                      <span className="muted">{r.ref.t === 'pdf' ? '…' : ''}</span>
                    )}
                  </div>
                  <div className="imp-main">
                    <span className="imp-label">{r.label}</span>
                    {r.sub && <span className="muted">{r.sub}</span>}
                  </div>
                  <span className="imp-move">
                    <button className="icon" onClick={() => move(i, -1)} disabled={i === 0} title="Move up" aria-label={`Move ${r.label} up`}>
                      ↑
                    </button>
                    <button className="icon" onClick={() => move(i, 1)} disabled={i === rows.length - 1} title="Move down" aria-label={`Move ${r.label} down`}>
                      ↓
                    </button>
                  </span>
                </li>
              ))}
            </ul>

            {source.kind === 'pptx' && allMedia.length > 0 && (
              <fieldset className="imp-media stack-sm">
                <legend>Videos and audio inside the PowerPoint</legend>
                {allMedia.map(({ slide, m }, i) => {
                  const big = (m.size ?? 0) > MAX_UPLOAD_BYTES
                  const ok = m.supported && !m.external && !big
                  const name = m.external ?? m.path.split('/').pop()
                  return (
                    <label key={`${slide.number}-${m.path || m.external}-${i}`} className="check">
                      <input
                        type="checkbox"
                        disabled={!ok}
                        checked={ok && mediaOn.has(m.path)}
                        onChange={(e) =>
                          setMediaOn((set) => {
                            const next = new Set(set)
                            if (e.target.checked) next.add(m.path)
                            else next.delete(m.path)
                            return next
                          })
                        }
                      />
                      <span>
                        Slide {slide.number}: {name} {m.size != null && <span className="muted">({fmtBytes(m.size)})</span>}{' '}
                        {m.external ? <span className="muted">online video: add it with a Live stream or YouTube item instead</span> : null}
                        {!m.external && !m.supported && <span className="muted">format not supported on the TV (use MP4)</span>}
                        {big && <span className="muted">over {MAX_UPLOAD_BYTES / 1048576} MB: too large to import, compress it and add it from the library</span>}
                        {ok && m.kind === 'audio' && <span className="muted">added to the media library only</span>}
                        {ok && m.kind === 'video' && <span className="muted">becomes a video {mode === 'deck' ? 'slide' : 'item'} after its slide</span>}
                      </span>
                    </label>
                  )
                })}
              </fieldset>
            )}

            {source.kind === 'pptx' && mode === 'deck' && (
              <label className="check">
                <input type="checkbox" checked={withPictures} onChange={(e) => setWithPictures(e.target.checked)} />
                Also add the pictures from text slides, as extra picture slides after them
              </label>
            )}

            <div className="imp-opts">
              <label className="field">
                <span>Time per {mode === 'deck' ? 'slide' : 'page'}</span>
                <select value={seconds ?? ''} onChange={(e) => setSeconds(e.target.value ? Number(e.target.value) : null)}>
                  <option value="">{mode === 'deck' ? 'Wait for Next on the remote' : 'Wait for the remote'}</option>
                  {SECONDS.map((s) => (
                    <option key={s} value={s}>
                      {s} seconds
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>Add to</span>
                <select value={where} onChange={(e) => setWhere(e.target.value as Where)}>
                  {target && <option value="append">The end of this {noun}</option>}
                  {target && target.count > 0 && <option value="insert">After a position in this {noun}</option>}
                  <option value="new">A new {noun}</option>
                </select>
              </label>
              {where === 'insert' && target && (
                <label className="field">
                  <span>After {mode === 'deck' ? 'slide' : 'item'} number</span>
                  <input type="number" min={0} max={target.count} value={after} onChange={(e) => setAfter(Math.max(0, Math.min(target.count, Number(e.target.value) || 0)))} />
                </label>
              )}
              {where === 'new' && (
                <>
                  <label className="field grow">
                    <span>New {noun} name</span>
                    <input value={newName} onChange={(e) => setNewName(e.target.value)} />
                  </label>
                  {!target && (
                    <label className="field">
                      <span>Available to</span>
                      <ScopeSelect value={scope} onChange={setScope} />
                    </label>
                  )}
                </>
              )}
              <label className="field grow">
                <span>Media folder (in the {module === 'slides' ? 'Slides' : 'Kids'} library)</span>
                <input value={folderName} onChange={(e) => setFolderName(e.target.value)} />
              </label>
            </div>
            {pdfOrImages && (
              <p className="help">
                Every {source.kind === 'pdf' ? 'page is drawn' : 'picture is uploaded'} as a {mode === 'deck' ? 'full-screen picture slide, shown whole on black' : 'picture item'}.
                {source.kind === 'pdf' && ' Pages are drawn at up to 1920 pixels on the long edge.'}
              </p>
            )}
            <div className="row wrap">
              <button className="btn primary" onClick={run} disabled={!allowed || chosen.length === 0}>
                Import {chosen.length} {mode === 'deck' ? 'slide' : 'page'}
                {chosen.length === 1 ? '' : 's'}
              </button>
              <button className="btn" onClick={close}>
                Cancel
              </button>
            </div>
          </div>
        )}

        {(step === 'importing' || step === 'done') && (
          <div className="imp-body stack-sm">
            <progress value={overall} max={100} aria-label="Import progress" />
            <ul className="imp-list" aria-live="polite">
              {statuses.map((s) => (
                <li key={s.key} className={`imp-status ${s.state}`}>
                  <span className="imp-label">{s.label}</span>
                  <span className="muted">
                    {s.state === 'wait' && 'Waiting'}
                    {s.state === 'busy' && `Working${s.percent ? ` ${s.percent}%` : '…'}`}
                    {s.state === 'ok' && (s.message ? `Done · ${s.message}` : 'Done')}
                    {s.state === 'fail' && <span className="error">Failed: {s.message}</span>}
                    {s.state === 'skip' && (s.message ?? 'Skipped')}
                  </span>
                </li>
              ))}
            </ul>
            {summary && (
              <p className="note" role="status">
                {summary}
              </p>
            )}
            {importing ? (
              <button
                className="btn"
                onClick={() => {
                  cancel.current = true
                  abort.current?.abort()
                }}
              >
                Stop
              </button>
            ) : (
              <div className="row">
                <button className="btn primary" onClick={onClose}>
                  Done
                </button>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
