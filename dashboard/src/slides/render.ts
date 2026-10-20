// Pure rules for drawing a slide: no React, no DOM. The preview components use these, and the same numbers are the
// layout spec the TV renderer follows (see SLIDES-MODULE-PLAN.md section 2). All sizes are percent of the frame HEIGHT
// ("cqh" in CSS), so a landscape and a portrait frame of the same height draw text at the same size.
import type { DeckSlide, SlideBackground, SlideLayout, ThemeConfig } from '../slidesTypes'
import type { SongForSlides } from '../slidesPages.types'
import { contrast } from '../theme'
import { expandSong } from '../songParsers'

export const DEFAULT_NAVY = '#1f3a5f'

/** Text sizes at scale 1, as percent of frame height. */
export const TITLE_PCT = 9
export const BODY_PCT = 6
export const LABEL_PCT = 2.6
export const SMALL_PCT = 3
export const COUNTDOWN_PCT = 22
/** Auto-fit never shrinks text below this. */
export const MIN_PCT = 2.4
/** Frame width as percent of frame height. */
export const ASPECT = { land: (16 / 9) * 100, port: (9 / 16) * 100 }

export type ResolvedTheme = {
  font: 'lato' | 'julius'
  titleScale: number
  bodyScale: number
  textColor: string
  align: 'left' | 'center'
  position: 'center' | 'lower' | 'top'
  shadow: boolean
  outline: boolean
  margin: number
  showLabels: boolean
  logo: { show: boolean; position: 'bottom_left' | 'bottom_right' | 'top_left' | 'top_right' }
}

const clamp = (n: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, n))
const num = (v: unknown, d: number) => (typeof v === 'number' && Number.isFinite(v) ? v : d)

/** Theme config with every default filled in (what the TV does too). */
export function resolveTheme(c?: ThemeConfig | null): ResolvedTheme {
  const t = c ?? {}
  return {
    font: t.font === 'julius' ? 'julius' : 'lato',
    titleScale: clamp(num(t.title_scale, 1), 0.5, 1.5),
    bodyScale: clamp(num(t.body_scale, 1), 0.5, 1.5),
    textColor: /^#[0-9a-fA-F]{6}$/.test(t.text_color ?? '') ? (t.text_color as string) : '#FFFFFF',
    align: t.align === 'left' ? 'left' : 'center',
    position: t.position === 'lower' || t.position === 'top' ? t.position : 'center',
    shadow: t.shadow ?? true,
    outline: t.outline ?? false,
    margin: clamp(num(t.margin, 8), 0, 20),
    showLabels: t.show_labels ?? true,
    logo: { show: t.logo?.show ?? false, position: t.logo?.position ?? 'bottom_left' },
  }
}

// ───────── Backgrounds ─────────

const usable = (b: SlideBackground | null | undefined): b is SlideBackground =>
  !!b && (b.type === 'color' || b.type === 'gradient' || !!b.url)

/** slide override, then deck, then theme, then the default colour. An image/video background with no file chosen is skipped. */
export function resolveBackground(
  slide: DeckSlide | undefined,
  deckBackground: SlideBackground | null | undefined,
  themeBackground: SlideBackground | null | undefined,
  fallbackColor: string,
): SlideBackground {
  for (const b of [slide?.background, deckBackground, themeBackground]) if (usable(b)) return b
  return { type: 'color', color: fallbackColor }
}

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
/** Mixes a colour towards black (dim 0 = unchanged, 0.8 = nearly black). */
export function dimmed(hex: string, dim = 0) {
  const k = 1 - clamp(dim, 0, 0.8)
  return '#' + rgb(hex).map((v) => Math.round(v * k).toString(16).padStart(2, '0')).join('')
}

/** The colours text sits on, with the dim overlay applied. Empty when it depends on a picture. */
export function backgroundColors(bg: SlideBackground): string[] {
  const dim = bg.dim ?? 0
  if (bg.type === 'color') return [dimmed(bg.color, dim)]
  if (bg.type === 'gradient') return [dimmed(bg.color, dim), dimmed(bg.color2, dim)]
  return []
}

