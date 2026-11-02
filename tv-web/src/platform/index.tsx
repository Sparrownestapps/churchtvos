// The web platform layer: the same functions as vega-app/src/platform, for a browser, LG webOS and Samsung Tizen.
// The shared screens and logic (vega-app/src) call only these.
import React, { useEffect, useRef, useState } from 'react'
import { cacheName } from '../../../vega-app/src/core/cacheName'
import type { KeyValue, MediaStore, Platform } from '../../../vega-app/src/core/sync'
import { detectTv, exitApp, keyFromEvent, prepareTv, setScreenSaver, type RemoteKey } from './tv'
import demoWelcome from '../../../vega-app/assets/demo/demo_welcome.png'
import demoEvents from '../../../vega-app/assets/demo/demo_events.png'
import demoInfo from '../../../vega-app/assets/demo/demo_info.png'

export type { RemoteKey }

// ---------------------------------------------------------------- storage

const PREFIX = 'ctvos:'

const kv: KeyValue = {
  get: async (k) => {
    try { return localStorage.getItem(PREFIX + k) } catch { return null }
  },
  set: async (k, v) => {
    try { localStorage.setItem(PREFIX + k, v) } catch { /* storage full or blocked: works until restart */ }
  },
  clear: async () => {
    try {
      Object.keys(localStorage).filter((k) => k.startsWith(PREFIX)).forEach((k) => localStorage.removeItem(k))
    } catch { /* nothing saved */ }
  },
}

// ---------------------------------------------------------------- media cache

/**
 * Downloads go into the browser's Cache Storage, and play from object URLs, so a schedule keeps playing if the Wi-Fi drops.
 * Where Cache Storage isn't available (some TV app contexts) nothing is cached and media streams from the web.
 */
const CACHE = 'church-tv-os-media-v1'
const objectUrls = new Map<string, string>()
const RESERVE_BYTES = 300 * 1024 * 1024

const cacheAvailable = () => typeof caches !== 'undefined'

async function loadMediaIndex() {
  if (!cacheAvailable()) return
  try {
    const cache = await caches.open(CACHE)
    for (const req of await cache.keys()) {
      const res = await cache.match(req)
      if (res) objectUrls.set(cacheName(req.url), URL.createObjectURL(await res.blob()))
    }
  } catch { /* no cache: stream */ }
}

const media: MediaStore = {
  has: (url) => !cacheAvailable() || objectUrls.has(cacheName(url)),

  async download(url) {
    if (!cacheAvailable() || objectUrls.has(cacheName(url))) return
    const est = await navigator.storage?.estimate?.().catch(() => null)
    if (est?.quota && est.usage !== undefined && est.quota - est.usage < RESERVE_BYTES) throw new Error('Not enough space on this TV')
    const res = await fetch(url)
    if (!res.ok) throw new Error(`Download failed (HTTP ${res.status})`)
    const blob = await res.blob()
    const cache = await caches.open(CACHE)
    await cache.put(url, new Response(blob, { headers: { 'Content-Type': res.headers.get('Content-Type') ?? '' } }))
    objectUrls.set(cacheName(url), URL.createObjectURL(blob))
  },

  async prune(keepUrls) {
    if (!cacheAvailable()) return
    const keep = new Set(keepUrls.map(cacheName))
    const cache = await caches.open(CACHE)
    for (const req of await cache.keys()) {
      const name = cacheName(req.url)
      if (keep.has(name)) continue
      await cache.delete(req)
      const u = objectUrls.get(name)
      if (u) URL.revokeObjectURL(u)
      objectUrls.delete(name)
    }
  },
}

/** Where to play or show [url] from: the downloaded copy, or the web while it is still downloading. */
export function localUri(url: string): string {
  return objectUrls.get(cacheName(url)) ?? url
}

// ---------------------------------------------------------------- platform

