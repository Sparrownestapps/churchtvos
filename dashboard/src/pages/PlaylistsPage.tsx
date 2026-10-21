import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Media, MediaFolder, Playlist, PlaylistItem } from '../types'
import { attempt, fetchAll, moveItem, must, scopeLabel, useLoad } from '../lib'
import { EmptyState, ScopeSelect, useDefaultScope } from '../ui'
import { MediaSelect } from '../MediaSelect'
import CountdownFields from '../CountdownFields'
import { countdownProblem } from '../slides/render'
import { YouTubeItemEditor, newYouTubeItem } from '../YouTubeItem'
import { StreamItemEditor, newStreamItem, validStreamUrl } from '../StreamItem'
import { NdiItemEditor, NDI_LABEL, cleanNdi, newNdiItem, ndiProblem } from '../NdiItem'
import { LyricsItemEditor, newLyricsItem, type SongLite } from '../LyricsItem'

const KIND_LABEL: Record<PlaylistItem['type'], string> = {
  video: 'Video',
  image: 'Slide',
  countdown: 'Countdown',
  lyrics: 'Lyrics',
  youtube: 'YouTube',
  stream: 'Live stream',
  ndi: NDI_LABEL,
}

export default function PlaylistsPage() {
  const { org, sites, canEditContent } = useApp()
  const defaultScope = useDefaultScope()
  const [editing, setEditing] = useState<Playlist | 'new' | null>(null)

  const { data, reload } = useLoad(async () => {
    const [playlists, media, folders, songs] = await Promise.all([
      supabase.from('playlists').select('*').eq('organization_id', org.id).order('updated_at', { ascending: false }),
      fetchAll<Media>((a, b) => supabase.from('media').select('*').eq('organization_id', org.id).eq('module', 'kids').order('title').range(a, b)),
      fetchAll<MediaFolder>((a, b) => supabase.from('media_folders').select('*').eq('organization_id', org.id).eq('module', 'kids').order('name').range(a, b)),
      // The song library is optional here: if it can't be read, typed lyrics still work.
      fetchAll<SongLite>((a, b) => supabase.from('songs').select('id,title,sections,arrangement,lines_per_slide').eq('organization_id', org.id).order('title').range(a, b)).catch(() => [] as SongLite[]),
    ])
    return { playlists: must(playlists) as Playlist[], media, folders, songs }
  })

  if (editing) {
    return (
      <PlaylistEditor
        playlist={editing === 'new' ? null : editing}
        media={data?.media ?? []}
        folders={data?.folders ?? []}
        songs={data?.songs ?? []}
        onDone={() => (setEditing(null), reload())}
      />
    )
  }

  async function duplicate(p: Playlist) {
    const ok = await attempt(async () =>
      must(await supabase.from('playlists').insert({ organization_id: org.id, site_id: p.site_id, name: `${p.name} (copy)`, items: p.items })),
    )
    if (ok) reload()
  }

  async function remove(p: Playlist) {
    if (!confirm(`Delete "${p.name}"? It will also be removed from any schedules.`)) return
    if (await attempt(async () => must(await supabase.from('playlists').delete().eq('id', p.id)))) reload()
  }

  const playlists = data?.playlists ?? []

  return (
    <div className="stack">
      {canEditContent('kids', defaultScope) && (
        <div>
          <button className="btn primary" onClick={() => setEditing('new')}>
            + New playlist
          </button>
        </div>
      )}
      {playlists.length === 0 && (
        <EmptyState help="kids">
          A playlist is what a Kids room plays, in order: videos, slides, a countdown, lyrics. Add media first, then press New playlist.
        </EmptyState>
      )}
      {playlists.map((p) => {
        const canEdit = canEditContent('kids', p.site_id)
        return (
          <div key={p.id} className="card row spread">
            <div>
              <h3>{p.name}</h3>
              <span className="muted">
                {p.items.length} items · {scopeLabel(p.site_id, sites)} ·{' '}
                {p.items.map((i) => KIND_LABEL[i.type]).join(', ') || 'empty'}
              </span>
            </div>
            <div className="row">
              {canEdit && (
                <button className="btn" onClick={() => setEditing(p)}>
                  Edit
                </button>
              )}
              {canEditContent('kids', p.site_id) && (
                <button className="btn" onClick={() => duplicate(p)}>
                  Duplicate
                </button>
              )}
              {canEdit && (
                <button className="btn danger" onClick={() => remove(p)}>
                  Delete
                </button>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}

function PlaylistEditor({ playlist, media, folders, songs, onDone }: { playlist: Playlist | null; media: Media[]; folders: MediaFolder[]; songs: SongLite[]; onDone: () => void }) {
  const { org } = useApp()
  const defaultScope = useDefaultScope()
  const channelId = org.branding.youtube_channel_id || null
  const [name, setName] = useState(playlist?.name ?? '')
  const [scope, setScope] = useState(playlist ? playlist.site_id : defaultScope)
  const [items, setItems] = useState<PlaylistItem[]>(playlist?.items ?? [])
  const [saving, setSaving] = useState(false)

  const update = (i: number, item: PlaylistItem) => setItems((list) => list.map((x, j) => (j === i ? item : x)))
  const move = (i: number, by: number) => setItems((list) => moveItem(list, i, by))
  const removeItem = (i: number) => setItems((list) => list.filter((_, j) => j !== i))

  function add(type: PlaylistItem['type']) {
    const blank: Record<PlaylistItem['type'], PlaylistItem> = {
      video: { type: 'video', title: '', url: '', media_id: '' },
      image: { type: 'image', title: '', url: '', media_id: '', seconds: null },
      countdown: { type: 'countdown', title: 'Service starts in', mode: 'duration', seconds: 300, at_zero: 'hold', if_passed: 'zero' },
      lyrics: newLyricsItem(),
      youtube: newYouTubeItem(channelId, org.name),
      stream: newStreamItem(null),
      ndi: newNdiItem(),
    }
    setItems((list) => [...list, blank[type]])
  }

  function pickMedia(i: number, item: PlaylistItem, mediaId: string) {
    const m = media.find((x) => x.id === mediaId)
    if (!m || (item.type !== 'video' && item.type !== 'image')) return
    update(i, { ...item, media_id: m.id, url: m.url, title: m.title })
  }

  async function save() {
    const missing = items.findIndex((i) => (i.type === 'video' || i.type === 'image') && !i.url)
    if (!name.trim()) return alert('Give the playlist a name.')
    if (missing >= 0) return alert(`Item ${missing + 1} needs a video or slide chosen.`)
    const noYouTube = items.findIndex((i) => i.type === 'youtube' && !i.video_id && !i.channel_id)
    if (noYouTube >= 0) return alert(`Item ${noYouTube + 1} needs a YouTube video chosen.`)
    const badStream = items.findIndex((i) => i.type === 'stream' && !validStreamUrl(i.url))
    if (badStream >= 0) return alert(`Item ${badStream + 1} needs a stream link (starting with https://).`)
    const badNdi = items.findIndex((i) => i.type === 'ndi' && ndiProblem(i))
    if (badNdi >= 0) return alert(`Item ${badNdi + 1}: ${ndiProblem(items[badNdi] as Extract<PlaylistItem, { type: 'ndi' }>)}`)
    const badCountdown = items.findIndex((i) => i.type === 'countdown' && countdownProblem(i))
    if (badCountdown >= 0) return alert(`Item ${badCountdown + 1}: ${countdownProblem(items[badCountdown] as Extract<PlaylistItem, { type: 'countdown' }>)}`)
    const noSong = items.findIndex((i) => i.type === 'lyrics' && 'song_id' in i && !i.song_id)
    if (noSong >= 0) return alert(`Item ${noSong + 1} needs a song chosen from the library (or switch it to typed lyrics).`)
    const cleaned = items.map((i) =>
      i.type === 'lyrics' && 'slides' in i ? { ...i, slides: i.slides.map((s) => s.trim()).filter(Boolean) } : i.type === 'ndi' ? cleanNdi(i) : i,
    )
    setSaving(true)
    const row = { organization_id: org.id, name: name.trim(), site_id: scope, items: cleaned }
    const ok = await attempt(async () =>
      must(
        playlist
          ? await supabase.from('playlists').update(row).eq('id', playlist.id)
          : await supabase.from('playlists').insert(row),
      ),
    )
    setSaving(false)
    if (ok) onDone()
  }

  return (
    <div className="stack">
      <div className="card row wrap">
        <label className="field grow">
          <span>Playlist name</span>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Elementary · Week 3" autoFocus />
        </label>
        <label className="field">
          <span>Available to</span>
          <ScopeSelect value={scope} onChange={setScope} />
        </label>
      </div>

      {items.map((item, i) => (
        <div key={i} className="card item">
          <div className="item-head">
            <span className="tag">
              {i + 1}. {KIND_LABEL[item.type]}
            </span>
            <span className="row">
              <button className="icon" onClick={() => move(i, -1)} disabled={i === 0} title="Move up">
                ↑
              </button>
              <button className="icon" onClick={() => move(i, 1)} disabled={i === items.length - 1} title="Move down">
                ↓
              </button>
              <button className="icon danger" onClick={() => removeItem(i)} title="Remove">
                ✕
              </button>
            </span>
          </div>

          {(item.type === 'video' || item.type === 'image') && (
            <div className="row wrap">
              <label className="field grow">
                <span>{item.type === 'video' ? 'Video' : 'Slide'}</span>
                <MediaSelect media={media} folders={folders} kind={item.type} value={item.media_id} onChange={(id) => pickMedia(i, item, id)} />
              </label>
              {item.type === 'image' && (
                <label className="field">
                  <span>Auto-advance after (sec)</span>
                  <input
                    type="number"
                    min={1}
                    placeholder="Wait for remote"
                    value={item.seconds ?? ''}
                    onChange={(e) => update(i, { ...item, seconds: e.target.value ? Number(e.target.value) : null })}
                  />
                </label>
              )}
            </div>
          )}

          {item.type === 'countdown' && (
            <CountdownFields value={item} onPatch={(p) => update(i, { ...item, ...p, title: p.title ?? item.title })} media={media} folders={folders} />
          )}

          {item.type === 'stream' && <StreamItemEditor item={item} onChange={(next) => update(i, next)} />}

          {item.type === 'ndi' &&
            (org.ndi_enabled ? (
              <NdiItemEditor item={item} onChange={(next) => update(i, next)} />
            ) : (
              <p className="note warn">NDI sources are switched off for this church, so this item is not shown on the TV and cannot be changed. You can remove it.</p>
            ))}

          {item.type === 'youtube' && <YouTubeItemEditor item={item} onChange={(next) => update(i, next)} />}

          {item.type === 'lyrics' && <LyricsItemEditor item={item} songs={songs} onChange={(next) => update(i, next)} />}
        </div>
      ))}

      <div className="card row wrap">
        <span className="muted">Add:</span>
        <button className="btn" onClick={() => add('video')}>
          + Video
        </button>
        <button className="btn" onClick={() => add('image')}>
          + Slide
        </button>
        <button className="btn" onClick={() => add('countdown')}>
          + Countdown
        </button>
        <button className="btn" onClick={() => add('lyrics')}>
          + Lyrics
        </button>
        <button className="btn" onClick={() => add('youtube')}>
          + YouTube
        </button>
        <button className="btn" onClick={() => add('stream')}>
          + Live stream
        </button>
        {org.ndi_enabled && (
          <button className="btn" onClick={() => add('ndi')} title="Experimental: needs the special NDI build of the TV app">
            + {NDI_LABEL}
          </button>
        )}
      </div>
      <p className="muted">
        Tip: for screens turned to portrait, use portrait media (1080 x 1920). YouTube items don't rotate on portrait screens.
      </p>

      <div className="row">
        <button className="btn primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : 'Save playlist'}
        </button>
        <button className="btn" onClick={onDone}>
          Cancel
        </button>
      </div>
    </div>
  )
}