/** Worst contrast ratio of the text colour against a plain colour/gradient background; null for pictures. */
export function worstContrast(textColor: string, bg: SlideBackground): number | null {
  const cols = backgroundColors(bg).filter((c) => /^#[0-9a-f]{6}$/i.test(c))
  if (!cols.length || !/^#[0-9a-f]{6}$/i.test(textColor)) return null
  return Math.min(...cols.map((c) => contrast(textColor, c)))
}

// ───────── Frames (what one TV screen shows) ─────────

export type Frame =
  | { kind: 'text'; layout: SlideLayout; title: string; body: string; align?: 'left' | 'center'; color?: string }
  | { kind: 'lyric'; text: string; label: string; n: number; count: number }
  | { kind: 'song_title'; title: string; authors: string; ccli: string; copyright: string }
  | { kind: 'countdown'; title: string; seconds: number; until?: string }
  | { kind: 'media'; url: string; media: 'image' | 'video'; fit: 'contain' | 'cover' }
  | { kind: 'stream'; title: string }
  | { kind: 'blank'; color: string }

/** The screens a deck slide produces. A song makes a title frame (if asked for) plus one frame per lyric slide. */
export function framesFor(slide: DeckSlide, songs: Map<string, SongForSlides>): Frame[] {
  switch (slide.kind) {
    case 'text':
      return [{ kind: 'text', layout: slide.layout ?? 'title_body', title: slide.title ?? '', body: slide.body ?? '', align: slide.align, color: slide.text_color }]
    case 'media':
      return [{ kind: 'media', url: slide.url, media: slide.media_kind, fit: slide.fit ?? 'contain' }]
    case 'countdown':
      return [{ kind: 'countdown', title: slide.title ?? '', seconds: slide.seconds ?? 0, until: slide.mode === 'until' && slide.until ? slide.until : undefined }]
    case 'stream':
      return [{ kind: 'stream', title: slide.title ?? '' }]
    case 'blank':
      return [{ kind: 'blank', color: slide.color ?? '#000000' }]
    case 'song': {
      const song = songs.get(slide.song_id)
      if (!song) return [{ kind: 'text', layout: 'title', title: slide.song_id ? 'Song not in the library' : 'Choose a song', body: '' }]
      const lyrics = expandSong(song)
      const out: Frame[] = []
      if (slide.show_title)
        out.push({ kind: 'song_title', title: song.title, authors: song.authors ?? '', ccli: song.ccli_number ?? '', copyright: song.copyright ?? '' })
      lyrics.forEach((l, i) => out.push({ kind: 'lyric', text: l.text, label: l.label, n: i + 1, count: lyrics.length }))
      return out.length ? out : [{ kind: 'text', layout: 'title', title: song.title, body: '(this song has no words yet)' }]
    }
  }
}

/** How many TV screens a song slide makes (title slide included). */
export function songScreenCount(slide: { show_title?: boolean }, song: SongForSlides | undefined) {
  return song ? expandSong(song).length + (slide.show_title ? 1 : 0) : 0
}

/** '09:00' -> '9:00 AM' */
export const clock12 = (hhmm: string) => {
  const [h, m] = hhmm.split(':').map(Number)
  return `${h % 12 || 12}:${String(m || 0).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`
}

export const countdownText = (seconds: number) => {
  const s = Math.max(0, Math.round(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const pad = (n: number) => String(n).padStart(2, '0')
  return h > 0 ? `${h}:${pad(m)}:${pad(s % 60)}` : `${pad(m)}:${pad(s % 60)}`
}

// ───────── Text blocks and auto-fit ─────────

export type Block = { role: 'label' | 'title' | 'body' | 'small' | 'time'; text: string; size: number; weight: number }
export type TextPlan = { blocks: Block[]; align: 'left' | 'center'; color: string; top: number; bottom: number }

/** Which blocks a frame draws, at what size (percent of frame height, before shrinking), and the box (percent from the top) they fit in. */
export function planText(frame: Frame, t: ResolvedTheme): TextPlan | null {
  const ts = TITLE_PCT * t.titleScale
  const bs = BODY_PCT * t.bodyScale
  const m = t.margin
  const box = (position: ResolvedTheme['position'], lowerThird = false) => {
    if (lowerThird) return { top: Math.max(m, 66), bottom: 100 - m }
    if (position === 'lower') return { top: Math.max(m, 45), bottom: 100 - m }
    if (position === 'top') return { top: m, bottom: Math.min(100 - m, 55) }
    return { top: m, bottom: 100 - m }
  }
  const blocks: Block[] = []
  const push = (role: Block['role'], text: string, size: number, weight: number) => text.trim() && blocks.push({ role, text, size, weight })
  switch (frame.kind) {
    case 'text': {
      if (frame.layout !== 'body') push('title', frame.title, ts, 800)
      if (frame.layout !== 'title') push('body', frame.body, bs, 500)
      return { blocks, align: frame.align ?? t.align, color: frame.color && /^#[0-9a-f]{6}$/i.test(frame.color) ? frame.color : t.textColor, ...box(t.position, frame.layout === 'lower_third') }
    }
    case 'lyric':
      if (t.showLabels) push('label', frame.label, LABEL_PCT, 700)
      push('title', frame.text, ts, 700)
      return { blocks, align: t.align, color: t.textColor, ...box(t.position) }
    case 'song_title':
      push('title', frame.title, ts, 800)
      push('small', frame.authors, SMALL_PCT, 500)
      push('small', frame.copyright, SMALL_PCT * 0.85, 400)
      push('small', frame.ccli ? `CCLI Song #${frame.ccli}` : '', SMALL_PCT * 0.85, 400)
      return { blocks, align: t.align, color: t.textColor, ...box(t.position) }
    case 'countdown':
      push('body', frame.title, bs, 600)
      if (frame.until) push('time', `Starts at ${clock12(frame.until)}`, COUNTDOWN_PCT * 0.45, 800)
      else push('time', countdownText(frame.seconds), COUNTDOWN_PCT, 800)
      return { blocks, align: 'center', color: t.textColor, top: m, bottom: 100 - m }
    default:
      return null
  }
}

const LINE_HEIGHT = 1.2
/** Average glyph width as a fraction of the font size (a little generous so the estimate errs on shrinking). */
const glyph = (font: ResolvedTheme['font'], weight: number) => (font === 'julius' ? 0.6 : 0.52) * (weight >= 700 ? 1.06 : 1)

/** Number of lines a text takes when wrapped at a width (all in percent-of-height units). Words longer than a line are broken. */
export function wrapLines(text: string, size: number, width: number, charW: number): number {
  const perLine = Math.max(1, Math.floor(width / (size * charW)))
  let lines = 0
  for (const para of text.split('\n')) {
    let used = 0
    let n = 1
    for (const word of para.split(/\s+/).filter(Boolean)) {
      const w = word.length
      if (w > perLine) {
        // a very long word is broken across lines
        if (used > 0) n++
        n += Math.ceil(w / perLine) - 1
        used = w % perLine || perLine
      } else if (used === 0) used = w
      else if (used + 1 + w <= perLine) used += 1 + w
      else (n++, (used = w))
    }
    lines += n
  }
  return lines
}

/** Lowest shrink factor: the main text never goes below MIN_PCT (labels and small print don't limit it). */
export function minScale(plan: TextPlan): number {
  const main = plan.blocks.filter((b) => b.role !== 'label' && b.role !== 'small').map((b) => b.size)
  return main.length ? Math.min(1, MIN_PCT / Math.min(...main)) : 1
}

/**
 * The shrink factor (0 to 1) that makes the text blocks fit the box: the same rule for every layout. Start at 1 and
 * shrink by 5% steps until the wrapped height fits, never below MIN_PCT for the smallest block.
 */
export function fitScale(plan: TextPlan, t: ResolvedTheme, aspect: 'land' | 'port'): number {
  if (plan.blocks.length === 0) return 1
  const boxW = ASPECT[aspect] * (1 - 2 * (t.margin / 100))
  const boxH = Math.max(1, plan.bottom - plan.top)
  const kMin = minScale(plan)
  const height = (k: number) => {
    let h = 0
    plan.blocks.forEach((b, i) => {
      const size = b.size * k
      h += wrapLines(b.text, size, boxW, glyph(t.font, b.weight)) * size * LINE_HEIGHT
      if (i < plan.blocks.length - 1) h += size * (b.role === 'title' || b.role === 'label' ? 0.3 : 0.15)
    })
    return h
  }
  let k = 1
  while (k > kMin && height(k) > boxH) k *= 0.95
  return Math.max(kMin, Math.round(k * 1000) / 1000)
}

// ───────── Deck helpers ─────────

/** 's_' plus 5 random letters/digits, unique within the deck. */
export function newSlideId(existing: { id: string }[]): string {
  const used = new Set(existing.map((s) => s.id))
  for (;;) {
    const id = 's_' + Math.random().toString(36).slice(2, 7).padEnd(5, '0')
    if (!used.has(id)) return id
  }
}

export type NewKind = DeckSlide['kind']

export function blankSlide(kind: NewKind, existing: { id: string }[]): DeckSlide {
  const id = newSlideId(existing)
  switch (kind) {
    case 'text':
      return { id, kind, title: '', body: '', layout: 'title_body', seconds: null }
    case 'media':
      return { id, kind, media_id: '', url: '', media_kind: 'image', fit: 'contain', seconds: null, audio: true }
    case 'song':
      return { id, kind, song_id: '', show_title: false }
    case 'countdown':
      return { id, kind, title: 'Service starts in', mode: 'duration', seconds: 300, at_zero: 'hold', if_passed: 'zero' }
    case 'stream':
      return { id, kind, title: '', url: '', audio: false, fallback: 'skip', seconds: null }
    case 'blank':
      return { id, kind, color: '#000000' }
  }
}

export const KIND_NAME: Record<NewKind, string> = {
  text: 'Text',
  media: 'Image or video',
  song: 'Song',
  countdown: 'Countdown',
  stream: 'Live stream',
  blank: 'Blank',
}

/** One line describing a slide for the strip: multi-line titles are joined with " / " (the CSS truncates). */
export function slideLabel(slide: DeckSlide, songs: Map<string, SongForSlides>, mediaTitle?: (id: string) => string | undefined): string {
  const oneLine = (s: string | undefined) => (s ?? '').split('\n').map((x) => x.trim()).filter(Boolean).join(' / ')
  switch (slide.kind) {
    case 'text':
      return oneLine(slide.title) || oneLine(slide.body) || 'Empty text slide'
    case 'media':
      return mediaTitle?.(slide.media_id) || (slide.media_id ? (slide.media_kind === 'video' ? 'Video' : 'Image') : 'Choose a file')
    case 'song':
      return songs.get(slide.song_id)?.title || (slide.song_id ? 'Song removed' : 'Choose a song')
    case 'countdown':
      return oneLine(slide.title) || 'Countdown'
    case 'stream':
      return oneLine(slide.title) || 'Live stream'
    case 'blank':
      return 'Blank'
  }
}

/** The first thing wrong with a deck's slides (for the Save button), or null. */
export function firstProblem(slides: DeckSlide[], deckBackground: SlideBackground | null): string | null {
  const badBg = (b: SlideBackground | null | undefined) => !!b && (b.type === 'image' || b.type === 'video') && !b.url
  if (badBg(deckBackground)) return 'The deck background needs an image or video chosen (or switch it back to the theme background).'
  for (let i = 0; i < slides.length; i++) {
    const s = slides[i]
    const n = i + 1
    if (badBg(s.background)) return `Slide ${n}: the background needs an image or video chosen.`
    if (s.kind === 'media' && !s.url) return `Slide ${n} needs an image or video chosen.`
    if (s.kind === 'song' && !s.song_id) return `Slide ${n} needs a song chosen.`
    if (s.kind === 'stream' && !/^https?:\/\/\S+$/i.test(s.url.trim())) return `Slide ${n} needs a stream link starting with https://.`
    if (s.kind === 'countdown') {
      const bad = countdownProblem(s)
      if (bad) return `Slide ${n}: ${bad}`
    }
    if (s.kind === 'text' && !(s.title ?? '').trim() && !(s.body ?? '').trim()) return `Slide ${n} is an empty text slide. Add some words or delete it.`
  }
  return null
}

/** Trims text, drops empty optional fields. */
export function cleanSlide(s: DeckSlide): DeckSlide {
  const out = { ...s } as DeckSlide
  if (!out.notes?.trim()) delete out.notes
  else out.notes = out.notes.trim()
  if (out.background === null) delete out.background
  if (out.kind === 'text') {
    out.title = (out.title ?? '').trim()
    out.body = (out.body ?? '').trim()
  }
  if (out.kind === 'countdown' || out.kind === 'stream') out.title = (out.title ?? '').trim()
  if (out.kind === 'stream') out.url = out.url.trim()
  return out
}

export const OVERSIZE_VIDEO_BYTES = 200 * 1024 * 1024

/** What is wrong with a countdown's settings (slide or Kids item), or null. */
export function countdownProblem(c: { mode?: string; seconds?: number; until?: string; audio?: { url: string } | null }): string | null {
  if (c.mode === 'until') {
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(c.until ?? '')) return 'choose the clock time to count down to.'
  } else if (!((c.seconds ?? 0) > 0)) return 'the countdown needs at least 1 second.'
  if (c.audio && !c.audio.url) return 'choose an audio file, or remove the audio.'
  return null
}
