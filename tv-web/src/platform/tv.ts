// What kind of TV the web player is running on, and its remote buttons.
// LG webOS: https://webostv.developer.lge.com (key codes, Back = 461). Samsung Tizen: https://developer.samsung.com/smarttv
// (key codes, Back = 10009; media keys must be registered with tizen.tvinputdevice).

export type RemoteKey =
  | 'up' | 'down' | 'left' | 'right' | 'select' | 'playPause' | 'next' | 'previous' | 'fastForward' | 'rewind' | 'menu' | 'back'

export interface TvInfo { kind: 'webos' | 'tizen' | 'web'; model: string }

type Tizen = {
  tvinputdevice?: { registerKey(name: string): void; getSupportedKeys(): { name: string }[] }
  application?: { getCurrentApplication(): { exit(): void } }
}
type SamsungWebApis = {
  appcommon?: { setScreenSaver(state: number, ok?: () => void, err?: () => void): void; AppCommonScreenSaverState: { SCREEN_SAVER_ON: number; SCREEN_SAVER_OFF: number } }
  productinfo?: { getRealModel?(): string; getModel?(): string }
}
declare global {
  interface Window {
    tizen?: Tizen
    webapis?: SamsungWebApis
    webOS?: { platformBack?(): void; deviceInfo?(cb: (info: { modelName?: string }) => void): void }
    webOSSystem?: { close?(): void }
  }
}

export function detectTv(): TvInfo {
  const ua = navigator.userAgent
  if (window.tizen || /Tizen/i.test(ua)) {
    let model = 'Samsung TV'
    try { model = `Samsung ${window.webapis?.productinfo?.getRealModel?.() ?? window.webapis?.productinfo?.getModel?.() ?? 'TV'}` } catch { /* no product info */ }
    return { kind: 'tizen', model }
  }
  if (/Web0S|webOS/i.test(ua)) return { kind: 'webos', model: 'LG webOS TV' }
  return { kind: 'web', model: 'Web browser' }
}

/** Samsung only delivers media keys to apps that ask for them. */
export async function prepareTv(tv: TvInfo) {
  if (tv.kind !== 'tizen') return
  const input = window.tizen?.tvinputdevice
  if (!input) return
  const wanted = ['MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaFastForward', 'MediaRewind', 'MediaTrackNext', 'MediaTrackPrevious', 'ColorF0Red', 'Menu', 'Tools']
  const supported = new Set(input.getSupportedKeys().map((k) => k.name))
  for (const k of wanted) if (supported.has(k)) { try { input.registerKey(k) } catch { /* not on this model */ } }
}

const BY_CODE: Record<number, RemoteKey> = {
  37: 'left', 38: 'up', 39: 'right', 40: 'down', 13: 'select',
  // LG webOS
  461: 'back', 415: 'playPause', 19: 'playPause', 417: 'fastForward', 412: 'rewind',
  // Samsung Tizen
  10009: 'back', 10252: 'playPause', 10232: 'previous', 10233: 'next', 10135: 'menu', 18: 'menu', 403: 'menu',
}

const BY_KEY: Record<string, RemoteKey> = {
  ArrowLeft: 'left', ArrowUp: 'up', ArrowRight: 'right', ArrowDown: 'down', Enter: 'select',
  Escape: 'back', Backspace: 'back', GoBack: 'back', BrowserBack: 'back',
  MediaPlayPause: 'playPause', MediaPlay: 'playPause', MediaPause: 'playPause', ' ': 'playPause',
  MediaTrackNext: 'next', MediaTrackPrevious: 'previous', MediaFastForward: 'fastForward', MediaRewind: 'rewind',
  ContextMenu: 'menu', m: 'menu', M: 'menu',
}

export function keyFromEvent(e: KeyboardEvent): RemoteKey | null {
  // Typing in a text field (none in this app today) keeps its keys.
  if ((e.target as HTMLElement | null)?.tagName === 'INPUT') return null
  return BY_CODE[e.keyCode] ?? BY_KEY[e.key] ?? null
}

/** Samsung lets an app switch the TV's screensaver off while it shows content. Other TVs: no-op. */
export function setScreenSaver(on: boolean) {
  const common = window.webapis?.appcommon
  if (!common) return
  try {
    const s = common.AppCommonScreenSaverState
    common.setScreenSaver(on ? s.SCREEN_SAVER_ON : s.SCREEN_SAVER_OFF)
  } catch { /* older model */ }
}

/** Back on the first screen leaves the app, as TV apps are expected to. */
export function exitApp() {
  try { window.tizen?.application?.getCurrentApplication().exit(); return } catch { /* not Samsung */ }
  if (window.webOS?.platformBack) { window.webOS.platformBack(); return }
  window.webOSSystem?.close?.()
}
