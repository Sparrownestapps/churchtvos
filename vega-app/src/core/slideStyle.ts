// How text looks on a deck slide: the theme with any per-slide overrides applied. Mirrors tv-app SlideViews.kt toStyle().
import { parseHexColor } from './brand'
import type { ThemeConfig } from './types'

export interface SlideStyle {
  titleFont: 'lato' | 'julius'
  titleScale: number
  bodyScale: number
  color: string
  center: boolean
  /** "center", "lower" or "top" */
  position: string
  shadow: 'none' | 'soft' | 'outline'
  marginPct: number
  showLabels: boolean
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v))

export function toStyle(theme: ThemeConfig | undefined, slideAlign?: string | null, slideColor?: string | null): SlideStyle {
  const t = theme ?? {}
  return {
    titleFont: t.font === 'julius' ? 'julius' : 'lato',
    titleScale: clamp(t.title_scale ?? 1, 0.5, 1.5),
    bodyScale: clamp(t.body_scale ?? 1, 0.5, 1.5),
    color: parseHexColor(slideColor) ?? parseHexColor(t.text_color) ?? '#FFFFFF',
    center: (slideAlign ?? t.align ?? 'center') !== 'left',
    position: t.position ?? 'center',
    shadow: t.outline ? 'outline' : t.shadow === false ? 'none' : 'soft',
    marginPct: clamp(t.margin ?? 8, 0, 20),
    showLabels: t.show_labels !== false,
  }
}
