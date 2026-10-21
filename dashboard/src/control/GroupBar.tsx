import { useState } from 'react'
import type { Screen } from '../types'
import { sendCommand, type CommandName } from './commands'
import MessageForm from './MessageForm'

type Failure = { name: string; error: string }

/** Sends one command to every ticked screen and reports per-screen failures. */
export default function GroupBar({ screens, selected, refresh }: { screens: Screen[]; selected: string[]; refresh: () => void }) {
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState<string | null>(null)
  const [failures, setFailures] = useState<Failure[]>([])
  const [showMsg, setShowMsg] = useState(false)
  const chosen = screens.filter((s) => selected.includes(s.id))
  const n = chosen.length

  async function fan(label: string, command: CommandName, payload: Record<string, unknown> = {}): Promise<boolean> {
    if (busy || n === 0) return false
    setBusy(true)
    setDone(null)
    const results = await Promise.all(chosen.map(async (s) => ({ s, r: await sendCommand(s.id, command, payload) })))
    const bad = results.flatMap(({ s, r }) => (r.ok ? [] : [{ name: s.name ?? 'Unnamed screen', error: r.error }]))
    setFailures(bad)
    setDone(`${label}: sent to ${n - bad.length} of ${n} screen${n === 1 ? '' : 's'}.`)
    window.setTimeout(() => setBusy(false), 300)
    window.setTimeout(refresh, 1500)
    return bad.length === 0
  }

  return (
    <div className="ctl-groupbar card stack-sm">
      <b>
        {n === 0 ? 'Tick the screens to control' : `${n} screen${n === 1 ? '' : 's'} selected`}
      </b>
      <div className="row wrap ctl-row2">
        <button className="btn" disabled={busy || !n} onClick={() => fan('Previous', 'previous')}>
          ◀ Previous
        </button>
        <button className="btn primary" disabled={busy || !n} onClick={() => fan('Next', 'next')}>
          Next ▶
        </button>
        <button className="btn" disabled={busy || !n} onClick={() => fan('Blank on', 'blank', { on: true })}>
          Blank on
        </button>
        <button className="btn" disabled={busy || !n} onClick={() => fan('Blank off', 'blank', { on: false })}>
          Blank off
        </button>
        <button
          className="btn danger"
          disabled={busy || !n}
          onClick={() => window.confirm(`Stop playback on ${n} screen${n === 1 ? '' : 's'}? This also ends any "Play now".`) && void fan('Stop', 'stop')}
        >
          Stop
        </button>
        <button className="btn" disabled={!n} aria-expanded={showMsg} onClick={() => setShowMsg((v) => !v)}>
          Message…
        </button>
      </div>
      {showMsg && n > 0 && (
        <MessageForm
          disabled={busy}
          pending={busy}
          onSend={(p) => fan('Message', 'message', p)}
          onClear={() => void fan('Clear message', 'clear_message')}
        />
      )}
      {done && <p className={failures.length ? 'notice warn' : 'notice'}>{done}</p>}
      {failures.length > 0 && (
        <ul className="ctl-log">
          {failures.map((f, i) => (
            <li key={i} className="bad">
              <b>{f.name}</b>
              <div className="error">{f.error}</div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
