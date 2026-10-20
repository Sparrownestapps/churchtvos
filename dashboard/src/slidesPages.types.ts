// Extra row types used by the Slides pages. The data shapes themselves (slides, backgrounds, themes) live in slidesTypes.ts.
import type { Media, MediaFolder } from './types'
import type { SongSection } from './songParsers'

/** The church's Slides media library (module = 'slides'), loaded once per page and shared with the pickers. */
export type SlidesLibrary = {
  media: Media[]
  folders: MediaFolder[]
  /** Re-reads the library (after an upload). */
  reload: () => void
}

/** What the deck editor needs to know about a library song (title slide + lyric preview + slide count). */
export type SongForSlides = {
  id: string
  title: string
  authors: string | null
  ccli_number: string | null
  copyright: string | null
  sections: SongSection[]
  arrangement: string[] | null
  lines_per_slide: number
}

/** A deck as listed in pickers (schedules, rotations). */
export type DeckRef = { id: string; name: string; site_id: string | null }
