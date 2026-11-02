// Everything Vega-specific lives here: storage, the media cache, video, remote keys and Back.
// The rest of the app (src/core, src/ui) only uses these functions, so a gap found on a real device is fixed in one place.
//
// Checked against the Vega SDK 2.0 docs (2026-11-02). Items marked VERIFY are not confirmed by the docs and need a first
// run on a Fire TV Stick 4K Select (see README "Never run on a real device").
import React, { useEffect, useRef } from 'react'
import { BackHandler, View } from 'react-native'
import { useTVEventHandler, type HWEvent } from '@amazon-devices/react-native-kepler'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { useFonts } from '@amazon-devices/expo-font'
import * as FileSystem from '@amazon-devices/expo-file-system'
import { KeplerVideoSurfaceView, VideoPlayer } from '@amazon-devices/react-native-w3cmedia'
import { cacheName } from '../core/cacheName'
import { REPORTED_APP_VERSION } from '../core/config'
import type { KeyValue, MediaStore, Platform } from '../core/sync'

// ---------------------------------------------------------------- storage

const PREFIX = 'ctvos:'

const kv: KeyValue = {
  get: (k) => AsyncStorage.getItem(PREFIX + k),
  set: (k, v) => AsyncStorage.setItem(PREFIX + k, v),
  clear: async () => {
    const keys = (await AsyncStorage.getAllKeys()).filter((k) => k.startsWith(PREFIX))
    await AsyncStorage.multiRemove(keys)
  },
}

// ---------------------------------------------------------------- media cache

/** /data/media/ (documentDirectory is the app's persistent /data folder, survives reboots and updates). */
const MEDIA_DIR = `${FileSystem.documentDirectory ?? '/data/'}media/`
/** Leave this much free so the system and the app itself never run out of room. */
const RESERVE_BYTES = 500 * 1024 * 1024

/** Names of fully downloaded files, so has() is instant (players check it on every render). */
const present = new Set<string>()

/** VERIFY: whether <Image> and the video player accept a plain /data path or need file://. One switch for both. */
const FILE_URI = (path: string) => `file://${path}`

async function loadMediaIndex() {
  await FileSystem.makeDirectoryAsync(MEDIA_DIR, { intermediates: true }).catch(() => undefined)
  const names = await FileSystem.readDirectoryAsync(MEDIA_DIR).catch(() => [] as string[])
  for (const n of names) {
    if (n.endsWith('.part')) await FileSystem.deleteAsync(MEDIA_DIR + n, { idempotent: true }).catch(() => undefined)
    else present.add(n)
  }
}

const media: MediaStore = {
  has: (url) => present.has(cacheName(url)),

  async download(url) {
    const name = cacheName(url)
    if (present.has(name)) return
    const free = await FileSystem.getFreeDiskStorageAsync().catch(() => Number.MAX_SAFE_INTEGER)
    if (free < RESERVE_BYTES) throw new Error('Not enough space on this TV')
    // Write to a temp file first so a dropped connection never leaves half a video behind.
    const partial = MEDIA_DIR + name + '.part'
    try {
      const res = await FileSystem.downloadAsync(url, partial, { cache: false } as never)
      if (res.status < 200 || res.status > 299) throw new Error(`Download failed (HTTP ${res.status})`)
      await FileSystem.moveAsync({ from: partial, to: MEDIA_DIR + name })
      present.add(name)
    } finally {
      await FileSystem.deleteAsync(partial, { idempotent: true }).catch(() => undefined)
    }
  },

  async prune(keepUrls) {
    const keep = new Set(keepUrls.map(cacheName))
    for (const name of [...present]) {
      if (keep.has(name)) continue
      await FileSystem.deleteAsync(MEDIA_DIR + name, { idempotent: true }).catch(() => undefined)
      present.delete(name)
    }
  },
}

/** Where to play or show [url] from: the downloaded copy, or the web while it is still downloading. */
export function localUri(url: string): string {
  const name = cacheName(url)
  return present.has(name) ? FILE_URI(MEDIA_DIR + name) : url
}

// ---------------------------------------------------------------- platform

function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n)
  const c = (globalThis as { crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array } }).crypto
  if (c?.getRandomValues) return c.getRandomValues(out)
  // VERIFY: Hermes on Vega may not expose crypto.getRandomValues. This fallback is not cryptographic; the device
  // secret it makes is still unique per TV, but swap in a native random source if one is available.
  let seed = Date.now() ^ Math.floor(Math.random() * 0xffffffff)
  for (let i = 0; i < n; i++) {
    seed = (seed * 1664525 + 1013904223 + Math.floor(Math.random() * 256)) >>> 0
    out[i] = (seed >>> 24) & 0xff
  }
  return out
}

export async function createPlatform(): Promise<Platform> {
  await loadMediaIndex()
  return {
    kv,
    media,
    model: 'Fire TV (Vega OS)',
    appVersion: REPORTED_APP_VERSION,
    randomBytes,
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    now: () => Date.now(),
  }
}

// ---------------------------------------------------------------- remote keys and Back

export type RemoteKey =
  | 'up' | 'down' | 'left' | 'right' | 'select' | 'playPause' | 'next' | 'previous' | 'fastForward' | 'rewind' | 'menu'

const KEY_NAMES: Record<string, RemoteKey> = {
  up: 'up', down: 'down', left: 'left', right: 'right', select: 'select', menu: 'menu',
  playpause: 'playPause', play: 'playPause', pause: 'playPause',
  skip_forward: 'next', skip_backward: 'previous', forward: 'fastForward', rewind: 'rewind',
}

/**
 * Remote buttons while this screen is in front. Only key-down (eventKeyAction 0) is passed on; held keys repeat.
 * D-pad focus movement can't be overridden on Vega, so screens with buttons let the system move focus.
 */
