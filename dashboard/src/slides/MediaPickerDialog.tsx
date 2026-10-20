import { useEffect, useMemo, useRef, useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import type { Media, MediaFolder } from '../types'
import type { SlidesLibrary } from '../slidesPages.types'
import { fmtBytes } from '../lib'
import { useDefaultScope } from '../ui'
import { OVERSIZE_VIDEO_BYTES } from './render'
import { uploadToSlidesLibrary } from './upload'

/** First frame of a video, loaded once it scrolls near the screen. */
export function VideoPoster({ url }: { url: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [on, setOn] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el || typeof IntersectionObserver === 'undefined') return setOn(true)
    const io = new IntersectionObserver(([e]) => e.isIntersecting && (setOn(true), io.disconnect()), { rootMargin: '200px' })
    io.observe(el)
    return () => io.disconnect()
  }, [])
  return (
    <div ref={ref} className="poster">
      {on && <video src={`${url}#t=0.5`} preload="metadata" muted playsInline />}
      <span className="play">▶</span>
    </div>
  )
}

export const oversize = (m: { kind: string; size_bytes: number | null }) => m.kind === 'video' && (m.size_bytes ?? 0) > OVERSIZE_VIDEO_BYTES

/**
 * Choose a file from the Slides media library: folders, search, thumbnails, and a quick Upload into the folder you are in.
 * (The full library is on Slides > Media.)
 */
export default function MediaPickerDialog({
  lib,
  kinds,
  value,
  title,
  onPick,
  onClose,
}: {
  lib: SlidesLibrary
  kinds: Media['kind'][]
  value?: string
  title: string
  onPick: (m: Media) => void
  onClose: () => void
}) {
  const { org, canEditContent } = useApp()
  const defaultScope = useDefaultScope()
  const [folderId, setFolderId] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [progress, setProgress] = useState<number | null>(null)
  const [error, setError] = useState<string | null>(null)
  const input = useRef<HTMLInputElement>(null)
  const closeRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    closeRef.current?.focus()
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])

  const byId = useMemo(() => new Map(lib.folders.map((f) => [f.id, f])), [lib.folders])
  const here = folderId && byId.has(folderId) ? folderId : null
  const current = here ? byId.get(here) : undefined
  const crumbs: MediaFolder[] = []
  for (let f = current; f && crumbs.length < 100; f = f.parent_id ? byId.get(f.parent_id) : undefined) crumbs.unshift(f)

  const q = search.trim().toLowerCase()
  const ofKind = lib.media.filter((m) => kinds.includes(m.kind))
  const subfolders = q ? [] : lib.folders.filter((f) => f.parent_id === here).sort((a, b) => a.name.localeCompare(b.name))
  const files = q
    ? ofKind.filter((m) => m.title.toLowerCase().includes(q))
    : ofKind.filter((m) => (m.folder_id && byId.has(m.folder_id) ? m.folder_id : null) === here)

  const uploadSite = current ? current.site_id : defaultScope
  const canUpload = canEditContent('slides', uploadSite)

  async function upload(file: File | undefined) {
    if (!file) return
    setError(null)
    setProgress(0)
    try {
      await uploadToSlidesLibrary({ file, orgId: org.id, folderId: here, siteId: uploadSite, onProgress: setProgress })
      lib.reload()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setProgress(null)
      if (input.current) input.current.value = ''
    }
  }

  const accept = kinds.map((k) => `${k}/*`).join(',')
  const label = kinds.length === 2 ? 'images or videos' : `${kinds[0]}s`

  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="card sl-picker stack-sm" role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="row spread">
          <h3>{title}</h3>
          <button ref={closeRef} className="link" onClick={onClose}>
            Cancel
          </button>
        </div>
        <div className="row wrap">
          <label className="field grow">
            <span>Search {label}</span>
            <input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Type part of a file name" />
          </label>
          {canUpload && (
            <>
              <button className="btn align-end" onClick={() => input.current?.click()} disabled={progress !== null}>
                {progress === null ? `Upload to ${current ? current.name : 'library'}` : `Uploading ${progress}%`}
              </button>
              <input ref={input} type="file" accept={accept} hidden onChange={(e) => upload(e.target.files?.[0])} />
            </>
          )}
        </div>
        {error && <p className="error">{error}</p>}
        <nav className="crumbs" aria-label="Folder">
          <button className="crumb" disabled={!here} onClick={() => setFolderId(null)}>
            Slides library
          </button>
          {crumbs.map((f, i) => (
            <span key={f.id}>
              ›{' '}
              <button className="crumb" disabled={i === crumbs.length - 1} onClick={() => setFolderId(f.id)}>
                {f.name}
              </button>
            </span>
          ))}
        </nav>
        <div className="sl-picker-body">
          <div className="sl-pick-grid">
            {subfolders.map((f) => (
              <button key={f.id} className="sl-pick-tile folder" onClick={() => setFolderId(f.id)}>
                <span className="folder-icon" aria-hidden="true">📁</span>
                <b>{f.name}</b>
              </button>
            ))}
            {files.map((m) => (
              <button key={m.id} className={`sl-pick-tile ${m.id === value ? 'on' : ''}`} onClick={() => onPick(m)} aria-pressed={m.id === value}>
                {m.kind === 'image' ? <img src={m.url} alt="" loading="lazy" draggable={false} /> : <VideoPoster url={m.url} />}
                <b>{m.title}</b>
                <span className="muted">
                  {m.kind === 'video' ? 'Video' : 'Image'} {fmtBytes(m.size_bytes)}
                </span>
                {oversize(m) && <span className="sl-warn-text">Large file (over 200 MB)</span>}
              </button>
            ))}
          </div>
          {subfolders.length === 0 && files.length === 0 && (
            <p className="muted">{q ? 'Nothing matches that search.' : `No ${label} here yet. ${canUpload ? 'Use Upload above.' : ''}`}</p>
          )}
        </div>
      </div>
    </div>
  )
}
