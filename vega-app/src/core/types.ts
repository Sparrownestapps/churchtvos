// What the server sends (device_state). Field names are the server's own; see tv-app Api.kt, Model.kt and SlidesModel.kt.
// Everything optional is filled in by normalizeState, so the rest of the app can rely on the defaults.

export interface SplashInfo { enabled?: boolean | null; seconds?: number | null }

export interface LookInfo {
  logo_url?: string | null
  logo_dark_url?: string | null
  primary_color?: string | null
  accent_color?: string | null
  splash?: SplashInfo | null
}

export interface BrandingInfo extends LookInfo {
  modules?: { kids?: LookInfo | null; signage?: LookInfo | null; slides?: LookInfo | null } | null
}

export interface OrganizationInfo { name: string; branding?: BrandingInfo | null; status?: string }

export interface ScreenInfo { name?: string | null; orientation: string; autoplay: boolean }

/** Days are 0 = Sunday; times are "HH:MM" local to the site. */
export interface ModuleRule { module: string; days: number[]; start: string; end: string; priority: number }

export interface CountdownAudio {
  url: string
  media_id?: string | null
  volume?: number
  loop?: boolean
  fade_seconds?: number
  align_end?: boolean
}

export type PlaylistItem =
  | { type: 'video'; title: string; url: string }
  /** seconds null = stays up until someone presses Next. */
  | { type: 'image'; title: string; url: string; seconds?: number | null }
  | {
      type: 'countdown'; title: string; seconds?: number; mode?: string; until?: string | null
      audio?: CountdownAudio | null; at_zero?: string; if_passed?: string
    }
  | {
      type: 'lyrics'; title: string; slides: string[]; labels?: string[]; show_title?: boolean
      authors?: string | null; ccli?: string | null; copyright?: string | null
    }
  | { type: 'sign'; title: string; subtext?: string; background?: string; seconds?: number; align?: string; logo?: boolean }
  | { type: 'stream'; title: string; url: string; seconds?: number | null; audio?: boolean; fallback?: string }
  | { type: 'youtube'; title: string; video_id?: string | null; channel_id?: string | null; start?: number | null }
  | { type: 'ndi'; title?: string; fallback?: string; fallback_text?: string; seconds?: number | null }
  | { type: string; title?: string }

export interface Playlist { id: string; name: string; items: PlaylistItem[] }

export interface Schedule { id: string; starts_at: string; ends_at?: string | null; playlist: Playlist }

export interface SignageSlot { id: string; days: number[]; start: string; end: string; priority: number; playlist: Playlist }

export type SlideBackground =
  | { type: 'color'; color?: string; dim?: number }
  | { type: 'gradient'; color?: string; color2?: string; angle?: number; dim?: number }
  | { type: 'image'; url: string; fit?: string; color?: string | null; dim?: number }
  | { type: 'video'; url: string; fit?: string; color?: string | null; dim?: number }
  | { type: string; dim?: number }

export interface ThemeConfig {
  font?: string | null
  title_scale?: number
  body_scale?: number
  text_color?: string | null
  align?: string | null
  position?: string | null
  shadow?: boolean
  outline?: boolean
  margin?: number
  background?: SlideBackground | null
  show_labels?: boolean
  logo?: { show?: boolean; position?: string }
}

interface SlideBase { id?: string; background?: SlideBackground | null }

export type DeckSlide =
  | (SlideBase & {
      kind: 'text'; title?: string | null; body?: string | null; layout?: string; align?: string | null
      text_color?: string | null; seconds?: number | null
    })
  | (SlideBase & { kind: 'media'; url: string; media_kind?: string; fit?: string; seconds?: number | null; audio?: boolean })
  | (SlideBase & {
      kind: 'countdown'; title?: string | null; seconds?: number; mode?: string; until?: string | null
      audio?: CountdownAudio | null; at_zero?: string; if_passed?: string
    })
  | (SlideBase & { kind: 'stream'; title?: string | null; url: string; audio?: boolean; fallback?: string; seconds?: number | null })
  | (SlideBase & { kind: 'ndi'; title?: string; source?: string; fallback?: string; fallback_text?: string; seconds?: number | null })
  | (SlideBase & { kind: 'blank'; color?: string | null })
  | (SlideBase & { kind: 'song_title'; title: string; authors?: string | null; ccli?: string | null; copyright?: string | null })
  | (SlideBase & { kind: 'lyric'; song?: string; text: string; label?: string | null; number?: number; count?: number })
  | (SlideBase & { kind: string })

export interface Deck {
  id: string
  name: string
  loop?: boolean
  theme?: ThemeConfig
  background?: SlideBackground | null
  slides: DeckSlide[]
}

export interface DeckSchedule { id: string; starts_at: string; ends_at?: string | null; deck: Deck }

/** A "play this now" request from a remote: it replaces the schedule until [until] or until someone stops it. */
export interface OverrideInfo { kind: string; until: string; deck?: Deck | null; playlist?: Playlist | null }

export interface DeviceState {
  paired: boolean
  pairing_code?: string | null
  organization?: OrganizationInfo | null
  experimental: { ndi?: boolean }
  site?: string | null
  location?: string | null
  timezone: string
  screen: ScreenInfo
  enabled_modules: string[]
  default_module: string
  module_rules: ModuleRule[]
  kids: { schedules: Schedule[] }
  signage: { slots: SignageSlot[]; default_playlist?: Playlist | null }
  slides: { schedules: DeckSchedule[] }
  override?: OverrideInfo | null
}

/** Fills in the defaults the Android app's decoder applies, so missing fields never crash a screen. */
export function normalizeState(raw: unknown): DeviceState {
  const r = (raw ?? {}) as Partial<DeviceState> & Record<string, unknown>
  const screen = (r.screen ?? {}) as Partial<ScreenInfo>
  const kids = (r.kids ?? {}) as Partial<DeviceState['kids']>
  const signage = (r.signage ?? {}) as Partial<DeviceState['signage']>
  const slides = (r.slides ?? {}) as Partial<DeviceState['slides']>
  return {
    paired: r.paired === true,
    pairing_code: r.pairing_code ?? null,
    organization: r.organization ?? null,
    experimental: r.experimental ?? {},
    site: r.site ?? null,
    location: r.location ?? null,
    timezone: r.timezone || 'America/Toronto',
    screen: { name: screen.name ?? null, orientation: screen.orientation || 'landscape', autoplay: screen.autoplay === true },
    enabled_modules: r.enabled_modules ?? [],
    default_module: r.default_module || 'kids',
    module_rules: (r.module_rules ?? []).map((m) => ({ ...m, days: m.days ?? [], priority: m.priority ?? 0 })),
    kids: { schedules: kids.schedules ?? [] },
    signage: {
      slots: (signage.slots ?? []).map((s) => ({ ...s, days: s.days ?? [], priority: s.priority ?? 0 })),
      default_playlist: signage.default_playlist ?? null,
    },
    slides: { schedules: slides.schedules ?? [] },
    override: r.override ?? null,
  }
}
