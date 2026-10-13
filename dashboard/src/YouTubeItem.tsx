import { useState } from 'react'
import type { PlaylistItem } from './types'
import { useLoad } from './lib'
import { useApp } from './context'
import type { YouTubeEntry } from '../api/youtube'

type YouTubeItem = Extract<PlaylistItem, { type: 'youtube' }>

/** channelId = the church's YouTube channel (Settings). Without one the item starts in "Choose a video" mode. */
export const newYouTubeItem = (channelId: string | null, churchName = 'Live now'): YouTubeItem => ({
  type: 'youtube',
  title: channelId ? `${churchName} · Live now` : '',
  video_id: null,
  channel_id: channelId,
  start: null,
})

/** Accepts watch, youtu.be, /live/, /embed/ and /shorts/ links, or a bare 11-character id. */
export function parseYouTubeId(input: string): string | null {
  const text = input.trim()
  if (/^[\w-]{11}$/.test(text)) return text
  try {
    const url = new URL(text)
    if (url.hostname.endsWith('youtu.be')) return url.pathname.slice(1, 12) || null
    const v = url.searchParams.get('v')
    if (v) return v
    return url.pathname.match(/\/(?:live|embed|shorts)\/([\w-]{11})/)?.[1] ?? null
  } catch {
    return null
  }
}

const thumb = (id: string) => `https://i.ytimg.com/vi/${id}/mqdefault.jpg`
const fmtDate = (iso: string) =>
  new Date(iso).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })

function fmtStart(seconds: number | null) {
  if (!seconds) return ''
  const h = Math.floor(seconds / 3600)
  const m = Math.floor((seconds % 3600) / 60)
  const s = String(seconds % 60).padStart(2, '0')
  return h ? `${h}:${String(m).padStart(2, '0')}:${s}` : `${m}:${s}`
}

function parseStart(text: string): number | null {
  const parts = text.trim().split(':').map(Number)
  if (!text.trim() || parts.some(isNaN)) return null
  return parts.reduce((total, n) => total * 60 + n, 0)
}

export function YouTubeItemEditor({ item, onChange }: { item: YouTubeItem; onChange: (item: YouTubeItem) => void }) {
  const { org } = useApp()
  const orgChannel = org.branding.youtube_channel_id || null
  const channel = orgChannel ?? item.channel_id
  const live = item.video_id === null && item.channel_id !== null
  const [link, setLink] = useState('')
  const [linkError, setLinkError] = useState<string | null>(null)
  const [startText, setStartText] = useState(fmtStart(item.start))

  const { data, error } = useLoad(async () => {
    if (!channel) return [] as YouTubeEntry[]
    const res = await fetch(`/api/youtube?kind=streams&channel=${encodeURIComponent(channel)}`)
    const body = await res.json()
    if (!res.ok) throw new Error(body.error)
    return body.items as YouTubeEntry[]
  }, [channel])

  const choose = (id: string, title: string) => onChange({ ...item, video_id: id, channel_id: null, title })

  async function useLink() {
    const id = parseYouTubeId(link)
    if (!id) return setLinkError("That doesn't look like a YouTube link.")
    setLinkError(null)
    const res = await fetch(`/api/youtube?video=${id}`).then((r) => r.json()).catch(() => ({ title: null }))
    choose(id, res.title ?? 'YouTube video')
    setLink('')
  }

  return (
    <div className="stack-sm">
      <div className="segmented">
        <button
          className={live ? 'on' : ''}
          disabled={!orgChannel}
          title={orgChannel ? '' : 'Add your YouTube channel in Settings first'}
          onClick={() => onChange(newYouTubeItem(orgChannel, org.name))}
        >
          Live now
        </button>
        <button
          className={!live ? 'on' : ''}
          onClick={() => !live || onChange({ ...item, video_id: null, channel_id: null, title: '' })}
        >
          Choose a video
        </button>
      </div>

      {live ? (
        <p className="muted">
          Plays whatever {org.name} is live-streaming on YouTube when this item comes up. If nothing is live, the
          TV says so and the volunteer can skip it.
        </p>
      ) : (
        <>
          {item.video_id && (
            <div className="row chosen">
              <img src={thumb(item.video_id)} alt="" />
              <div className="stack-sm">
                <b>{item.title}</b>
                <a href={`https://youtu.be/${item.video_id}`} target="_blank" rel="noreferrer" className="muted">
                  Preview on YouTube ↗
                </a>
              </div>
            </div>
          )}
          <span className="field-label">Recent {org.name} streams</span>
          {!channel && <p className="muted">Add your church's YouTube channel in Settings to pick from recent streams. You can still paste a link below.</p>}
          {error && <p className="error">Couldn't load streams: {error}</p>}
          {channel && !data && !error && <p className="muted">Loading streams…</p>}
          <div className="yt-grid">
            {data?.map((v) => (
              <button
                key={v.id}
                className={`yt-tile ${item.video_id === v.id ? 'on' : ''}`}
                onClick={() => choose(v.id, `${v.title} · ${fmtDate(v.published)}`)}
              >
                <img src={thumb(v.id)} alt="" loading="lazy" />
                <span>{fmtDate(v.published)}</span>
              </button>
            ))}
          </div>
          <div className="row wrap">
            <label className="field grow">
              <span>Or paste any YouTube link</span>
              <input
                value={link}
                onChange={(e) => setLink(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && useLink()}
                placeholder="https://www.youtube.com/watch?v=…"
              />
            </label>
            <button className="btn align-end" onClick={useLink}>
              Use link
            </button>
          </div>
          {linkError && <p className="error">{linkError}</p>}
          <label className="field">
            <span>Start at (optional)</span>
            <input
              value={startText}
              placeholder="e.g. 12:30"
              style={{ width: 140 }}
              onChange={(e) => setStartText(e.target.value)}
              onBlur={() => {
                const start = parseStart(startText)
                setStartText(fmtStart(start))
                onChange({ ...item, start })
              }}
            />
          </label>
        </>
      )}
    </div>
  )
}
