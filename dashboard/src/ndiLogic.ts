// EXPERIMENTAL NDI source: pure rules (no React) shared by the Kids and Slides editors and by slides/render.ts. See NDI-CONTRACT.md.
import type { NdiConfig, NdiItem } from './types'

export const NDI_DEFAULTS: NdiConfig = {
  source: '',
  address: null,
  audio: false,
  fit: 'fit',
  fallback: 'skip',
  fallback_text: '',
  max_wait_seconds: 15,
  seconds: null,
}

export const newNdiItem = (): NdiItem => ({ type: 'ndi', title: '', ...NDI_DEFAULTS })

/** Host name or IPv4 with an optional :port. Empty is fine (discovery by name). */
export const validNdiAddress = (a: string) => a.trim() === '' || /^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?(:\d{1,5})?$/.test(a.trim()) && portOk(a.trim())
function portOk(a: string) {
  const m = /:(\d{1,5})$/.exec(a)
  return !m || (Number(m[1]) >= 1 && Number(m[1]) <= 65535)
}

/** What is wrong with an NDI source's settings, or null. Mirrors the database check (ndi_check). */
export function ndiProblem(c: NdiConfig): string | null {
  if (!c.source.trim()) return 'choose the NDI source name, for example "STUDIO-PC (Camera 1)".'
  if (c.source.length > 200) return 'the NDI source name is too long.'
  if (!validNdiAddress(c.address ?? '')) return 'the address must be a host name or IP address, with an optional :port (for example 192.168.1.50:5961), and no spaces.'
  if (!Number.isInteger(c.max_wait_seconds) || c.max_wait_seconds < 3 || c.max_wait_seconds > 120) return '"Wait for the source" must be a whole number from 3 to 120 seconds.'
  if (c.seconds != null && (!Number.isInteger(c.seconds) || c.seconds < 1 || c.seconds > 86400)) return '"Show for" must be a whole number of seconds, or empty.'
  if (c.fallback === 'message' && (c.fallback_text ?? '').length > 200) return 'the fallback message is too long (200 characters).'
  return null
}

/** Removes empty optional fields before saving. */
export function cleanNdi<T extends NdiConfig>(c: T): T {
  const out = { ...c, source: c.source.trim() }
  const addr = (c.address ?? '').trim()
  if (addr) out.address = addr
  else delete out.address
  const text = (c.fallback_text ?? '').trim()
  if (c.fallback === 'message' && text) out.fallback_text = text
  else delete out.fallback_text
  return out
}

