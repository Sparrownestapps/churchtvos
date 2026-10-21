import type { SongSection } from './songParsers'
import type { CountdownAudio } from './slidesTypes'

/** An application id from the `modules` table ('kids', 'signage', ...). */
export type Module = string

/** One row of the `modules` registry. */
export type ModuleDef = { id: Module; name: string; sort: number; available: boolean }
export type Role = 'owner' | 'admin' | 'editor' | 'operator'
export type ScreenModule = Module | 'off'
export type Orientation = 'landscape' | 'portrait' | 'portrait_flipped'

export type SplashSettings = {
  enabled?: boolean
  /** How long the full-screen logo shows when the TV starts or switches into the module. */
  seconds?: number
}

/** One look: the church's default, or an override for a single module. Unset fields inherit. */
export type Look = {
  logo_url?: string
  /** Logo for dark backgrounds (falls back to logo_url). */
  logo_dark_url?: string
  primary_color?: string
  accent_color?: string
  splash?: SplashSettings
}

export type Branding = Look & {
  modules?: { kids?: Look; signage?: Look; slides?: Look }
  /** YouTube channel (UC…) used by the Kids YouTube picker and "Live now" items. */
  youtube_channel_id?: string
}

export type Organization = {
  id: string
  name: string
  slug: string
  branding: Branding
  created_at: string
  /** 'suspended' = paused by the platform owner: nothing is live. */
  status?: 'active' | 'suspended'
  /** EXPERIMENTAL features switched on by the platform admin (see NDI-CONTRACT.md). Absent or false = off. */
  ndi_enabled?: boolean
}

export type Membership = {
  id: string
  organization_id: string
  user_id: string | null
  email: string
  role: Role
  modules: Module[]
  /** null = all sites */
  site_ids: string[] | null
  created_at: string
}

export type Entitlement = {
  organization_id: string
  module: Module
  status: 'trialing' | 'active' | 'past_due' | 'canceled'
  tv_limit: number
  plan: string
  grace_ends_at: string | null
  current_period_end: string | null
}

export type Site = { id: string; organization_id: string; name: string; timezone: string }
/** `modules` tags which applications use the location (it may carry several, or none). */
export type Location = { id: string; organization_id: string; site_id: string; name: string; modules: Module[] }

export type Media = {
  id: string
  organization_id: string
  site_id: string | null
  module: Module
  folder_id: string | null
  title: string
  kind: 'video' | 'image' | 'audio'
  storage_path: string
  url: string
  size_bytes: number | null
  created_at: string
}

export type MediaFolder = {
  id: string
  organization_id: string
  module: Module
  parent_id: string | null
  /** null = all sites */
  site_id: string | null
  name: string
  created_at: string
}

// Must match PlaylistItem in the TV app (Model.kt).
export type PlaylistItem =
  | { type: 'video'; title: string; url: string; media_id: string }
  | { type: 'image'; title: string; url: string; media_id: string; seconds: number | null }
  | CountdownItem
  | LyricsItem
  // video_id null + channel_id set = whatever that channel is live-streaming when the item plays
  | { type: 'youtube'; title: string; video_id: string | null; channel_id: string | null; start: number | null }
  | StreamItem
  | NdiItem

/**
 * Lyrics: typed by hand (legacy shape, `slides`) or taken from the song library (`song_id`; the server expands it into
 * slides for the TV). `show_title` shows the song name as its own first slide that holds until Next. Legacy items have
 * no `show_title` and behave as before.
 */
export type LyricsItem =
  | { type: 'lyrics'; title: string; slides: string[]; show_title?: boolean }
  | { type: 'lyrics'; title: string; song_id: string; show_title?: boolean }

/** One row of the shared song library (`songs`). */
export type Song = {
  id: string
  organization_id: string
  title: string
  authors: string | null
  ccli_number: string | null
  copyright: string | null
  sections: SongSection[]
  /** Ordered section ids to play (repeats allowed). null / empty = every section once, in order. */
  arrangement: string[] | null
  /** 0 = one slide per section. */
  lines_per_slide: number
  source: 'manual' | 'paste' | 'file'
  created_at: string
  updated_at: string
}

