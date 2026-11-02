// What a phone, the website or the assistant can ask this TV to do (see the database function send_screen_command),
// and what the TV reports back. Mirrors tv-app Remote.kt.

export type RemoteCommand =
  | { type: 'next' }
  | { type: 'previous' }
  | { type: 'jump'; index: number }
  /** on null toggles. */
  | { type: 'blank'; on: boolean | null }
  | { type: 'stop' }
  /** The server has recorded a play-now override; fetch it right away. */
  | { type: 'start' }
  | { type: 'message'; text: string; seconds: number; background: string }
  | { type: 'clear_message' }

export interface RawCommand { id?: number; command: string; payload?: Record<string, unknown> | null }

const int = (v: unknown) => (typeof v === 'number' && Number.isInteger(v) ? v : null)

/** Unknown or malformed commands are ignored (null), so a newer server never breaks an older TV. */
export function parseCommand(c: RawCommand): RemoteCommand | null {
  const p = c.payload ?? {}
  switch (c.command) {
    case 'next': return { type: 'next' }
    case 'previous': return { type: 'previous' }
    case 'jump': {
      const index = int(p.index)
      return index === null ? null : { type: 'jump', index }
    }
    case 'blank': return { type: 'blank', on: typeof p.on === 'boolean' ? p.on : null }
    case 'stop': return { type: 'stop' }
    case 'start': return { type: 'start' }
    case 'message': {
      const text = typeof p.text === 'string' ? p.text : ''
      if (!text.trim()) return null
      const seconds = Math.min(300, Math.max(5, int(p.seconds) ?? 30))
      return { type: 'message', text, seconds, background: typeof p.background === 'string' ? p.background : '#1B2A4A' }
    }
    case 'clear_message': return { type: 'clear_message' }
    default: return null
  }
}

/** What this TV is showing, reported to the server so remotes can display it. */
export interface PlaybackStatus {
  module: string
  state: 'idle' | 'playing' | 'blank' | 'message'
  title: string
  label: string
  index: number
  count: number
  outline: string[]
  refKind: string | null
  refId: string | null
}

export const IDLE: PlaybackStatus = {
  module: '', state: 'idle', title: '', label: '', index: 0, count: 0, outline: [], refKind: null, refId: null,
}

/** A message sign currently covering the screen. */
export interface ActiveMessage { text: string; background: string; untilMs: number }

/** Changes in this key (or 15 s passing) trigger a status report. */
export function statusKey(s: PlaybackStatus): string {
  return [s.module, s.state, s.title, s.index, s.count, s.label].join('|')
}

type Listener<T> = (value: T) => void

/** A value the screens and the network loop share (Kotlin's MutableStateFlow). */
export class Store<T> {
  private listeners = new Set<Listener<T>>()
  constructor(private current: T) {}
  get value(): T { return this.current }
  set value(v: T) {
    if (v === this.current) return
    this.current = v
    this.listeners.forEach((l) => l(v))
  }
  subscribe(l: Listener<T>): () => void {
    this.listeners.add(l)
    return () => { this.listeners.delete(l) }
  }
}

/** The meeting point between the network loop (sync) and whatever is on screen. */
export const Remote = {
  commandListeners: new Set<Listener<RemoteCommand>>(),
  emit(c: RemoteCommand) { Remote.commandListeners.forEach((l) => l(c)) },
  onCommand(l: Listener<RemoteCommand>): () => void {
    Remote.commandListeners.add(l)
    return () => { Remote.commandListeners.delete(l) }
  },
  status: new Store<PlaybackStatus>(IDLE),
  message: new Store<ActiveMessage | null>(null),
  idle() { Remote.status.value = IDLE },
}