export async function createPlatform(): Promise<Platform> {
  const tv = detectTv()
  await prepareTv(tv)
  await loadMediaIndex()
  return {
    kv,
    media,
    model: tv.model,
    appVersion: `1.7.0-${tv.kind}`,
    randomBytes: (n) => crypto.getRandomValues(new Uint8Array(n)),
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    now: () => Date.now(),
  }
}

// ---------------------------------------------------------------- remote keys, Back and focus

type KeyHandler = (key: RemoteKey, repeat: boolean) => boolean | void
const keyHandlers = new Set<{ current: KeyHandler }>()
const backHandlers: { current: () => boolean }[] = []

/** Moves focus to the nearest focusable element in the arrow's direction (TVs do this natively; browsers don't). */
function moveFocus(key: 'up' | 'down' | 'left' | 'right'): boolean {
  const all = Array.from(document.querySelectorAll<HTMLElement>('[tabindex="0"], button, [role="button"]'))
    .filter((el) => el.offsetParent !== null && el.getAttribute('aria-disabled') !== 'true')
  if (all.length === 0) return false
  const from = document.activeElement as HTMLElement | null
  if (!from || !all.includes(from)) { all[0].focus(); return true }
  const a = from.getBoundingClientRect()
  const ax = a.left + a.width / 2
  const ay = a.top + a.height / 2
  let best: HTMLElement | null = null
  let bestScore = Infinity
  for (const el of all) {
    if (el === from) continue
    const b = el.getBoundingClientRect()
    const dx = b.left + b.width / 2 - ax
    const dy = b.top + b.height / 2 - ay
    const along = key === 'up' ? -dy : key === 'down' ? dy : key === 'left' ? -dx : dx
    const across = key === 'up' || key === 'down' ? Math.abs(dx) : Math.abs(dy)
    if (along <= 1) continue
    const score = along + across * 2
    if (score < bestScore) { bestScore = score; best = el }
  }
  if (!best) return false
  best.focus()
  best.scrollIntoView?.({ block: 'nearest' })
  return true
}

let installed = false
function installKeyListener() {
  if (installed) return
  installed = true
  window.addEventListener('keydown', (e) => {
    const key = keyFromEvent(e)
    if (!key) return
    if (key === 'back') {
      e.preventDefault()
      for (let i = backHandlers.length - 1; i >= 0; i--) if (backHandlers[i].current()) return
      exitApp()
      return
    }
    let handled = false
    keyHandlers.forEach((h) => { if (h.current(key, e.repeat)) handled = true })
    if (handled) { e.preventDefault(); return }
    if (key === 'up' || key === 'down' || key === 'left' || key === 'right') {
      if (moveFocus(key)) e.preventDefault()
    }
  })
}

/** Remote buttons while this screen is in front. */
export function useRemoteKeys(handler: KeyHandler, enabled = true) {
  const ref = useRef(handler)
  ref.current = handler
  useEffect(() => {
    if (!enabled) return
    installKeyListener()
    keyHandlers.add(ref)
    return () => { keyHandlers.delete(ref) }
  }, [enabled])
}

/** The remote's Back button. The newest screen gets it first; return true when handled. */
export function useBack(handler: () => boolean, enabled = true) {
  const ref = useRef(handler)
  ref.current = handler
  useEffect(() => {
    if (!enabled) return
    installKeyListener()
    backHandlers.push(ref)
    return () => {
      const i = backHandlers.indexOf(ref)
      if (i >= 0) backHandlers.splice(i, 1)
    }
  }, [enabled])
}

/** Keeps the TV from starting its screensaver while content is up (Samsung: app setting; browsers: Wake Lock). */
export function useKeepAwake() {
  useEffect(() => {
    let lock: { release(): Promise<void> } | null = null
    setScreenSaver(false)
    const wake = (navigator as Navigator & { wakeLock?: { request(t: 'screen'): Promise<{ release(): Promise<void> }> } }).wakeLock
    wake?.request('screen').then((l) => { lock = l }).catch(() => undefined)
    return () => {
      setScreenSaver(true)
      void lock?.release().catch(() => undefined)
    }
  }, [])
}

