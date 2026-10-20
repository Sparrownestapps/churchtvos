import { useState } from 'react'
import type { CountdownAudio } from './slidesTypes'
import type { Media, MediaFolder } from './types'
import { MediaSelect } from './MediaSelect'

export const COUNTDOWN_NEEDS_APP = 'Audio and countdown-to-a-time need Church TV OS app version 1.4.0 or newer on the TV.'

/** The countdown settings shared by a Slides countdown slide and a Kids countdown item. */
export type CountdownValue = {
  title?: string
  mode?: 'duration' | 'until'
  seconds?: number
  until?: string
  audio?: CountdownAudio | null
  at_zero?: 'next' | 'hold'
  if_passed?: 'skip' | 'zero'
}

/** Editor for a countdown (title, how long or until when, what happens at the end, and optional audio). `media`/`folders` are the module's library. */
export default function CountdownFields({
  value,
  onPatch,
  media,
  folders,
}: {
  value: CountdownValue
  onPatch: (p: Partial<CountdownValue>) => void
  media: Media[]
  folders: MediaFolder[]
}) {
  const [search, setSearch] = useState('')
  const mode = value.mode ?? 'duration'
  const seconds = value.seconds ?? 0
  const audio = value.audio ?? null
  const q = search.trim().toLowerCase()
  const tracks = media.filter((m) => m.kind === 'audio' && (!q || m.title.toLowerCase().includes(q) || m.id === audio?.media_id))
  const patchAudio = (p: Partial<CountdownAudio>) => audio && onPatch({ audio: { ...audio, ...p } })

  function pick(id: string) {
    const m = media.find((x) => x.id === id)
    if (!m) return onPatch({ audio: null })
    onPatch({ audio: { volume: 0.8, loop: true, fade_seconds: 3, align_end: false, ...audio, media_id: m.id, url: m.url } })
  }

  return (
    <div className="stack-sm">
      <label className="field">
        <span>Heading</span>
        <input value={value.title ?? ''} onChange={(e) => onPatch({ title: e.target.value })} placeholder="e.g. Service starts in" />
      </label>

      <div className="row wrap">
        <label className="field">
          <span>Count down</span>
          <select value={mode} onChange={(e) => onPatch({ mode: e.target.value as 'duration' | 'until', ...(e.target.value === 'until' && !value.until ? { until: '09:00' } : {}), ...(e.target.value === 'duration' && !(seconds > 0) ? { seconds: 300 } : {}) })}>
            <option value="duration">For a set time</option>
            <option value="until">To a clock time</option>
          </select>
        </label>
        {mode === 'duration' ? (
          <>
            <label className="field">
              <span>Minutes</span>
              <input type="number" min={0} style={{ width: 100 }} value={Math.floor(seconds / 60)} onChange={(e) => onPatch({ seconds: Math.max(0, Number(e.target.value) || 0) * 60 + (seconds % 60) })} />
            </label>
            <label className="field">
              <span>Seconds</span>
              <input type="number" min={0} max={59} style={{ width: 100 }} value={seconds % 60} onChange={(e) => onPatch({ seconds: Math.floor(seconds / 60) * 60 + Math.min(59, Math.max(0, Number(e.target.value) || 0)) })} />
            </label>
          </>
        ) : (
          <label className="field">
            <span>Counts down to</span>
            <input type="time" value={value.until ?? ''} onChange={(e) => onPatch({ until: e.target.value })} />
          </label>
        )}
      </div>
      {mode === 'until' && <p className="help">Today, in your site's time zone.</p>}

      <div className="row wrap">
        {mode === 'until' && (
          <label className="field">
            <span>If that time has already passed</span>
            <select value={value.if_passed ?? 'zero'} onChange={(e) => onPatch({ if_passed: e.target.value as 'skip' | 'zero' })}>
              <option value="zero">Show 0:00</option>
              <option value="skip">Skip this slide</option>
            </select>
          </label>
        )}
        <label className="field">
          <span>When it reaches zero</span>
          <select value={value.at_zero ?? 'next'} onChange={(e) => onPatch({ at_zero: e.target.value as 'next' | 'hold' })}>
            <option value="hold">Stay on 0:00 until I press Next (recommended)</option>
            <option value="next">Go to the next slide automatically</option>
          </select>
        </label>
      </div>

      <div className="stack-sm">
        <span className="field-label">Audio</span>
        <div className="row wrap">
          <label className="field grow">
            <span>Search audio</span>
            <input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Part of a file name" />
          </label>
          <label className="field grow">
            <span>Audio file</span>
            <MediaSelect media={tracks} folders={folders} kind="audio" value={audio?.media_id ?? ''} onChange={pick} />
          </label>
        </div>
        {media.every((m) => m.kind !== 'audio') && <p className="help">No audio files yet. Upload an MP3 or M4A on this module's Media page, then come back.</p>}
        {audio && (
          <div className="stack-sm">
            {audio.url && <audio controls preload="none" src={audio.url} style={{ width: '100%', maxWidth: 420 }} />}
            <div className="row wrap">
              <label className="field grow">
                <span>Volume: {Math.round((audio.volume ?? 0.8) * 100)}%</span>
                <input type="range" min={0} max={100} step={5} value={Math.round((audio.volume ?? 0.8) * 100)} onChange={(e) => patchAudio({ volume: Number(e.target.value) / 100 })} />
              </label>
              <label className="field">
                <span>Fade out over the last (sec)</span>
                <input type="number" min={0} max={10} style={{ width: 100 }} value={audio.fade_seconds ?? 3} onChange={(e) => patchAudio({ fade_seconds: Math.min(10, Math.max(0, Number(e.target.value) || 0)) })} />
              </label>
            </div>
            <label className="check">
              <input type="checkbox" checked={audio.loop ?? true} onChange={(e) => patchAudio({ loop: e.target.checked })} />
              Repeat until zero
            </label>
            <label className="check">
              <input type="checkbox" checked={audio.align_end ?? false} onChange={(e) => patchAudio({ align_end: e.target.checked })} />
              Finish exactly at zero
            </label>
            <p className="help">Starts a shorter track late so it ends right when the countdown reaches 0:00; if the track is longer, it starts partway through.</p>
            <div>
              <button type="button" className="btn danger" onClick={() => onPatch({ audio: null })}>
                Remove audio
              </button>
            </div>
          </div>
        )}
      </div>
      <p className="note">{COUNTDOWN_NEEDS_APP}</p>
    </div>
  )
}
