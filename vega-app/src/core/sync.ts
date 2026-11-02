// Keeps the TV in step with the dashboard: polls its schedules, pre-downloads the media, and runs the remote-control loop.
// Mirrors tv-app TvSync.kt. Storage and files come from the platform layer (src/platform) so this file runs in Node tests too.
import { Api } from './api'
import { deckMediaUrls, playlistMediaUrls } from './model'
import { parseCommand, Remote, statusKey, Store, type RawCommand } from './remote'
import { normalizeState, type DeviceState } from './types'
import { isoMillis } from './time'

export interface KeyValue {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<void>
  clear(): Promise<void>
}

export interface MediaStore {
  /** True once [url] is fully downloaded. */
  has(url: string): boolean
  /** Downloads [url] (no-op if already there). Throws on failure, leaving no partial file. */
  download(url: string): Promise<void>
  /** Deletes cached files no scheduled playlist or deck uses any more. */
  prune(keepUrls: string[]): Promise<void>
}

export interface Platform {
  kv: KeyValue
  media: MediaStore
  model: string
  appVersion: string
  randomBytes(n: number): Uint8Array
  sleep(ms: number): Promise<void>
  now(): number
}

export interface DownloadProgress { done: number; total: number }

export interface TvUiState {
  /** null until we've heard from the server or loaded a saved copy. */
  device: DeviceState | null
  offline: boolean
  downloading: DownloadProgress | null
  failedDownloads: number
  error: string | null
}

const EMPTY: TvUiState = { device: null, offline: false, downloading: null, failedDownloads: 0, error: null }

const hex = (b: Uint8Array) => Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('')

export function uuidFrom(b: Uint8Array): string {
  const c = Uint8Array.from(b.slice(0, 16))
  c[6] = (c[6] & 0x0f) | 0x40
  c[8] = (c[8] & 0x3f) | 0x80
  const h = hex(c)
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

/** Every remote file the current schedules need, Kids first (soonest first), then Signage, then Slides. */
export function neededMediaUrls(d: DeviceState): string[] {
  const bySoonest = <T extends { starts_at: string }>(a: T[]) => [...a].sort((x, y) => isoMillis(x.starts_at) - isoMillis(y.starts_at))
  const urls = [
    ...bySoonest(d.kids.schedules).flatMap((s) => playlistMediaUrls(s.playlist)),
    ...d.signage.slots.flatMap((s) => playlistMediaUrls(s.playlist)),
    ...(d.signage.default_playlist ? playlistMediaUrls(d.signage.default_playlist) : []),
    ...bySoonest(d.slides.schedules).flatMap((s) => deckMediaUrls(s.deck)),
    ...(d.override?.deck ? deckMediaUrls(d.override.deck) : []),
    ...(d.override?.playlist ? playlistMediaUrls(d.override.playlist) : []),
  ]
  return [...new Set(urls)]
}

export class TvSync {
  readonly state = new Store<TvUiState>(EMPTY)
  private api: Api
  private deviceId = ''
  private secret = ''
  private wake: (() => void) | null = null
  private stopped = false

  constructor(private p: Platform, api?: Api) {
    this.api = api ?? new Api()
  }

  get id() { return this.deviceId }

  /** Loads (or creates) this TV's identity and the last saved state. Call once before run(). */
  async init() {
    this.deviceId = (await this.p.kv.get('device_id')) ?? ''
    if (!this.deviceId) {
      this.deviceId = uuidFrom(this.p.randomBytes(16))
      await this.p.kv.set('device_id', this.deviceId)
    }
    this.secret = (await this.p.kv.get('secret')) ?? ''
    if (!this.secret) {
      this.secret = hex(this.p.randomBytes(32))
      await this.p.kv.set('secret', this.secret)
    }
    const saved = await this.p.kv.get('state')
    if (saved) {
      try {
        this.state.value = { ...this.state.value, device: normalizeState(JSON.parse(saved)) }
      } catch {
        // a damaged saved copy is ignored; the server sends a fresh one
      }
    }
  }

  /** Wakes the slow poll loop (for example when a remote has just asked this TV to play something). */
  refreshNow() { this.wake?.() }

  stop() { this.stopped = true; this.wake?.() }

  /** Forget everything so the TV registers again with a fresh pairing code. */
  async reset() {
    await this.p.kv.clear()
    this.state.value = EMPTY
    await this.init()
    this.refreshNow()
  }

  private update(patch: Partial<TvUiState>) {
    this.state.value = { ...this.state.value, ...patch }
  }

  private waitOrWake(ms: number): Promise<void> {
    return new Promise((resolve) => {
      let done = false
      const finish = () => { if (!done) { done = true; this.wake = null; resolve() } }
      this.wake = finish
      this.p.sleep(ms).then(finish)
    })
  }

  async run() {
    let registered = false
    while (!this.stopped) {
      try {
        if (!registered) {
          await this.api.registerDevice(this.deviceId, this.secret, this.p.model, this.p.appVersion)
          registered = true
        }
        const raw = await this.api.deviceState(this.deviceId, this.secret)
        const device = normalizeState(JSON.parse(raw))
        await this.p.kv.set('state', raw)
        this.update({ device, offline: false, error: null })
        await this.downloadMedia(device)
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e)
        if (message.includes('Unknown device')) {
          // Server no longer knows this TV (e.g. deleted from the dashboard): start over.
          await this.p.kv.clear()
          this.state.value = EMPTY
          await this.init()
          registered = false
        } else {
          this.update({ offline: true, error: message })
        }
      }
      // Poll quickly while waiting to be paired so it feels instant.
      await this.waitOrWake(this.state.value.device?.paired ? 30_000 : 5_000)
    }
  }

  /**
   * Remote control: polls for commands (every 2 s while something is on screen, every 5 s otherwise),
   * and reports what this TV is showing. Failures are silent; run() handles being offline.
   */
  async runRemote() {
    let lastKey = ''
    let lastAt = 0
    let lastOutline: string | null = null
    while (!this.stopped) {
      if (this.state.value.device?.paired) {
        try {
          const raw = await this.api.pollCommands(this.deviceId, this.secret)
          const list = (raw ? JSON.parse(raw) : []) as RawCommand[]
          for (const c of Array.isArray(list) ? list : []) {
            const cmd = parseCommand(c)
            if (!cmd) continue
            if (cmd.type === 'start') this.refreshNow()
            Remote.emit(cmd)
          }
          const msg = Remote.message.value
          const base = Remote.status.value
          const status = msg && msg.untilMs > this.p.now() ? { ...base, state: 'message' as const } : base
          const key = statusKey(status)
          const now = this.p.now()
          if (key !== lastKey || now - lastAt > 15_000) {
            const outline = JSON.stringify(status.outline)
            await this.api.reportStatus(this.deviceId, this.secret, status, outline !== lastOutline || status.state === 'idle')
            lastKey = key
            lastAt = now
            lastOutline = outline
          }
        } catch {
          // offline or a hiccup: try again next round
        }
      }
      await this.p.sleep(Remote.status.value.state === 'idle' ? 5_000 : 2_000)
    }
  }

  private async downloadMedia(device: DeviceState) {
    const urls = neededMediaUrls(device)
    const missing = urls.filter((u) => !this.p.media.has(u))
    let failed = 0
    for (let i = 0; i < missing.length; i++) {
      this.update({ downloading: { done: i, total: missing.length } })
      try {
        await this.p.media.download(missing[i])
      } catch {
        failed++
      }
    }
    this.update({ downloading: null, failedDownloads: failed })
    if (device.paired) await this.p.media.prune(urls)
  }
}
