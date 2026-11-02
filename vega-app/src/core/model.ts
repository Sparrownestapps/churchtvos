// Playlists and decks turned into what the players show. Mirrors tv-app Model.kt and SlidesModel.kt.
import type { CountdownAudio, Deck, DeckSlide, Playlist, PlaylistItem, SlideBackground } from './types'

export interface CountdownSpec {
  mode: string
  seconds: number
  until: string | null
  audio: CountdownAudio | null
  atZero: string
  ifPassed: string
}

/** One screen of content in the Kids / Signage player. Lyrics expand to one slide per section. */
export type Slide =
  | { kind: 'video'; url: string }
  | { kind: 'image'; url: string; seconds: number | null }
  | { kind: 'countdown'; title: string; spec: CountdownSpec }
  /** A picture shipped inside the app (demo mode). */
  | { kind: 'bundled'; asset: string; seconds: number }
  | { kind: 'lyric'; song: string; text: string; number: number; count: number }
  /** The song name on its own, before the words. Holds until Next is pressed. */
  | { kind: 'song_title'; title: string; authors: string | null; ccli: string | null; copyright: string | null }
  | { kind: 'sign'; title: string; subtext: string; background: string; seconds: number; align: string; logo: boolean }
  | { kind: 'stream'; url: string; audio: boolean; seconds: number | null; fallback: string }
  /** An NDI item this TV can't receive, shown as its fallback message (experimental churches only). */
  | { kind: 'notice'; title: string; text: string; seconds: number | null }

export function countdownSpec(c: {
  seconds?: number; mode?: string; until?: string | null; audio?: CountdownAudio | null; at_zero?: string; if_passed?: string
}): CountdownSpec {
  return {
    mode: c.mode ?? 'duration',
    seconds: c.seconds ?? 60,
    until: c.until ?? null,
    audio: c.audio ?? null,
    atZero: c.at_zero ?? 'next',
    ifPassed: c.if_passed ?? 'zero',
  }
}

/**
 * NDI can't be received on this TV. Like the Roku app, an NDI item plays only when the church has the experimental flag
 * and the item asks to show a message when its source is unavailable; otherwise it is left out.
 */
export function ndiShowsMessage(item: { fallback?: string }, ndiFlagOn: boolean): boolean {
  return ndiFlagOn && item.fallback === 'message'
}

/** Item types this app can't play at all (YouTube, and anything newer than the app). */
export function isSupportedItem(item: PlaylistItem, ndiFlagOn: boolean): boolean {
  switch (item.type) {
    case 'video': case 'image': case 'countdown': case 'lyrics': case 'sign': case 'stream':
      return true
    case 'ndi':
      return ndiShowsMessage(item as { fallback?: string }, ndiFlagOn)
    default:
      return false
  }
}

export function toSlides(playlist: Playlist, ndiFlagOn: boolean): Slide[] {
  const out: Slide[] = []
  for (const raw of playlist.items) {
    const item = raw as Record<string, any>
    switch (item.type) {
      case 'video': out.push({ kind: 'video', url: item.url }); break
      case 'image': out.push({ kind: 'image', url: item.url, seconds: item.seconds ?? null }); break
      case 'countdown': out.push({ kind: 'countdown', title: item.title ?? '', spec: countdownSpec(item) }); break
      case 'lyrics': {
        const slides: string[] = item.slides ?? []
        if (item.show_title) {
          out.push({ kind: 'song_title', title: item.title, authors: item.authors ?? null, ccli: item.ccli ?? null, copyright: item.copyright ?? null })
        }
        slides.forEach((text, i) => out.push({ kind: 'lyric', song: item.title, text, number: i + 1, count: slides.length }))
        break
      }
      case 'sign':
        out.push({
          kind: 'sign', title: item.title ?? '', subtext: item.subtext ?? '', background: item.background ?? '#1B2A4A',
          seconds: item.seconds ?? 10, align: item.align ?? 'center', logo: item.logo === true,
        })
        break
      case 'stream':
        out.push({ kind: 'stream', url: item.url, audio: item.audio === true, seconds: item.seconds ?? null, fallback: item.fallback ?? 'skip' })
        break
      case 'ndi':
        if (ndiShowsMessage(item, ndiFlagOn)) {
          out.push({ kind: 'notice', title: item.title ?? '', text: item.fallback_text || 'Live feed unavailable', seconds: item.seconds ?? null })
        }
        break
      default:
        break // YouTube and unknown types are skipped
    }
  }
  return out
}

/** Signage loops must move on by themselves, so untimed pictures, streams and notices get a default time. */
export function signageSlides(playlist: Playlist, ndiFlagOn: boolean): Slide[] {
  return toSlides(playlist, ndiFlagOn).map((s) => {
    if (s.kind === 'image' && s.seconds === null) return { ...s, seconds: 10 }
    if (s.kind === 'stream' && s.seconds === null) return { ...s, seconds: 30 }
    if (s.kind === 'notice' && s.seconds === null) return { ...s, seconds: 30 }
    return s
  })
}

