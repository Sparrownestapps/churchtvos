import { useState, type DragEvent } from 'react'
import * as tus from 'tus-js-client'
import { useApp } from '../context'
import { SUPABASE_KEY, SUPABASE_URL, supabase } from '../supabase'
import type { Media } from '../types'
import { attempt, fmtBytes, must, randomName, scopeLabel, useLoad } from '../lib'
import { ReadOnlyNote, ScopeSelect, useDefaultScope } from '../ui'

type Upload = { id: string; name: string; percent: number; error?: string }

export default function MediaPage() {
  const { org, sites, canEditContent } = useApp()
  // Media is shared by Kids and Signage: editing either module is enough.
  const canEdit = (siteId: string | null) => canEditContent('kids', siteId) || canEditContent('signage', siteId)
  const canUpload = canEdit(useDefaultScope()) || sites.some((s) => canEdit(s.id))
  const [scope, setScope] = useState(useDefaultScope())
  const [uploads, setUploads] = useState<Upload[]>([])
  const [dragging, setDragging] = useState(false)
  const [filter, setFilter] = useState('')

  const { data: media, reload } = useLoad(
    async () => must(await supabase.from('media').select('*').eq('organization_id', org.id).order('created_at', { ascending: false })) as Media[],
  )

  const patch = (id: string, change: Partial<Upload>) =>
    setUploads((list) => list.map((u) => (u.id === id ? { ...u, ...change } : u)))

  async function upload(file: File) {
    const id = crypto.randomUUID()
    setUploads((list) => [...list, { id, name: file.name, percent: 0 }])
    const kind = file.type.startsWith('video/') ? 'video' : file.type.startsWith('image/') ? 'image' : null
    if (!kind) return patch(id, { error: 'Only videos and images can be uploaded' })

    try {
      const path = `${org.id}/${randomName(file.name)}`
      const { data } = await supabase.auth.getSession()
      // Resumable upload: survives flaky Wi-Fi and handles large curriculum videos.
      await new Promise<void>((resolve, reject) => {
        new tus.Upload(file, {
          endpoint: `${SUPABASE_URL}/storage/v1/upload/resumable`,
          retryDelays: [0, 3000, 5000, 10000, 20000],
          headers: { authorization: `Bearer ${data.session?.access_token}`, apikey: SUPABASE_KEY, 'x-upsert': 'false' },
          uploadDataDuringCreation: true,
          removeFingerprintOnSuccess: true,
          chunkSize: 6 * 1024 * 1024, // Supabase requires exactly 6 MB chunks
          metadata: { bucketName: 'media', objectName: path, contentType: file.type, cacheControl: '3600' },
          onProgress: (sent, total) => patch(id, { percent: Math.round((sent / total) * 100) }),
          onError: reject,
          onSuccess: () => resolve(),
        }).start()
      })
      const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl
      must(
        await supabase.from('media').insert({
          organization_id: org.id,
          site_id: scope,
          title: file.name.replace(/\.[^.]+$/, ''),
          kind,
          storage_path: path,
          url,
          size_bytes: file.size,
        }),
      )
      setUploads((list) => list.filter((u) => u.id !== id))
      reload()
    } catch (e) {
      const message = (e as Error).message
      patch(id, {
        error: /maximum allowed size|413|too large/i.test(message)
          ? 'File is larger than your Supabase plan allows (50 MB on the free plan)'
          : message,
      })
    }
  }

  function onDrop(e: DragEvent) {
    e.preventDefault()
    setDragging(false)
    Array.from(e.dataTransfer.files).forEach(upload)
  }

  async function rename(m: Media) {
    const title = prompt('Rename media', m.title)?.trim()
    if (!title || title === m.title) return
    if (await attempt(async () => must(await supabase.from('media').update({ title }).eq('id', m.id)))) reload()
  }

  async function remove(m: Media) {
    if (!confirm(`Delete "${m.title}"? Playlists using it will skip it.`)) return
    const ok = await attempt(async () => {
      must(await supabase.storage.from('media').remove([m.storage_path]))
      must(await supabase.from('media').delete().eq('id', m.id))
    })
    if (ok) reload()
  }

  const visible = (media ?? [])
    .filter((m) => m.title.toLowerCase().includes(filter.toLowerCase()))

  return (
    <div className="stack">
      {!canUpload && <ReadOnlyNote />}
      {canUpload && <div className="card">
        <div className="row">
          <span>Upload to</span>
          <ScopeSelect value={scope} onChange={setScope} />
        </div>
        <label
          className={`drop ${dragging ? 'dragging' : ''}`}
          onDragOver={(e) => (e.preventDefault(), setDragging(true))}
          onDragLeave={() => setDragging(false)}
          onDrop={onDrop}
        >
          <input
            type="file"
            multiple
            accept="video/*,image/*"
            hidden
            onChange={(e) => (Array.from(e.target.files ?? []).forEach(upload), (e.target.value = ''))}
          />
          <b>Drop videos or images here</b>
          <span className="muted">or click to choose files · MP4 video and JPG/PNG slides work best (1920×1080)</span>
        </label>
        {uploads.map((u) => (
          <div key={u.id} className="upload">
            <span>{u.name}</span>
            {u.error ? (
              <>
                <span className="error">{u.error}</span>
                <button className="link" onClick={() => setUploads((l) => l.filter((x) => x.id !== u.id))}>
                  Dismiss
                </button>
              </>
            ) : (
              <progress value={u.percent} max={100} />
            )}
          </div>
        ))}
      </div>}

      <div className="card">
        <div className="row spread">
          <h3>Library</h3>
          <input placeholder="Search…" value={filter} onChange={(e) => setFilter(e.target.value)} />
        </div>
        {visible.length === 0 ? (
          <p className="muted">No media yet. Upload your first video or slide above.</p>
        ) : (
          <div className="media-grid">
            {visible.map((m) => (
              <div key={m.id} className="media-tile">
                {m.kind === 'image' ? (
                  <img src={m.url} alt="" loading="lazy" />
                ) : (
                  <video src={`${m.url}#t=1`} preload="metadata" muted />
                )}
                <div className="media-info">
                  <b title={m.title}>{m.title}</b>
                  <span className="muted">
                    {m.kind === 'video' ? 'Video' : 'Slide'} · {fmtBytes(m.size_bytes)} · {scopeLabel(m.site_id, sites)}
                  </span>
                  {canEdit(m.site_id) && (
                    <span className="row">
                      <button className="link" onClick={() => rename(m)}>
                        Rename
                      </button>
                      <button className="link danger" onClick={() => remove(m)}>
                        Delete
                      </button>
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
