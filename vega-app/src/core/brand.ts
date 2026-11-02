// A church's look on the TV (dashboard Settings → Branding), with per-module overrides. Mirrors tv-app Theme.kt and SignSlide.kt.
import type { DeviceState, LookInfo } from './types'
import { DASHBOARD_HOST } from './config'

export interface Brand {
  primary: string
  accent: string
  logoUrl: string | null
  logoDarkUrl: string | null
  orgName: string
  /** null = no splash */
  splashSeconds: number | null
}

export const DEFAULT_BRAND: Brand = {
  primary: '#1B2A4A', accent: '#F2A33A', logoUrl: null, logoDarkUrl: null, orgName: 'Church TV OS', splashSeconds: null,
}

export const GREYSCALE = '#58595B'
export const PAPER = '#F4F5F7'

/** "#RGB", "#RRGGBB" or "#AARRGGBB" (Android's format) to "#RRGGBB" / "rgba(...)"; null if unreadable. */
export function parseHexColor(hex: string | null | undefined): string | null {
  const h = (hex ?? '').trim()
  if (/^#[0-9a-fA-F]{6}$/.test(h)) return h.toUpperCase()
  if (/^#[0-9a-fA-F]{3}$/.test(h)) return ('#' + h[1] + h[1] + h[2] + h[2] + h[3] + h[3]).toUpperCase()
  if (/^#[0-9a-fA-F]{8}$/.test(h)) {
    const a = parseInt(h.slice(1, 3), 16) / 255
    const [r, g, b] = [3, 5, 7].map((i) => parseInt(h.slice(i, i + 2), 16))
    return `rgba(${r},${g},${b},${a.toFixed(3)})`
  }
  return null
}

function rgb(color: string): [number, number, number] {
  const m = /^rgba?\((\d+),(\d+),(\d+)/.exec(color)
  if (m) return [+m[1], +m[2], +m[3]]
  const h = parseHexColor(color) ?? '#000000'
  return [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)) as [number, number, number]
}

/** Relative luminance (sRGB), as Compose's Color.luminance(). */
export function luminance(color: string): number {
  const lin = (c: number) => {
    const s = c / 255
    return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
  }
  const [r, g, b] = rgb(color)
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

/** Dark text on light backgrounds (luminance above 0.5), else white. The dashboard preview uses the same threshold. */
export const textColorOn = (background: string) => (luminance(background) > 0.5 ? '#111111' : '#FFFFFF')

export const isLight = (color: string) => luminance(color) > 0.5

/** Logo for [background]: the dark-background logo on dark colours, else the normal one (falling back either way). */
export function logoOn(brand: Brand, background: string): string | null {
  return luminance(background) < 0.4 ? brand.logoDarkUrl ?? brand.logoUrl : brand.logoUrl ?? brand.logoDarkUrl
}

/** Colour with an alpha, for overlays: withAlpha('#FFFFFF', 0.6). */
export function withAlpha(color: string, alpha: number): string {
  const [r, g, b] = rgb(color)
  return `rgba(${r},${g},${b},${alpha})`
}

/** The church's look, with [module]'s own settings (if any) laid over it. */
export function brandFor(d: DeviceState | null, module?: string): Brand {
  const org = d?.organization?.branding ?? null
  const own: LookInfo | null =
    module === 'kids' ? org?.modules?.kids ?? null
      : module === 'signage' ? org?.modules?.signage ?? null
        : module === 'slides' ? org?.modules?.slides ?? null
          : null
  const enabled = own?.splash?.enabled ?? org?.splash?.enabled
  const seconds = own?.splash?.seconds ?? org?.splash?.seconds
  return {
    primary: parseHexColor(own?.primary_color ?? org?.primary_color) ?? DEFAULT_BRAND.primary,
    accent: parseHexColor(own?.accent_color ?? org?.accent_color) ?? DEFAULT_BRAND.accent,
    logoUrl: own?.logo_url ?? org?.logo_url ?? null,
    logoDarkUrl: own?.logo_dark_url ?? org?.logo_dark_url ?? null,
    orgName: d?.organization?.name ?? DEFAULT_BRAND.orgName,
    splashSeconds: enabled === true ? Math.min(30, Math.max(2, seconds ?? 5)) : null,
  }
}

/**
 * The pairing QR contract (shared with the iOS app and the dashboard's /pair page):
 * the QR encodes exactly https://app.churchtvos.com/pair?code=<CODE>, with the 6 characters uppercase and no spaces.
 */
export function pairingQrPayload(code: string): string | null {
  const clean = code.replace(/\s/g, '').toUpperCase()
  if (!/^[A-Z0-9]{6}$/.test(clean)) return null
  return `https://${DASHBOARD_HOST}/pair?code=${clean}`
}
