import type { NdiConfig } from './types'

// Slides module data shapes. CONTRACT shared by the dashboard, the database function deck_expand() and the TV app.
// Do not change a field name or meaning without changing all three. See SLIDES-MODULE-PLAN.md.

/** A background layer. Resolution order for a slide: slide.background, then deck.background, then theme.background, then the default (church primary colour). */
export type SlideBackground =
  | { type: 'color'; color: string; dim?: number }
  | { type: 'gradient'; color: string; color2: string; angle?: number; dim?: number }
  | { type: 'image'; media_id: string; url: string; fit?: 'cover' | 'contain'; color?: string; dim?: number }
  | { type: 'video'; media_id: string; url: string; fit?: 'cover' | 'contain'; color?: string; dim?: number }
// dim: 0..0.8 black overlay that keeps text readable on busy backgrounds. color: fill behind a 'contain' image/video.

export type SlideLayout = 'title_body' | 'title' | 'body' | 'lower_third'

type SlideBase = {
  id: string // unique within the deck, e.g. 's_k3f9a'
  background?: SlideBackground | null // override for this slide only
  notes?: string // private to the dashboard, never sent to the TV
}

export type TextSlide = SlideBase & {
  kind: 'text'
  title?: string
  body?: string
  layout?: SlideLayout // default 'title_body'
  align?: 'left' | 'center' // default from theme
  text_color?: string // '#RRGGBB', default from theme
  seconds?: number | null // null/absent = waits for Next on the TV remote
}

export type MediaSlide = SlideBase & {
  kind: 'media'
  media_id: string
  url: string
  media_kind: 'image' | 'video'
  fit?: 'contain' | 'cover' // default 'contain'
  seconds?: number | null // images only: auto-advance after N seconds; null = wait. Videos advance when they end.
  audio?: boolean // videos only, default true
}

export type SongSlide = SlideBase & {
  kind: 'song'
  song_id: string
  show_title?: boolean // a styled title slide first; holds until Next
}

/** Audio that plays during a countdown. A file from the media library (media.kind = 'audio'). */
export type CountdownAudio = {
  media_id: string
  url: string
  volume?: number // 0..1, default 0.8
  loop?: boolean // repeat until zero, default true (ignored when align_end is on and the track is shorter than the countdown)
  fade_seconds?: number // fade out over the last N seconds, default 3
  align_end?: boolean // start late so the track finishes exactly at zero, default false
}

/**
 * Countdown, shared by Slides decks and Kids playlists (Kids uses {type:'countdown'} with the same extra fields).
 * mode 'duration' (default): counts down `seconds` from when the slide appears.
 * mode 'until': counts down to the clock time `until` ('HH:MM', 24h) in the site's time zone, today.
 */
export type CountdownSlide = SlideBase & {
  kind: 'countdown'
  title?: string
  mode?: 'duration' | 'until'
  seconds?: number // duration mode
  until?: string // until mode, 'HH:MM'
  audio?: CountdownAudio | null
  at_zero?: 'next' | 'hold' // NEW countdowns are saved with 'hold' (stay on 0:00 until the leader presses Next). A field that is missing (older Kids items) means 'next' (move on automatically), which is how those items always behaved.
  if_passed?: 'skip' | 'zero' // until mode, when the time has already passed: 'zero' (default for new items) shows 0:00 and then follows at_zero; 'skip' leaves the slide out
}

export type StreamSlide = SlideBase & {
  kind: 'stream'
  title?: string
  url: string // HLS (.m3u8)
  audio?: boolean
  fallback?: 'skip' | 'hold'
  seconds?: number | null
}

/** EXPERIMENTAL NDI source. Same fields as the Kids item; see NdiConfig in types.ts and NDI-CONTRACT.md. Only saved when the church has the flag. */
export type NdiSlide = SlideBase & { kind: 'ndi'; title?: string } & NdiConfig

export type BlankSlide = SlideBase & {
  kind: 'blank'
  color?: string // default '#000000'
}

export type DeckSlide = TextSlide | MediaSlide | SongSlide | CountdownSlide | StreamSlide | NdiSlide | BlankSlide

/** slide_themes.config */
export type ThemeConfig = {
  font?: 'lato' | 'julius' // body font; titles use 'julius' when set to it
  title_scale?: number // 0.5 - 1.5, default 1
  body_scale?: number // 0.5 - 1.5, default 1
  text_color?: string // default '#FFFFFF'
  align?: 'left' | 'center' // default 'center'
  position?: 'center' | 'lower' | 'top' // vertical placement of text, default 'center'
  shadow?: boolean // default true
  outline?: boolean // default false
  margin?: number // percent of the screen kept clear around text, 0-20, default 8
  background?: SlideBackground
  show_labels?: boolean // small section label on lyric slides, default true
  logo?: { show: boolean; position: 'bottom_left' | 'bottom_right' | 'top_left' | 'top_right' } // the church logo, default hidden
}

export type SlideTheme = {
  id: string
  organization_id: string
  name: string
  config: ThemeConfig
  created_at: string
  updated_at: string
}

export type Deck = {
  id: string
  organization_id: string
  site_id: string | null
  name: string
  theme_id: string | null
  background: SlideBackground | null // deck default (beats the theme's)
  slides: DeckSlide[]
  loops: boolean // start over after the last slide (database column 'loops')
  created_at: string
  updated_at: string
}

export type DeckSchedule = {
  id: string
  organization_id: string
  location_id: string
  deck_id: string
  starts_at: string
  ends_at: string | null
  created_at: string
}

/** Repeating schedule with a rotation of decks (same rules as Kids series: skip waits, override uses its place). */
export type DeckSeries = {
  id: string
  organization_id: string
  location_id: string
  name: string | null
  days: number[]
  start_time: string
  end_time: string
  start_date: string
  end_date: string | null
  deck_ids: string[]
  on_end: 'stop' | 'loop'
  created_at: string
}

export type DeckSeriesException = {
  series_id: string
  on_date: string
  action: 'skip' | 'deck'
  deck_id: string | null
}

/** Row returned by the RPC deck_series_occurrences(p_org, p_from, p_to, p_location). */
export type DeckOccurrence = {
  series_id: string
  location_id: string
  on_date: string
  starts_at: string
  ends_at: string
  deck_id: string
  occurrence_no: number
  is_override: boolean
}