/**
 * Countdown. Old items have only title + seconds. Newer fields (need app 1.4.0+): mode 'until' counts to a clock time ('HH:MM',
 * site time zone) and may omit seconds; audio plays during it; at_zero and if_passed say what happens at the end.
 * Same fields as the Slides countdown (slidesTypes.ts).
 */
export type CountdownItem = {
  type: 'countdown'
  title: string
  seconds?: number
  mode?: 'duration' | 'until'
  until?: string
  audio?: CountdownAudio | null
  at_zero?: 'next' | 'hold'
  if_passed?: 'skip' | 'zero'
}

/** Live HLS (.m3u8) feed. Must match the TV app (needs app 1.1.0+). */
export type StreamItem = {
  type: 'stream'
  title: string
  url: string
  /** null = until the viewer presses next (Kids) / the playlist loops past it (Signage). */
  seconds: number | null
  audio: boolean
  /** If the feed is down: move on, or show a "waiting for feed" card for a while first. */
  fallback: 'skip' | 'hold'
}

/**
 * EXPERIMENTAL: an NDI source (a camera or computer on the same network). Shared by Kids playlist items (`type: 'ndi'`) and
 * Slides deck slides (`kind: 'ndi'`). The server only accepts it for churches the platform admin has enabled it for
 * (organizations.ndi_enabled), and only the experimental TV build (the "ndi" flavor, app version ending "-ndi") can play it.
 * Contract: NDI-CONTRACT.md at the repository root. Keep the two in step.
 */
export type NdiConfig = {
  /** NDI source name exactly as NDI lists it, "MACHINE (Source)". Required. */
  source: string
  /** Optional host or IP with optional :port, for networks where discovery does not work. */
  address?: string | null
  audio: boolean
  /** fit = whole picture visible (letterbox); fill = crop to fill the screen. */
  fit: 'fit' | 'fill'
  /** If the source is not available: skip the slide, or show fallback_text. */
  fallback: 'skip' | 'message'
  fallback_text?: string
  /** Seconds to wait for the source (first connect, and after a drop) before the fallback applies. 3 to 120. */
  max_wait_seconds: number
  /** null = until the viewer presses next (Kids) / the playlist loops past it (Signage). */
  seconds: number | null
}

export type NdiItem = { type: 'ndi'; title: string } & NdiConfig

/** A text-only sign slide (Signage only). Must match the TV app (needs app 1.1.0+). */
export type SignSlide = {
  type: 'sign'
  title: string
  subtext: string
  background: string
  seconds: number
  align: 'left' | 'center'
  logo: boolean
}

export type Playlist = {
  id: string
  organization_id: string
  site_id: string | null
  name: string
  items: PlaylistItem[]
  updated_at: string
}

export type Schedule = {
  id: string
  organization_id: string
  location_id: string
  playlist_id: string
  starts_at: string
  ends_at: string | null
}

export type SignageItem = SignageMediaItem | StreamItem | SignSlide

export type SignageMediaItem = {
  type: 'image' | 'video'
  title: string
  url: string
  /** Images: how long to show. Videos play to the end (null). */
  seconds: number | null
  media_id: string
}

export type SignagePlaylist = {
  id: string
  organization_id: string
  site_id: string | null
  name: string
  items: SignageItem[]
  updated_at: string
}

export type ScreenGroup = { id: string; organization_id: string; name: string }

export type Screen = {
  id: string
  organization_id: string | null
  location_id: string | null
  group_id: string | null
  name: string | null
  orientation: Orientation
  default_module: ScreenModule
  signage_default_playlist_id: string | null
  autoplay?: boolean
  pairing_code: string | null
  model: string | null
  app_version: string | null
  last_seen_at: string | null
  created_at: string
}

/** Shared shape of screen_schedules and signage_slots rows. */
type RuleBase = {
  id: string
  organization_id: string
  screen_id: string | null
  group_id: string | null
  /** 0 = Sunday */
  days: number[]
  start_time: string
  end_time: string
  priority: number
  created_at: string
}
export type ScreenSchedule = RuleBase & { module: ScreenModule }
export type SignageSlot = RuleBase & { playlist_id: string }