// ---------------------------------------------------------------- video and audio

const FILL: React.CSSProperties = { position: 'absolute', left: 0, top: 0, width: '100%', height: '100%', background: 'transparent' }

/** One video or audio file, filling its parent. Live streams (.m3u8) play natively on TVs and through hls.js in browsers. */
export function VideoView(props: {
  uri: string
  paused?: boolean
  loop?: boolean
  volume?: number
  fit?: 'contain' | 'cover'
  audioOnly?: boolean
  startAtMs?: number
  onEnded?: () => void
  onError?: () => void
  onDuration?: (ms: number) => void
}) {
  const el = useRef<HTMLVideoElement>(null)
  const cb = useRef(props)
  cb.current = props
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const v = el.current
    if (!v) return
    let hls: { destroy(): void } | null = null
    let alive = true
    setReady(false)
    const isHls = /\.m3u8($|\?)/i.test(props.uri)
    if (isHls && !v.canPlayType('application/vnd.apple.mpegurl')) {
      import('hls.js').then(({ default: Hls }) => {
        if (!alive) return
        if (!Hls.isSupported()) { cb.current.onError?.(); return }
        const h = new Hls()
        hls = h
        h.on(Hls.Events.ERROR, (_e, data) => { if (data.fatal) cb.current.onError?.() })
        h.loadSource(props.uri)
        h.attachMedia(v)
        setReady(true)
      }).catch(() => cb.current.onError?.())
    } else {
      v.src = props.uri
      setReady(true)
    }
    return () => {
      alive = false
      hls?.destroy()
      v.removeAttribute('src')
      v.load()
    }
  }, [props.uri])

  useEffect(() => {
    const v = el.current
    if (!v || !ready) return
    if (props.paused) v.pause()
    else void v.play().catch(() => {
      // Autoplay with sound can be blocked in a desktop browser: retry muted rather than show nothing.
      v.muted = true
      void v.play().catch(() => cb.current.onError?.())
    })
  }, [props.paused, ready])

  useEffect(() => {
    const v = el.current
    if (v) v.volume = Math.min(1, Math.max(0, props.volume ?? 1))
  }, [props.volume])

  useEffect(() => {
    const v = el.current
    if (v && ready && props.startAtMs) v.currentTime = props.startAtMs / 1000
  }, [props.startAtMs, ready])

  return (
    <video
      ref={el}
      playsInline
      loop={props.loop}
      muted={(props.volume ?? 1) <= 0}
      onEnded={() => cb.current.onEnded?.()}
      onError={() => cb.current.onError?.()}
      onLoadedMetadata={(e) => { const d = e.currentTarget.duration; if (d > 0 && isFinite(d)) cb.current.onDuration?.(d * 1000) }}
      style={props.audioOnly ? { display: 'none' } : { ...FILL, objectFit: props.fit === 'cover' ? 'cover' : 'contain', pointerEvents: 'none' }}
    />
  )
}

// ---------------------------------------------------------------- fonts and bundled pictures

/** Fonts are declared with @font-face in src/fonts.css; wait until the browser has them so text fitting measures right. */
export function useAppFonts(): boolean {
  const [loaded, setLoaded] = useState(false)
  useEffect(() => {
    const fonts = (document as Document & { fonts?: { load(f: string): Promise<unknown>; ready: Promise<unknown> } }).fonts
    if (!fonts) { setLoaded(true); return }
    Promise.all(['Lato-Regular', 'Lato-Bold', 'Lato-Black', 'JuliusSansOne-Regular'].map((f) => fonts.load(`16px "${f}"`)))
      .catch(() => undefined)
      .finally(() => setLoaded(true))
  }, [])
  return loaded
}

/** Pictures shipped inside the app for demo mode (the same ones as the Android app). */
export const BUNDLED: Record<string, { uri: string }> = {
  welcome: { uri: demoWelcome },
  events: { uri: demoEvents },
  info: { uri: demoInfo },
}
