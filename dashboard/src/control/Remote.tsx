import { useEffect, useRef, useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Screen } from '../types'
import { MODULE_NAME, locationLabel } from '../lib'
import { useSender } from './commands'
import MessageForm from './MessageForm'
import { MIN_CONTROL_VERSION, STATE_LABEL, agoLabel, currentOutlineIndex, isOnline, shownState, versionOk, type ScreenStatus } from './logic'

type Item = { id: string; name: string }
const DURATIONS = [
  { minutes: 30, label: '30 minutes' },
  { minutes: 60, label: '1 hour' },
  { minutes: 120, label: '2 hours' },
  { minutes: 240, label: '4 hours' },
  { minutes: 1440, label: 'Until I stop it' },
]

/** The live remote for one screen. */
export default function Remote({
  screen,
  status,
  now,
  refresh,
  onClose,
}: {
  screen: Screen
  status: ScreenStatus | undefined
  now: number
  refresh: () => void
  onClose: () => void
}) {
  const { org, sites, locations, moduleOn } = useApp()
  const { run, busy, disabled, log } = useSender(screen.id, refresh)
  const online = isOnline(screen.last_seen_at, now)
  const state = shownState(screen, status, now)
  const blank = state === 'blank'
  const outline = state === 'idle' || state === 'offline' ? null : status?.outline ?? null
  const current = state === 'idle' || state === 'offline' ? -1 : currentOutlineIndex(status)
  const closeRef = useRef<HTMLButtonElement>(null)

  // Keyboard: Right/Space next, Left previous, B blank, Esc close.
  const keys = useRef<(e: KeyboardEvent) => void>(() => {})
  keys.current = (e) => {
    const t = e.target as HTMLElement | null
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return
    if (e.metaKey || e.ctrlKey || e.altKey) return
    if (e.key === 'Escape') return onClose()
    if (e.key === ' ' && t?.tagName === 'BUTTON') return
    if (e.key === 'ArrowRight' || e.key === ' ') {
      e.preventDefault()
      void run('Next', 'next')
    } else if (e.key === 'ArrowLeft') {
      e.preventDefault()
      void run('Previous', 'previous')
    } else if (e.key === 'b' || e.key === 'B') {
      e.preventDefault()
      void run(blank ? 'Screen on' : 'Blank', 'blank', { on: !blank })
    }
  }
  useEffect(() => {
    const h = (e: KeyboardEvent) => keys.current(e)
    window.addEventListener('keydown', h)
    closeRef.current?.focus()
    return () => window.removeEventListener('keydown', h)
  }, [])

  // Play now: the church's decks and playlists.
  const [decks, setDecks] = useState<Item[]>([])
  const [lists, setLists] = useState<Item[]>([])
  const [libError, setLibError] = useState<string | null>(null)
  useEffect(() => {
    let off = false
    ;(async () => {
      const [d, p] = await Promise.all([
        moduleOn('slides') ? supabase.from('decks').select('id, name').eq('organization_id', org.id).order('name') : null,
        moduleOn('kids') ? supabase.from('playlists').select('id, name').eq('organization_id', org.id).order('name') : null,
      ])
      if (off) return
      if (d?.error || p?.error) setLibError((d?.error ?? p?.error)!.message)
      setDecks((d?.data as Item[] | null) ?? [])
      setLists((p?.data as Item[] | null) ?? [])
    })()
    return () => {
      off = true
    }
  }, [org.id, moduleOn])
  const [pick, setPick] = useState('')
  const [minutes, setMinutes] = useState(240)

  async function playNow() {
    const [kind, id] = pick.split(':')
    const name = (kind === 'deck' ? decks : lists).find((x) => x.id === id)?.name ?? 'this'
    const until = DURATIONS.find((d) => d.minutes === minutes)?.label.toLowerCase()
    if (!window.confirm(`Play "${name}" on ${screen.name ?? 'this screen'} now?\n\nThis replaces the schedule on that screen until you press Stop or it runs out (${until}).`)) return
    await run(`Play now: ${name}`, 'start', { kind, id, minutes })
  }
  async function stop() {
    if (!window.confirm('Stop playback on this screen? This also ends any "Play now".')) return
    await run('Stop', 'stop')
  }

  const listRef = useRef<HTMLOListElement>(null)
  useEffect(() => {
    const el = listRef.current?.querySelector<HTMLElement>('[aria-current="true"]')
    const box = listRef.current
    if (el && box) box.scrollTop = el.offsetTop - box.offsetTop - box.clientHeight / 2 + el.clientHeight / 2
  }, [current, outline?.length])

  const loc = locationLabel(locations.find((l) => l.id === screen.location_id), sites)
  const pending = (label: string) => busy === label
  const label = (text: string, key: string) => (pending(key) ? 'Sending…' : text)

  return (
    <>
      <div className="ctl-scrim" onClick={onClose} />
      <aside className="ctl-remote" role="dialog" aria-label={`Remote for ${screen.name ?? 'screen'}`}>
        <header className="ctl-remote-head">
          <div>
            <h2>{screen.name ?? 'Unnamed screen'}</h2>
            <div className="muted">
              {loc} · {MODULE_NAME[status?.module ?? screen.default_module]}
            </div>
          </div>
          <button ref={closeRef} className="btn" onClick={onClose} aria-label="Close remote">
            Close
          </button>
        </header>

        {!online && <p className="ctl-warn">This TV is offline. Commands are dropped after about a minute, so a TV that comes back later will not replay them.</p>}
        {!versionOk(screen.app_version) && (
          <p className="ctl-warn">
            This TV runs app {screen.app_version ?? 'an unknown version'}. It needs {MIN_CONTROL_VERSION} or newer to obey commands.
          </p>
        )}

        <div className="ctl-now">
          <span className={`ctl-chip s-${state}`}>{STATE_LABEL[state]}</span>
          <div>
            <b>{state === 'idle' || state === 'offline' ? 'Nothing reported' : status?.title || 'Untitled'}</b>
            {state !== 'idle' && state !== 'offline' && status?.item_label && <div className="muted">{status.item_label}</div>}
            {state !== 'idle' && state !== 'offline' && status?.slide_index != null && status.slide_count ? (
              <div className="muted">
                Slide {status.slide_index + 1} of {status.slide_count}
              </div>
            ) : null}
            <div className="muted">Updated {agoLabel(status?.updated_at, now)}</div>
          </div>
        </div>

        <div className="ctl-big">
          <button className="btn ctl-bigbtn" disabled={disabled} onClick={() => run('Previous', 'previous')}>
            {label('◀ Previous', 'Previous')}
          </button>
          <button className="btn primary ctl-bigbtn" disabled={disabled} onClick={() => run('Next', 'next')}>
            {label('Next ▶', 'Next')}
          </button>
        </div>
        <div className="row wrap ctl-row2">
          <button className={`btn ${blank ? 'primary' : ''}`} disabled={disabled} aria-pressed={blank} onClick={() => run(blank ? 'Screen on' : 'Blank', 'blank', { on: !blank })}>
            {pending('Blank') || pending('Screen on') ? 'Sending…' : blank ? 'Blank: on (tap to show)' : 'Blank screen'}
          </button>
          <button className="btn danger" disabled={disabled} onClick={stop}>
            {label('Stop', 'Stop')}
          </button>
        </div>
        <p className="muted ctl-keys">Keys: Right or Space = next · Left = previous · B = blank · Esc = close</p>

        <section className="stack-sm">
          <h3>Jump to slide</h3>
          {outline && outline.length > 0 ? (
            <ol className="ctl-outline" ref={listRef}>
              {outline.map((text, i) => (
                <li key={i}>
                  <button
                    className={`ctl-slide ${i === current ? 'on' : ''}`}
                    aria-current={i === current ? 'true' : undefined}
                    disabled={disabled}
                    onClick={() => run(`Jump to ${i + 1}`, 'jump', { index: i })}
                  >
                    <span className="ctl-num">{i + 1}</span>
                    <span className="ctl-slide-text">{text || `Slide ${i + 1}`}</span>
                  </button>
                </li>
              ))}
            </ol>
          ) : (
            <p className="muted">The list appears once the TV is playing and reporting its slides (app {MIN_CONTROL_VERSION} or newer).</p>
          )}
        </section>

        <section className="stack-sm">
          <h3>Play now</h3>
          {decks.length === 0 && lists.length === 0 ? (
            <p className="muted">{libError ? `Could not load your library: ${libError}` : 'No decks or playlists to choose from.'}</p>
          ) : (
            <>
              <div className="row wrap">
                <label className="field grow">
                  <span>What to play</span>
                  <select value={pick} onChange={(e) => setPick(e.target.value)}>
                    <option value="">Choose…</option>
                    {decks.length > 0 && (
                      <optgroup label="Slides decks">
                        {decks.map((d) => (
                          <option key={d.id} value={`deck:${d.id}`}>
                            {d.name}
                          </option>
                        ))}
                      </optgroup>
                    )}
                    {lists.length > 0 && (
                      <optgroup label="Kids playlists">
                        {lists.map((p) => (
                          <option key={p.id} value={`playlist:${p.id}`}>
                            {p.name}
                          </option>
                        ))}
                      </optgroup>
                    )}
                  </select>
                </label>
                <label className="field">
                  <span>For</span>
                  <select value={minutes} onChange={(e) => setMinutes(Number(e.target.value))}>
                    {DURATIONS.map((d) => (
                      <option key={d.minutes} value={d.minutes}>
                        {d.label}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              <button className="btn primary" disabled={disabled || !pick} onClick={playNow}>
                {pending(`Play now: ${(pick.startsWith('deck') ? decks : lists).find((x) => x.id === pick.split(':')[1])?.name}`) ? 'Sending…' : 'Play now'}
              </button>
              <p className="muted">Replaces the schedule on this screen until you press Stop or the time runs out.</p>
            </>
          )}
        </section>

        <section className="stack-sm">
          <h3>Send a message</h3>
          <MessageForm
            disabled={disabled}
            pending={pending('Message')}
            onSend={(p) => run('Message', 'message', p)}
            onClear={() => void run('Clear message', 'clear_message')}
          />
        </section>

        <section className="stack-sm">
          <h3>Sent from here</h3>
          {log.length === 0 ? (
            <p className="muted">Nothing yet.</p>
          ) : (
            <ul className="ctl-log">
              {log.map((l) => (
                <li key={l.id} className={l.ok ? 'ok' : 'bad'}>
                  <span aria-hidden="true">{l.ok ? '✓' : '✕'}</span> <b>{l.label}</b>
                  <span className="muted"> · {l.at.toLocaleTimeString()}</span>
                  {l.error && <div className="error">{l.error}</div>}
                </li>
              ))}
            </ul>
          )}
        </section>
      </aside>
    </>
  )
}
