import type { DeckSlide, MediaSlide, TextSlide } from '../slidesTypes'
import type { PlaylistItem } from '../types'
import { newSlideId } from '../slides/render'

// The pure rules of the PDF / PowerPoint / picture importer: limits, names, and how imported pages become deck slides or
// Kids playlist items. Written down in PPTX-IMPORT-CONTRACT.md at the repository root; keep the two in step.

export const MAX_PAGES = 150
/** PDF or PowerPoint file size (the whole file is read into the browser's memory). */
export const MAX_DOCUMENT_BYTES = 150 * 1024 * 1024
/** One uploaded picture, video or audio file (the free Supabase plan refuses larger files). */
export const MAX_UPLOAD_BYTES = 50 * 1024 * 1024
export const IMAGE_FILE = /\.(png|jpe?g|webp|gif)$/i

export type SecondsChoice = number | null // null = wait for Next / the remote

/** Default time per page: decks are stepped through with the remote, Kids playlists move on by themselves. */
export const DEFAULT_SECONDS = { deck: null, playlist: 10 } as const

export const baseName = (file: string) => file.replace(/\.[^.]+$/, '').trim() || 'Imported'

/** 'Easter Sunday' + page 3 of 12 -> 'Easter Sunday 03.jpg'. The number keeps the page number in the source file. */
export function pageFileName(base: string, n: number, total: number, ext: string): string {
  const width = Math.max(2, String(total).length)
  return `${base} ${String(n).padStart(width, '0')}.${ext}`
}

export const naturalCompare = (a: string, b: string) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' })

/** Folder name for a set of picture files: their shared start ('Slide' from Slide1.png, Slide2.png), else a dated name. */
export function folderNameForImages(names: string[], today = new Date()): string {
  const bases = names.map(baseName)
  if (bases.length === 1) return bases[0]
  let prefix = bases[0] ?? ''
  for (const b of bases) while (prefix && !b.toLowerCase().startsWith(prefix.toLowerCase())) prefix = prefix.slice(0, -1)
  prefix = prefix.replace(/[\s\-_.\d]+$/, '').trim()
  return prefix.length >= 3 ? prefix : `Imported pictures ${today.toISOString().slice(0, 10)}`
}

/** What one imported page turned into, ready for the builders below. */
export type Entry =
  | { type: 'text'; title: string; body: string; notes?: string }
  | { type: 'image'; media_id: string; url: string; title: string; notes?: string }
  | { type: 'video'; media_id: string; url: string; title: string; notes?: string }

const BLACK = { type: 'color', color: '#000000' } as const

/** Deck slides for entries. Picture and video slides are 'contain' on a black background so the whole page shows. */
export function deckSlidesFrom(entries: Entry[], seconds: SecondsChoice, existing: { id: string }[]): DeckSlide[] {
  const out: DeckSlide[] = []
  for (const e of entries) {
    const id = newSlideId([...existing, ...out])
    if (e.type === 'text') {
      const layout = e.title && e.body ? 'title_body' : e.title ? 'title' : 'body'
      const s: TextSlide = { id, kind: 'text', title: e.title, body: e.body, layout, seconds }
      if (e.notes) s.notes = e.notes
      out.push(s)
    } else {
      const s: MediaSlide = {
        id,
        kind: 'media',
        media_id: e.media_id,
        url: e.url,
        media_kind: e.type,
        fit: 'contain',
        background: BLACK,
        ...(e.type === 'image' ? { seconds } : { audio: true }),
      }
      if (e.notes) s.notes = e.notes
      out.push(s)
    }
  }
  return out
}

/** Kids playlist items for entries (Kids has no text slide: the importer turns text into pictures first, so text entries are not expected here). Notes are not kept. */
export function playlistItemsFrom(entries: Entry[], seconds: SecondsChoice): PlaylistItem[] {
  const out: PlaylistItem[] = []
  for (const e of entries) {
    if (e.type === 'image') out.push({ type: 'image', title: e.title, url: e.url, media_id: e.media_id, seconds })
    else if (e.type === 'video') out.push({ type: 'video', title: e.title, url: e.url, media_id: e.media_id })
  }
  return out
}

/** Insert `add` into `list` at 0-based `at` (clamped), returning a new list. */
export function insertAt<T>(list: T[], at: number, add: T[]): T[] {
  const i = Math.max(0, Math.min(list.length, at))
  return [...list.slice(0, i), ...add, ...list.slice(i)]
}

/** Why a file cannot be imported, or null. */
export function fileProblem(file: File): string | null {
  if (/\.ppt$/i.test(file.name)) return 'Old .ppt files are not supported. In PowerPoint use File > Save As > PowerPoint Presentation (.pptx), or export to PDF.'
  if (/\.key$/i.test(file.name)) return 'Keynote files are not supported. In Keynote use File > Export To > PDF (or Images).'
  if (/\.(pdf|pptx)$/i.test(file.name) && file.size > MAX_DOCUMENT_BYTES) return `This file is ${Math.round(file.size / 1048576)} MB. The limit is ${MAX_DOCUMENT_BYTES / 1048576} MB. Export fewer slides, or a smaller PDF.`
  if (IMAGE_FILE.test(file.name) && file.size > MAX_UPLOAD_BYTES) return `This picture is over ${MAX_UPLOAD_BYTES / 1048576} MB.`
  if (!/\.(pdf|pptx)$/i.test(file.name) && !IMAGE_FILE.test(file.name)) return 'Choose a PDF, a PowerPoint (.pptx) or picture files (PNG, JPG).'
  return null
}
