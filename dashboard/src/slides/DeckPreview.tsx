import { useEffect, useMemo, useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import type { DeckSlide, SlideBackground, ThemeConfig } from '../slidesTypes'
import type { SongForSlides } from '../slidesPages.types'
import { isHex } from '../lib'
import { luminance } from '../theme'
import SlideFrame from './SlideFrame'
import { DEFAULT_NAVY, framesFor, resolveBackground, resolveTheme, type Frame } from './render'

/** Church colour used when nothing else sets a background. */
export function useDefaultColor() {
  const { org } = useApp()
  return isHex(org.branding.primary_color) ? org.branding.primary_color : DEFAULT_NAVY
}

/** Light logo on dark backgrounds, dark logo on light ones (same idea as the TV). */
export function useLogoFor(bg: SlideBackground) {
  const { org } = useApp()
  const b = org.branding
  const light = bg.type === 'color' && luminance(isHex(bg.color) ? bg.color : '#000000') > 0.5
  return light ? b.logo_url || b.logo_dark_url : b.logo_dark_url || b.logo_url
}

/**
 * The live preview of one slide: a 16:9 frame and a 9:16 frame, with the resolved background
 * (slide, then deck, then theme, then the default colour). Songs step through their title and lyric screens.
 */
export default function DeckPreview({
  slide,
  deckBackground,
  theme,
  songs,
}: {
  slide: DeckSlide | undefined
  deckBackground: SlideBackground | null
  theme: ThemeConfig | undefined
  songs: Map<string, SongForSlides>
}) {
  const fallback = useDefaultColor()
  const resolvedTheme = useMemo(() => resolveTheme(theme), [theme])
  const frames = useMemo<Frame[]>(() => (slide ? framesFor(slide, songs) : []), [slide, songs])
  const [i, setI] = useState(0)
  useEffect(() => setI(0), [slide?.id])
  const idx = Math.min(i, Math.max(0, frames.length - 1))
  const bg = resolveBackground(slide, deckBackground, theme?.background, fallback)
  const logo = useLogoFor(bg)

  if (!slide || frames.length === 0) return <p className="muted">Select a slide to see it here.</p>
  const frame = frames[idx]

  return (
    <div className="stack-sm">
      <div className="sl-previews">
        <figure className="sl-fig land">
          <SlideFrame frame={frame} theme={resolvedTheme} background={bg} logo={logo} live />
          <figcaption className="muted">Landscape 16:9</figcaption>
        </figure>
        <figure className="sl-fig port">
          <SlideFrame frame={frame} theme={resolvedTheme} background={bg} logo={logo} portrait live />
          <figcaption className="muted">Portrait 9:16</figcaption>
        </figure>
      </div>
      {frames.length > 1 && (
        <div className="row spread">
          <button className="btn" onClick={() => setI(idx - 1)} disabled={idx === 0} aria-label="Previous screen">
            ← Back
          </button>
          <span className="muted" role="status">
            Screen {idx + 1} of {frames.length}
            {frame.kind === 'lyric' && frame.label ? ` · ${frame.label}` : frame.kind === 'song_title' ? ' · title' : ''}
          </span>
          <button className="btn" onClick={() => setI(idx + 1)} disabled={idx === frames.length - 1} aria-label="Next screen">
            Next →
          </button>
        </div>
      )}
      <p className="help">Preview only: fonts and text wrapping on the TV can differ slightly. Text shrinks to fit its box.</p>
    </div>
  )
}

/** A small still render of a slide (no playing video), used in the deck list. */
export function MiniSlide({
  slide,
  deckBackground,
  theme,
  songs,
}: {
  slide: DeckSlide
  deckBackground: SlideBackground | null
  theme: ThemeConfig | undefined
  songs: Map<string, SongForSlides>
}) {
  const fallback = useDefaultColor()
  const resolvedTheme = useMemo(() => resolveTheme(theme), [theme])
  const bg = resolveBackground(slide, deckBackground, theme?.background, fallback)
  const logo = useLogoFor(bg)
  return <SlideFrame frame={framesFor(slide, songs)[0]} theme={resolvedTheme} background={bg} logo={logo} />
}
