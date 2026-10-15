import { useSyncExternalStore } from 'react'

/** Light / Dark / System, remembered per browser. index.html applies it before first paint; this keeps it live. */
export type ThemeMode = 'light' | 'dark' | 'system'
export type Resolved = 'light' | 'dark'

const KEY = 'churchtvos.theme'
/** Must match --card in styles.css (the lightest dark-mode surface brand colours sit on). */
export const DARK_SURFACE = '#1a1e24'
/** Browser chrome colours (theme-color meta) = the app bar. */
const CHROME: Record<Resolved, string> = { light: '#ffffff', dark: DARK_SURFACE }

const media = typeof matchMedia === 'function' ? matchMedia('(prefers-color-scheme: dark)') : null

function readMode(): ThemeMode {
  try {
    const v = localStorage.getItem(KEY)
    if (v === 'light' || v === 'dark' || v === 'system') return v
  } catch {
    /* private mode */
  }
  return 'system'
}

let mode: ThemeMode = readMode()
const listeners = new Set<() => void>()

export const resolveMode = (m: ThemeMode): Resolved => (m === 'system' ? (media?.matches ? 'dark' : 'light') : m)

function apply() {
  const resolved = resolveMode(mode)
  const root = document.documentElement
  root.dataset.theme = resolved
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', CHROME[resolved])
  document.querySelector('meta[name="apple-mobile-web-app-status-bar-style"]')?.setAttribute('content', resolved === 'dark' ? 'black' : 'default')
  listeners.forEach((l) => l())
}

export function setThemeMode(m: ThemeMode) {
  mode = m
  try {
    localStorage.setItem(KEY, m)
  } catch {
    /* the choice just isn't remembered */
  }
  apply()
}

/** Call once at startup: syncs meta tags and follows the system theme while on System. */
export function initTheme() {
  apply()
  media?.addEventListener?.('change', () => mode === 'system' && apply())
}

const snapshot = () => `${mode}|${resolveMode(mode)}`
const subscribe = (cb: () => void) => (listeners.add(cb), () => void listeners.delete(cb))

export function useTheme(): { mode: ThemeMode; resolved: Resolved } {
  const [m, r] = useSyncExternalStore(subscribe, snapshot).split('|')
  return { mode: m as ThemeMode, resolved: r as Resolved }
}

// ───────── Colour maths (WCAG relative luminance) ─────────

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
const toHex = (c: number[]) => '#' + c.map((v) => Math.round(Math.max(0, Math.min(255, v))).toString(16).padStart(2, '0')).join('')

/** Relative luminance 0 (black) to 1 (white). Text on a background is dark when this is > 0.5 (same rule as the TV app). */
export function luminance(hex: string) {
  const [r, g, b] = rgb(hex).map((v) => v / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

export function contrast(a: string, b: string) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

/** Colour of text to put on a sign background: near-black on light, white on dark. */
export const signTextColor = (bg: string) => (luminance(bg) > 0.5 ? '#111111' : '#ffffff')

/** Whichever of white / near-black reads best on this colour (button labels). */
export const onColor = (bg: string) => (contrast(bg, '#ffffff') >= contrast(bg, '#111111') ? '#ffffff' : '#111111')

/** Lightens a brand colour (mixing towards white) until it reads on the dark surface; unchanged if it already does. */
export function readableOnDark(hex: string, min = 4.8, surface = DARK_SURFACE) {
  const base = rgb(hex)
  for (let t = 0; t <= 1.0001; t += 0.04) {
    const c = toHex(base.map((v) => v + (255 - v) * t))
    if (contrast(c, surface) >= min) return c
  }
  return '#ffffff'
}
