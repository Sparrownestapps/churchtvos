import { useState } from 'react'
import type { StreamItem } from './types'

export const NEEDS_APP_NOTE = 'Needs the Church TV OS app version 1.1.0 or newer on the TV.'

export const newStreamItem = (seconds: number | null): StreamItem => ({
  type: 'stream',
  title: '',
  url: '',
  seconds,
  audio: false,
  fallback: 'skip',
})

/** Quick sanity check used when saving: an http(s) link. */
export const validStreamUrl = (u: string) => /^https?:\/\/\S+$/i.test(u.trim())

type Result = { kind: 'ok' | 'hint'; text: string } | null

/** Editor for a live HLS stream item, shared by the Kids and Signage playlist editors. */
export function StreamItemEditor({ item, onChange }: { item: StreamItem; onChange: (next: StreamItem) => void }) {
  const [testing, setTesting] = useState(false)
  const [result, setResult] = useState<Result>(null)
  const patch = (p: Partial<StreamItem>) => onChange({ ...item, ...p })

  async function test() {
    const url = item.url.trim()
    if (!validStreamUrl(url)) return setResult({ kind: 'hint', text: 'Paste a full link starting with https:// first.' })
    setTesting(true)
    setResult(null)
    const ctl = new AbortController()
    const timer = setTimeout(() => ctl.abort(), 8000)
    try {
      const res = await fetch(url, { cache: 'no-store', signal: ctl.signal })
      if (!res.ok) {
        setResult({ kind: 'hint', text: `The server answered ${res.status}. Check the link, and that the broadcast is live.` })
      } else {
        const head = (await res.text()).slice(0, 200)
        setResult(
          head.trimStart().startsWith('#EXTM3U')
            ? { kind: 'ok', text: 'The link answered and looks like an HLS stream.' }
            : { kind: 'hint', text: "The link answered, but it doesn't look like an .m3u8 stream playlist. Double-check you copied the M3U8 link." },
        )
      }
    } catch {
      setResult({
        kind: 'hint',
        text: "Couldn't check this link from the browser. That's common (the server may block browser checks, or the stream isn't live yet) and doesn't mean it's broken. The TV may still play it.",
      })
    } finally {
      clearTimeout(timer)
      setTesting(false)
    }
  }

  return (
    <div className="stack-sm">
      <div className="note">{NEEDS_APP_NOTE}</div>
      <label className="field">
        <span>Title</span>
        <input value={item.title} onChange={(e) => patch({ title: e.target.value })} placeholder="e.g. Sunday service live" />
      </label>
      <div className="row wrap">
        <label className="field grow">
          <span>Stream link (HLS, .m3u8)</span>
          <input
            type="url"
            inputMode="url"
            value={item.url}
            onChange={(e) => (patch({ url: e.target.value }), setResult(null))}
            placeholder="https://…/playlist.m3u8"
          />
        </label>
        <button type="button" className="btn align-end" onClick={test} disabled={testing || !item.url.trim()}>
          {testing ? 'Testing…' : 'Test link'}
        </button>
      </div>
      {result && <p className={`test-result ${result.kind}`}>{result.text}</p>}
      <div className="row wrap">
        <label className="field">
          <span>Show for (seconds)</span>
          <input
            type="number"
            min={1}
            style={{ width: 130 }}
            placeholder="Until next"
            value={item.seconds ?? ''}
            onChange={(e) => patch({ seconds: e.target.value ? Math.max(1, Number(e.target.value)) : null })}
          />
        </label>
        <label className="field">
          <span>If the stream is down</span>
          <select value={item.fallback} onChange={(e) => patch({ fallback: e.target.value as StreamItem['fallback'] })}>
            <option value="skip">Skip it</option>
            <option value="hold">Show "waiting for feed"</option>
          </select>
        </label>
        <label className="check align-end">
          <input type="checkbox" checked={item.audio} onChange={(e) => patch({ audio: e.target.checked })} />
          Play sound
        </label>
      </div>
      <p className="help">
        Leave the time blank to keep the stream up until the next item is chosen (Kids) or the playlist loops past it (Signage).
        <b> Skip it</b> moves straight on if the stream isn't running, so a room is never left blank.
        <b> Show "waiting for feed"</b> holds a waiting card for a little while before moving on, which suits a stream that starts a few minutes late.
        Sound is off unless you turn it on.
      </p>
      <details className="help">
        <summary>Using BoxCast?</summary>
        <ul>
          <li>In BoxCast open the broadcast, choose Embed, and copy the Static M3U8 link into the box above.</li>
          <li>BoxCast viewers are about 30 to 40 seconds behind real life, so don't use it for lyrics or anything that has to be in sync with the room.</li>
          <li>For a near-live feed from the building, use a camera or switcher converted to HLS (for example with OBS or Nimble Streamer).</li>
        </ul>
      </details>
    </div>
  )
}
