import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Media, MediaFolder, SignageItem, SignagePlaylist } from '../types'
import { attempt, fetchAll, moveItem, must, scopeLabel, useLoad } from '../lib'
import { ScopeSelect, useDefaultScope } from '../ui'
import { MediaSelect } from '../MediaSelect'

export default function SignagePlaylistsPage() {
  const { org, sites, canEditContent } = useApp()
  const defaultScope = useDefaultScope()
  const [editing, setEditing] = useState<SignagePlaylist | 'new' | null>(null)

  const { data, reload } = useLoad(async () => {
    const [playlists, media, folders] = await Promise.all([
      supabase.from('signage_playlists').select('*').eq('organization_id', org.id).order('updated_at', { ascending: false }),
      fetchAll<Media>((a, b) => supabase.from('media').select('*').eq('organization_id', org.id).eq('module', 'signage').order('title').range(a, b)),
      fetchAll<MediaFolder>((a, b) => supabase.from('media_folders').select('*').eq('organization_id', org.id).eq('module', 'signage').order('name').range(a, b)),
    ])
    return { playlists: must(playlists) as SignagePlaylist[], media, folders }
  })

  if (editing) {
    return (
      <Editor
        playlist={editing === 'new' ? null : editing}
        media={data?.media ?? []}
        folders={data?.folders ?? []}
        onDone={() => (setEditing(null), reload())}
      />
    )
  }

  async function duplicate(p: SignagePlaylist) {
    const ok = await attempt(async () =>
      must(await supabase.from('signage_playlists').insert({ organization_id: org.id, site_id: p.site_id, name: `${p.name} (copy)`, items: p.items })),
    )
    if (ok) reload()
  }

  async function remove(p: SignagePlaylist) {
    if (!confirm(`Delete "${p.name}"? Its slots will be removed too.`)) return
    if (await attempt(async () => must(await supabase.from('signage_playlists').delete().eq('id', p.id)))) reload()
  }

  const playlists = data?.playlists ?? []

  return (
    <div className="stack">
      {canEditContent('signage', defaultScope) && (
        <div>
          <button className="btn primary" onClick={() => setEditing('new')}>
            + New playlist
          </button>
        </div>
      )}
      {playlists.length === 0 && <p className="muted">No Signage playlists yet.</p>}
      {playlists.map((p) => {
        const canEdit = canEditContent('signage', p.site_id)
        const seconds = p.items.reduce((t, i) => t + (i.type === 'image' ? i.seconds ?? 10 : 0), 0)
        return (
          <div key={p.id} className="card row spread wrap-sm">
            <div>
              <h3>{p.name}</h3>
              <span className="muted">
                {p.items.length} items · {scopeLabel(p.site_id, sites)}
                {seconds > 0 && ` · about ${Math.round(seconds / 60 * 10) / 10} min of images`}
              </span>
            </div>
            {canEdit && (
              <div className="row">
                <button className="btn" onClick={() => setEditing(p)}>
                  Edit
                </button>
                <button className="btn" onClick={() => duplicate(p)}>
                  Duplicate
                </button>
                <button className="btn danger" onClick={() => remove(p)}>
                  Delete
                </button>
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}

function Editor({ playlist, media, folders, onDone }: { playlist: SignagePlaylist | null; media: Media[]; folders: MediaFolder[]; onDone: () => void }) {
  const { org } = useApp()
  const defaultScope = useDefaultScope()
  const [name, setName] = useState(playlist?.name ?? '')
  const [scope, setScope] = useState(playlist ? playlist.site_id : defaultScope)
  const [items, setItems] = useState<SignageItem[]>(playlist?.items ?? [])
  const [saving, setSaving] = useState(false)

  const update = (i: number, item: SignageItem) => setItems((list) => list.map((x, j) => (j === i ? item : x)))

  const add = (type: SignageItem['type']) =>
    setItems((list) => [...list, { type, title: '', url: '', seconds: type === 'image' ? 10 : null, media_id: '' }])

  function pick(i: number, item: SignageItem, mediaId: string) {
    const m = media.find((x) => x.id === mediaId)
    if (m) update(i, { ...item, media_id: m.id, url: m.url, title: m.title })
  }

  async function save() {
    if (!name.trim()) return alert('Give the playlist a name.')
    const missing = items.findIndex((i) => !i.url)
    if (missing >= 0) return alert(`Item ${missing + 1} needs an image or video chosen.`)
    setSaving(true)
    const row = { organization_id: org.id, name: name.trim(), site_id: scope, items }
    const ok = await attempt(async () =>
      must(
        playlist
          ? await supabase.from('signage_playlists').update(row).eq('id', playlist.id)
          : await supabase.from('signage_playlists').insert(row),
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
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Lobby · Weekday loop" autoFocus />
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
              {i + 1}. {item.type === 'image' ? 'Image' : 'Video'}
            </span>
            <span className="row">
              <button className="icon" onClick={() => setItems((l) => moveItem(l, i, -1))} disabled={i === 0} title="Move up">
                ↑
              </button>
              <button className="icon" onClick={() => setItems((l) => moveItem(l, i, 1))} disabled={i === items.length - 1} title="Move down">
                ↓
              </button>
              <button className="icon danger" onClick={() => setItems((l) => l.filter((_, j) => j !== i))} title="Remove">
                ✕
              </button>
            </span>
          </div>
          <div className="row wrap">
            {item.url && (item.type === 'image' ? <img className="thumb" src={item.url} alt="" /> : <video className="thumb" src={`${item.url}#t=1`} preload="metadata" muted />)}
            <label className="field grow">
              <span>{item.type === 'image' ? 'Image' : 'Video'} from the library</span>
              <MediaSelect media={media} folders={folders} kind={item.type} value={item.media_id} onChange={(id) => pick(i, item, id)} />
            </label>
            {item.type === 'image' && (
              <label className="field">
                <span>Show for (seconds)</span>
                <input
                  type="number"
                  min={1}
                  style={{ width: 110 }}
                  value={item.seconds ?? ''}
                  onChange={(e) => update(i, { ...item, seconds: e.target.value ? Number(e.target.value) : 10 })}
                />
              </label>
            )}
            {item.type === 'video' && <span className="muted">Plays to the end</span>}
          </div>
        </div>
      ))}

      <div className="card row wrap">
        <span className="muted">Add:</span>
        <button className="btn" onClick={() => add('image')}>
          + Image
        </button>
        <button className="btn" onClick={() => add('video')}>
          + Video
        </button>
        {media.length === 0 && <span className="muted">Upload images and videos under Signage, then Media, first.</span>}
      </div>

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