export function useRemoteKeys(handler: (key: RemoteKey, repeat: boolean) => boolean | void, enabled = true) {
  const ref = useRef(handler)
  ref.current = handler
  const down = useRef<Record<string, boolean>>({})
  useTVEventHandler((e: HWEvent) => {
    if (!enabled || !e?.eventType) return
    const key = KEY_NAMES[e.eventType]
    if (!key) return
    if (e.eventKeyAction === 1) { down.current[key] = false; return }
    const repeat = down.current[key] === true
    down.current[key] = true
    ref.current(key, repeat)
  })
}

/** The remote's Back button. Return true when handled; false lets the system leave the app. */
export function useBack(handler: () => boolean, enabled = true) {
  const ref = useRef(handler)
  ref.current = handler
  useEffect(() => {
    if (!enabled) return
    const sub = BackHandler.addEventListener('hardwareBackPress', () => ref.current())
    return () => sub.remove()
  }, [enabled])
}

/**
 * Vega has no API to keep the screen on (release notes). The screensaver starts after 5 minutes without remote input.
 * VERIFY whether playing video holds it off. Kept as a hook so a future API slots in without touching the players.
 */
export function useKeepAwake() {}

// ---------------------------------------------------------------- video and audio

/**
 * One video or audio file, filling its parent. Follows Amazon's vega-video-sample: VideoPlayer + KeplerVideoSurfaceView.
 * Vega's player (w3cmedia) has no loop, volume or mute: looping restarts on "ended"; [volume] 0 pauses audio-only
 * players; otherwise volume is ignored (see README). HLS (.m3u8) needs the Shaka/hls.js MSE player (the sample's
 * shaka-setup) and is not wired up yet: it reports an error, so live streams skip or hold their notice.
 */
export function VideoView(props: {
  uri: string
  paused?: boolean
  loop?: boolean
  volume?: number
  fit?: 'contain' | 'cover'
  audioOnly?: boolean
  /** Seek here (ms) when this changes. */
  startAtMs?: number
  onEnded?: () => void
  onError?: () => void
  onDuration?: (ms: number) => void
}) {
  const player = useRef<VideoPlayer | null>(null)
  const surface = useRef<string | null>(null)
  const [ready, setReady] = React.useState(false)
  const cb = useRef(props)
  cb.current = props

  useEffect(() => {
    let alive = true
    const p = new VideoPlayer()
    player.current = p
    const ended = () => {
      if (cb.current.loop) { p.currentTime = 0; void p.play() } else cb.current.onEnded?.()
    }
    const error = () => cb.current.onError?.()
    const meta = () => { if (p.duration > 0) cb.current.onDuration?.(p.duration * 1000) }
    ;(async () => {
      try {
        if (/\.m3u8($|\?)/i.test(cb.current.uri)) throw new Error('HLS needs the MSE player')
        await p.initialize()
        if (!alive) return
        p.addEventListener('ended', ended)
        p.addEventListener('error', error)
        p.addEventListener('loadedmetadata', meta)
        p.autoplay = false
        p.src = cb.current.uri
        p.load()
        if (surface.current) p.setSurfaceHandle(surface.current)
        setReady(true)
      } catch {
        if (alive) cb.current.onError?.()
      }
    })()
    return () => {
      alive = false
      setReady(false)
      p.removeEventListener('ended', ended)
      p.removeEventListener('error', error)
      p.removeEventListener('loadedmetadata', meta)
      try { p.pause() } catch { /* already stopped */ }
      if (surface.current) p.clearSurfaceHandle(surface.current)
      void p.deinitialize().catch(() => undefined)
      player.current = null
    }
  }, [props.uri])

  const silent = props.audioOnly && (props.volume ?? 1) <= 0.001
  useEffect(() => {
    const p = player.current
    if (!p || !ready) return
    if (props.paused || silent) p.pause()
    else void p.play().catch(() => cb.current.onError?.())
  }, [props.paused, silent, ready])

  useEffect(() => {
    const p = player.current
    if (p && ready && props.startAtMs) p.currentTime = props.startAtMs / 1000
  }, [props.startAtMs, ready])

  if (props.audioOnly) return null
  return (
    <View style={{ position: 'absolute', left: 0, top: 0, right: 0, bottom: 0 }} pointerEvents="none">
      {/* VERIFY: "cover" fit and rotation (portrait screens) on the video surface. */}
      <KeplerVideoSurfaceView
        style={{ flex: 1, zIndex: 0 }}
        onSurfaceViewCreated={(h: string) => { surface.current = h; player.current?.setSurfaceHandle(h) }}
        onSurfaceViewDestroyed={(h: string) => { player.current?.clearSurfaceHandle(h); surface.current = null }}
      />
    </View>
  )
}

// ---------------------------------------------------------------- fonts and bundled pictures

/** Lato and Julius Sans One, as in the Android app (assets/fonts, loaded at start as Amazon's expo-font page describes). */
export function useAppFonts(): boolean {
  const [loaded] = useFonts({
    'Lato-Regular': require('../../assets/fonts/Lato-Regular.ttf'),
    'Lato-Bold': require('../../assets/fonts/Lato-Bold.ttf'),
    'Lato-Black': require('../../assets/fonts/Lato-Black.ttf'),
    'JuliusSansOne-Regular': require('../../assets/fonts/JuliusSansOne-Regular.ttf'),
  })
  return loaded
}

/** Pictures shipped inside the app for demo mode (the same ones as the Android app). */
export const BUNDLED: Record<string, number> = {
  welcome: require('../../assets/demo/demo_welcome.png'),
  events: require('../../assets/demo/demo_events.png'),
  info: require('../../assets/demo/demo_info.png'),
}