/** Remote media a playlist needs on the device before it can play. */
export function playlistMediaUrls(p: Playlist): string[] {
  const urls: string[] = []
  for (const raw of p.items) {
    const item = raw as Record<string, any>
    if (item.type === 'video' || item.type === 'image') urls.push(item.url)
    else if (item.type === 'countdown' && item.audio?.url) urls.push(item.audio.url)
  }
  return urls
}

function backgroundUrl(bg: SlideBackground | null | undefined): string | null {
  if (bg && (bg.type === 'image' || bg.type === 'video')) return (bg as { url: string }).url ?? null
  return null
}

/** Remote files a deck needs on the TV before it can play (backgrounds, images, videos, countdown music). */
export function deckMediaUrls(deck: Deck): string[] {
  const urls: string[] = []
  const add = (u: string | null | undefined) => { if (u) urls.push(u) }
  add(backgroundUrl(deck.background))
  add(backgroundUrl(deck.theme?.background))
  for (const raw of deck.slides) {
    const s = raw as Record<string, any>
    add(backgroundUrl(s.background))
    if (s.kind === 'media') add(s.url)
    if (s.kind === 'countdown') add(s.audio?.url)
  }
  return [...new Set(urls)]
}

const KNOWN_DECK_KINDS = new Set(['text', 'media', 'countdown', 'stream', 'ndi', 'blank', 'song_title', 'lyric'])

/** Deck slides this TV can show: unknown kinds dropped, NDI only as a fallback message. */
export function playableDeckSlides(deck: Deck, ndiFlagOn: boolean): DeckSlide[] {
  return deck.slides.filter((s) => KNOWN_DECK_KINDS.has(s.kind) && (s.kind !== 'ndi' || ndiShowsMessage(s as { fallback?: string }, ndiFlagOn)))
}

/** Short description of a slide for remotes ("Jump to slide" lists and the now-showing line). */
export function slideLabel(s: Slide): string {
  switch (s.kind) {
    case 'video': return 'Video'
    case 'image': return 'Picture'
    case 'bundled': return 'Slide'
    case 'countdown': return s.title.trim() || 'Countdown'
    case 'lyric': return `${s.song} · Part ${s.number} of ${s.count}`
    case 'song_title': return `${s.title} (title)`
    case 'sign': return s.title.trim() || 'Sign'
    case 'stream': return 'Live stream'
    case 'notice': return 'NDI: ' + (s.title.trim() || 'source')
  }
}

const firstLine = (s: string | null | undefined) => (s ?? '').split('\n')[0]?.trim() ?? ''

/** A deck slide in the slide list and the remotes' outline. */
export function deckSlideLabel(raw: DeckSlide): string {
  const s = raw as Record<string, any>
  switch (s.kind) {
    case 'text': return (s.title ?? '').trim() || firstLine(s.body) || 'Text'
    case 'media': return s.media_kind === 'video' ? 'Video' : 'Picture'
    case 'countdown': return (s.title ?? '').trim() ? `Countdown: ${s.title}` : 'Countdown'
    case 'stream': return (s.title ?? '').trim() ? `Live: ${s.title}` : 'Live stream'
    case 'ndi': return 'NDI: ' + ((s.title ?? '').trim() || (s.source ?? '').trim() || 'source')
    case 'blank': return 'Blank'
    case 'song_title': return `${s.title} (title)`
    case 'lyric': return `${s.song ?? ''} · ${(s.label ?? '').trim() || `Part ${s.number ?? 1}`}`
    default: return '—'
  }
}

/** The label column on the Kids home screen. */
export function itemKindLabel(item: PlaylistItem): string {
  const i = item as Record<string, any>
  switch (i.type) {
    case 'video': return 'VIDEO'
    case 'image': return 'SLIDE'
    case 'countdown': return 'COUNTDOWN'
    case 'lyrics': return 'LYRICS'
    case 'youtube': return i.video_id ? 'YOUTUBE' : 'LIVE'
    case 'sign': return 'SIGN'
    case 'stream': return 'STREAM'
    case 'ndi': return 'NDI'
    default: return '—'
  }
}

/** The label column on the Slides home screen: [kind, detail]. */
export function deckHomeLabel(raw: DeckSlide): [string, string] {
  const s = raw as Record<string, any>
  switch (s.kind) {
    case 'text': return ['TEXT', (s.title ?? '').trim() || firstLine(s.body)]
    case 'media': return [s.media_kind === 'video' ? 'VIDEO' : 'PICTURE', '']
    case 'countdown': return ['COUNTDOWN', s.title ?? '']
    case 'stream': return ['LIVE', s.title ?? '']
    case 'ndi': return ['NDI', s.title ?? '']
    case 'blank': return ['BLANK', '']
    case 'song_title': return ['SONG', s.title ?? '']
    case 'lyric': return ['LYRICS', `${s.song ?? ''} · ${s.label ?? `Part ${s.number ?? 1}`}`]
    default: return ['', '']
  }
}

/** slide, then deck, then theme (then the church's primary colour, decided by the caller). */
export function resolveBackground(deck: Deck, slide: DeckSlide | null): SlideBackground | null {
  const known = (bg: SlideBackground | null | undefined) =>
    bg && ['color', 'gradient', 'image', 'video'].includes(bg.type) ? bg : null
  return known(slide?.background) ?? known(deck.background) ?? known(deck.theme?.background) ?? null
}
