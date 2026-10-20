import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import * as tus from 'tus-js-client'
import { useApp } from '../context'
import { SUPABASE_KEY, SUPABASE_URL, supabase } from '../supabase'
import type { Media, MediaFolder, Module } from '../types'
import { attempt, fetchAll, fmtBytes, folderPath, must, randomName, scopeLabel, useLoad } from '../lib'
import { EmptyState, ReadOnlyNote, ScopeSelect, useDefaultScope } from '../ui'

type Upload = { id: string; name: string; percent: number; error?: string }
type View = 'grid' | 'list'
type Usage = { media_id: string; playlist_names: string[] }
type Stats = { module: string; files: number; bytes: number }

/** Drag payload for moving files between folders (a JSON array of media ids). */
const DRAG_TYPE = 'application/x-churchtvos-media'
const VIEW_KEY = 'churchtvos.mediaView'

const readView = (): View => {
  try {
    return localStorage.getItem(VIEW_KEY) === 'list' ? 'list' : 'grid'
  } catch {
    return 'grid'
  }
}

/** Throws a readable message for folder writes (e.g. a duplicate name). */
function folderOk(res: { error: { message: string } | null }) {
  if (!res.error) return
  throw new Error(/media_folders_unique_name|duplicate key/.test(res.error.message) ? 'A folder with that name already exists here.' : res.error.message)
}

/** First frame of a video, loaded only once it scrolls near the screen (keeps big libraries light). */
function VideoPoster({ url }: { url: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const [on, setOn] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el || typeof IntersectionObserver === 'undefined') return setOn(true)
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setOn(true)
          io.disconnect()
        }
      },
      { rootMargin: '200px' },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [])
  return (
    <div ref={ref} className="poster">
      {on && <video src={`${url}#t=0.5`} preload="metadata" muted playsInline />}
      <span className="play">▶</span>
    </div>
  )
}

function Thumb({ m }: { m: Media }) {
  return m.kind === 'image' ? <img src={m.url} alt="" loading="lazy" draggable={false} /> : <VideoPoster url={m.url} />
}

/** Dialog for choosing a destination folder. */
function FolderPicker({
  title,
  folders,
  exclude,
  currentId,
  onPick,
  onClose,
}: {
  title: string
  folders: MediaFolder[]
  /** Folders that can't be chosen (a folder and everything inside it). */
  exclude: Set<string>
  currentId?: string | null
  onPick: (id: string | null) => void
  onClose: () => void
}) {
  const children = (parent: string | null) =>
    folders.filter((f) => f.parent_id === parent).sort((a, b) => a.name.localeCompare(b.name))
  const rows: { id: string | null; name: string; depth: number }[] = [{ id: null, name: 'Library (top level)', depth: 0 }]
  const walk = (parent: string | null, depth: number) => {
    for (const f of children(parent)) {
      if (exclude.has(f.id)) continue
      rows.push({ id: f.id, name: f.name, depth })
      walk(f.id, depth + 1)
    }
  }
  walk(null, 1)
  return (
    <div className="modal-scrim" onClick={onClose}>
      <div className="modal card stack-sm" role="dialog" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="row spread">
          <h3>{title}</h3>
          <button className="link" onClick={onClose}>
            Cancel
          </button>
        </div>
        <div className="picker-list">
          {rows.map((r) => (
            <button
              key={r.id ?? 'root'}
              className="picker-row"
              style={{ paddingLeft: 12 + r.depth * 18 }}
              disabled={r.id === currentId}
              onClick={() => onPick(r.id)}
            >
              {r.id ? '📁 ' : ''}
              {r.name}
              {r.id === currentId && <span className="muted"> (current)</span>}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

export default function MediaPage({ module }: { module: Module }) {
  const { org, sites, allSites, canEditContent, moduleName } = useApp()
  const canEdit = (siteId: string | null) => canEditContent(module, siteId)
  const defaultScope = useDefaultScope()
  const canUpload = canEdit(defaultScope) || sites.some((s) => canEdit(s.id))

  const [folderId, setFolderId] = useState<string | null>(null)
  const [view, setViewState] = useState<View>(readView)
  const [filter, setFilter] = useState('')
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [uploads, setUploads] = useState<Upload[]>([])
  const [dragging, setDragging] = useState(false)
  const [dropTarget, setDropTarget] = useState<string | null>(null)
  const [scope, setScope] = useState(defaultScope)
  const [newFolder, setNewFolder] = useState<{ name: string; site: string | null } | null>(null)
  const [picker, setPicker] = useState<{ kind: 'files'; ids: string[] } | { kind: 'folder'; folder: MediaFolder } | null>(null)
  const [openUsage, setOpenUsage] = useState<string | null>(null)

  const { data, error, reload } = useLoad(async () => {
    const [media, folders, usage, stats] = await Promise.all([
      fetchAll<Media>((a, b) =>
        supabase.from('media').select('*').eq('organization_id', org.id).eq('module', module).order('created_at', { ascending: false }).order('id').range(a, b),
      ),
      fetchAll<MediaFolder>((a, b) =>
        supabase.from('media_folders').select('*').eq('organization_id', org.id).eq('module', module).order('name').order('id').range(a, b),
      ),
      supabase.rpc('media_usage', { p_org: org.id, p_module: module }),
      supabase.rpc('media_storage_by_module', { p_org: org.id }),
    ])
    // Usage and totals are nice-to-have: a failure there must not hide the library.
    return {
      media,
      folders,
      usage: usage.error ? [] : ((usage.data ?? []) as Usage[]),
      stats: stats.error ? undefined : ((stats.data ?? []) as Stats[]).find((s) => s.module === module),
    }
  }, [module])

  const media = data?.media ?? []
  const folders = useMemo(() => data?.folders ?? [], [data])
  const byId = useMemo(() => new Map(folders.map((f) => [f.id, f])), [folders])
  const usage = useMemo(() => new Map((data?.usage ?? []).map((u) => [u.media_id, u.playlist_names])), [data])

  // A folder that was deleted (or can't be seen any more) falls back to the top level.
  const here = folderId && byId.has(folderId) ? folderId : null
  const current = here ? byId.get(here) : undefined
  const crumbs: MediaFolder[] = []
  for (let f = current; f && crumbs.length < 100; f = f.parent_id ? byId.get(f.parent_id) : undefined) crumbs.unshift(f)

  const q = filter.trim().toLowerCase()
  const subfolders = q ? [] : folders.filter((f) => f.parent_id === here).sort((a, b) => a.name.localeCompare(b.name))
  const files = q ? media.filter((m) => m.title.toLowerCase().includes(q)) : media.filter((m) => m.folder_id === here)
  const fileIds = new Set(media.map((m) => m.id))
  const chosen = [...selected].filter((id) => fileIds.has(id))

  const descendants = (id: string) => {
    const out = new Set<string>([id])
    for (let grew = true; grew; ) {
      grew = false
      for (const f of folders) if (f.parent_id && out.has(f.parent_id) && !out.has(f.id)) (out.add(f.id), (grew = true))
    }
    return out
  }

  const setView = (v: View) => {
    setViewState(v)
    try {
      localStorage.setItem(VIEW_KEY, v)
    } catch {
      /* not remembered */
    }
  }
  const open = (id: string | null) => {
    setFolderId(id)
    setSelected(new Set())
    setFilter('')
  }
  const toggle = (id: string) =>
    setSelected((s) => {
      const next = new Set(s)
      if (!next.delete(id)) next.add(id)
      return next
    })

  const patch = (id: string, change: Partial<Upload>) =>
    setUploads((list) => list.map((u) => (u.id === id ? { ...u, ...change } : u)))

  // ───────── Upload ─────────

  async function upload(file: File) {
    const id = crypto.randomUUID()
    setUploads((list) => [...list, { id, name: file.name, percent: 0 }])
    const kind = file.type.startsWith('video/') ? 'video' : file.type.startsWith('image/') ? 'image' : null
    if (!kind) return patch(id, { error: 'Only videos and images can be uploaded' })
    // A folder limited to one site passes that limit to what is inside it.
    const siteId = current ? current.site_id : scope
    if (!canEdit(siteId)) return patch(id, { error: "You can't upload here" })

    let path = ''
    try {
      path = `${org.id}/${randomName(file.name)}`
      const objectName = path
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
          metadata: { bucketName: 'media', objectName, contentType: file.type, cacheControl: '3600' },
          onProgress: (sent, total) => patch(id, { percent: Math.round((sent / total) * 100) }),
          onError: reject,
          onSuccess: () => resolve(),
        }).start()
      })
      const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl
      const res = await supabase.from('media').insert({
        organization_id: org.id,
        module,
        folder_id: here,
        site_id: siteId,
        title: file.name.replace(/\.[^.]+$/, ''),
        kind,
        storage_path: path,
        url,
        size_bytes: file.size,
      })
      if (res.error) {
        await supabase.storage.from('media').remove([path]) // don't leave an unlisted file behind
        throw new Error(res.error.message)
      }
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

  const hasFiles = (e: DragEvent) => Array.from(e.dataTransfer.types).includes('Files')

  function onDropFiles(e: DragEvent) {
    e.preventDefault()
    setDragging(false)
    Array.from(e.dataTransfer.files).forEach(upload)
  }

  // ───────── Files ─────────

  async function rename(m: Media) {
    const title = prompt('Rename file', m.title)?.trim()
    if (!title || title === m.title) return
    if (await attempt(async () => must(await supabase.from('media').update({ title }).eq('id', m.id).eq('organization_id', org.id)))) reload()
  }

  /** Deletes the row first (the server refuses if a playlist uses it), and only then the stored file. */
  async function deleteFile(m: Media) {
    const { data: gone, error } = await supabase.from('media').delete().eq('id', m.id).eq('organization_id', org.id).select('id')
    if (error) throw new Error(error.message)
    if (!gone?.length) throw new Error(`Couldn't delete "${m.title}". You may not have permission.`)
    await supabase.storage.from('media').remove([m.storage_path]) // a leftover file is harmless; a missing one would break playlists
  }

  async function remove(m: Media) {
    if (!confirm(`Delete "${m.title}"? This can't be undone.`)) return
    const ok = await attempt(() => deleteFile(m))
    setSelected((s) => (s.delete(m.id), new Set(s)))
    reload()
    return ok
  }

  async function removeSelected() {
    const list = media.filter((m) => chosen.includes(m.id) && canEdit(m.site_id))
    if (list.length === 0 || !confirm(`Delete ${list.length} file${list.length === 1 ? '' : 's'}? This can't be undone.`)) return
    const failed: string[] = []
    for (const m of list) {
      try {
        await deleteFile(m)
      } catch (e) {
        failed.push((e as Error).message)
      }
    }
    if (failed.length) alert(`${failed.length} of ${list.length} couldn't be deleted:\n\n${failed.slice(0, 5).join('\n')}`)
    setSelected(new Set())
    reload()
  }

  async function moveFiles(ids: string[], target: string | null) {
    const movable = media.filter((m) => ids.includes(m.id) && m.folder_id !== target && canEdit(m.site_id)).map((m) => m.id)
    if (movable.length === 0) return
    const ok = await attempt(async () =>
      must(await supabase.from('media').update({ folder_id: target }).in('id', movable).eq('organization_id', org.id).eq('module', module)),
    )
    if (ok) {
      setSelected(new Set())
      reload()
    }
  }

  // ───────── Folders ─────────

  async function createFolder() {
    if (!newFolder?.name.trim()) return
    const site = current ? current.site_id : newFolder.site
    const ok = await attempt(async () =>
      folderOk(
        await supabase
          .from('media_folders')
          .insert({ organization_id: org.id, module, parent_id: here, site_id: site, name: newFolder.name.trim() }),
      ),
    )
    if (ok) {
      setNewFolder(null)
      reload()
    }
  }

  async function renameFolder(f: MediaFolder) {
    const name = prompt('Rename folder', f.name)?.trim()
    if (!name || name === f.name) return
    if (await attempt(async () => folderOk(await supabase.from('media_folders').update({ name }).eq('id', f.id).eq('organization_id', org.id)))) reload()
  }

  async function moveFolder(f: MediaFolder, target: string | null) {
    setPicker(null)
    if (target === f.parent_id) return
    if (await attempt(async () => folderOk(await supabase.from('media_folders').update({ parent_id: target }).eq('id', f.id).eq('organization_id', org.id)))) reload()
  }

  async function removeFolder(f: MediaFolder) {
    const parent = f.parent_id ? byId.get(f.parent_id)?.name : null
    if (
      !confirm(
        `Delete the folder "${f.name}"?\n\nNothing inside it is deleted: its files and sub-folders move up one level to ${parent ? `"${parent}"` : 'the top of the library'}.`,
      )
    )
      return
    if (await attempt(async () => must(await supabase.from('media_folders').delete().eq('id', f.id).eq('organization_id', org.id)))) {
      if (here === f.id) open(f.parent_id)
      reload()
    }
  }

  // ───────── Drag and drop onto folders ─────────

  const dropProps = (target: string | null, key: string) => ({
    onDragOver: (e: DragEvent) => {
      if (!Array.from(e.dataTransfer.types).includes(DRAG_TYPE)) return
      e.preventDefault()
      setDropTarget(key)
    },
    onDragLeave: () => setDropTarget((t) => (t === key ? null : t)),
    onDrop: (e: DragEvent) => {
      const raw = e.dataTransfer.getData(DRAG_TYPE)
      setDropTarget(null)
      if (!raw) return
      e.preventDefault()
      try {
        moveFiles(JSON.parse(raw) as string[], target)
      } catch {
        /* not ours */
      }
    },
  })

  const dragProps = (m: Media) =>
    canEdit(m.site_id)
      ? {
          draggable: true,
          onDragStart: (e: DragEvent) => {
            const ids = selected.has(m.id) ? chosen : [m.id]
            e.dataTransfer.setData(DRAG_TYPE, JSON.stringify(ids))
            e.dataTransfer.effectAllowed = 'move'
          },
        }
      : {}

  // ───────── Rendering ─────────

  const usageLabel = (m: Media) => {
    const names = usage.get(m.id)
    if (!names?.length) return null
    return (
      <>
        <button className="link" title={names.join(', ')} onClick={() => setOpenUsage(openUsage === m.id ? null : m.id)}>
          Used in {names.length} playlist{names.length === 1 ? '' : 's'}
        </button>
        {openUsage === m.id && <span className="muted usage-names">{names.join(', ')}</span>}
      </>
    )
  }

  const fileActions = (m: Media) =>
    canEdit(m.site_id) && (
      <span className="row wrap-sm">
        <button className="link" onClick={() => rename(m)}>
          Rename
        </button>
        <button className="link" onClick={() => setPicker({ kind: 'files', ids: [m.id] })}>
          Move to…
        </button>
        <button className="link danger" onClick={() => remove(m)}>
          Delete
        </button>
      </span>
    )

  const folderActions = (f: MediaFolder) =>
    canEdit(f.site_id) && (
      <span className="row wrap-sm">
        <button className="link" onClick={() => renameFolder(f)}>
          Rename
        </button>
        <button className="link" onClick={() => setPicker({ kind: 'folder', folder: f })}>
          Move to…
        </button>
        <button className="link danger" onClick={() => removeFolder(f)}>
          Delete
        </button>
      </span>
    )

  const itemCount = (f: MediaFolder) =>
    media.filter((m) => m.folder_id === f.id).length + folders.filter((x) => x.parent_id === f.id).length

  const stats = data?.stats
  const empty = subfolders.length === 0 && files.length === 0

  return (
    <div className="stack">
      {!canUpload && <ReadOnlyNote />}
      {error && <p className="error">Couldn't load the library: {error}</p>}

      {canUpload && (
        <div className="card">
          <div className="row wrap-sm">
            <span>
              Upload to <b>{current ? folderPath(current.id, byId) : 'top level'}</b>
            </span>
            {current ? (
              <span className="muted">· {current.site_id ? `${scopeLabel(current.site_id, sites)} only (set by this folder)` : 'All sites'}</span>
            ) : (
              <ScopeSelect value={scope} onChange={setScope} />
            )}
          </div>
          <label
            className={`drop ${dragging ? 'dragging' : ''}`}
            onDragOver={(e) => hasFiles(e) && (e.preventDefault(), setDragging(true))}
            onDragLeave={() => setDragging(false)}
            onDrop={onDropFiles}
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
        </div>
      )}

      <div className="card stack-sm">
        <div className="row spread wrap-sm">
          <h3>{moduleName(module)} library</h3>
          <span className="muted">
            {stats ? `${Number(stats.files)} files · ${fmtBytes(Number(stats.bytes))} used` : data ? `${media.length} files` : ''}
          </span>
        </div>

        <div className="row spread wrap-sm">
          <nav className="crumbs" aria-label="Folder path">
            <button className={`crumb ${dropTarget === 'root' ? 'drop-on' : ''}`} disabled={!here} onClick={() => open(null)} {...dropProps(null, 'root')}>
              Library
            </button>
            {crumbs.map((c, i) => (
              <span key={c.id} className="row">
                <span className="muted">/</span>
                <button
                  className={`crumb ${dropTarget === c.id ? 'drop-on' : ''}`}
                  disabled={i === crumbs.length - 1}
                  onClick={() => open(c.id)}
                  {...dropProps(c.id, c.id)}
                >
                  {c.name}
                </button>
              </span>
            ))}
          </nav>
          <div className="row wrap-sm">
            <input placeholder="Search this library…" value={filter} onChange={(e) => setFilter(e.target.value)} />
            <span className="segmented" role="group" aria-label="View">
              <button className={view === 'grid' ? 'on' : ''} onClick={() => setView('grid')}>
                Grid
              </button>
              <button className={view === 'list' ? 'on' : ''} onClick={() => setView('list')}>
                List
              </button>
            </span>
            {canUpload && !q && (
              <button className="btn" onClick={() => setNewFolder(newFolder ? null : { name: '', site: defaultScope })}>
                + New folder
              </button>
            )}
          </div>
        </div>

        {newFolder && (
          <div className="row wrap panel">
            <label className="field grow">
              <span>Folder name{here ? ` (inside ${current?.name})` : ''}</span>
              <input
                autoFocus
                value={newFolder.name}
                onChange={(e) => setNewFolder({ ...newFolder, name: e.target.value })}
                onKeyDown={(e) => e.key === 'Enter' && createFolder()}
                placeholder="e.g. Curriculum"
              />
            </label>
            {allSites && !current?.site_id && (
              <label className="field">
                <span>Available to</span>
                <ScopeSelect value={newFolder.site} onChange={(site) => setNewFolder({ ...newFolder, site })} />
              </label>
            )}
            <button className="btn primary align-end" onClick={createFolder}>
              Create
            </button>
            <button className="btn align-end" onClick={() => setNewFolder(null)}>
              Cancel
            </button>
          </div>
        )}

        {canUpload && chosen.length > 0 && (
          <div className="row wrap-sm selection-bar">
            <b>{chosen.length} selected</b>
            <button className="link" onClick={() => setPicker({ kind: 'files', ids: chosen })}>
              Move to…
            </button>
            <button className="link danger" onClick={removeSelected}>
              Delete
            </button>
            <button className="link" onClick={() => setSelected(new Set())}>
              Clear
            </button>
          </div>
        )}
        {canUpload && files.length > 0 && chosen.length < files.length && (
          <div>
            <button className="link" onClick={() => setSelected(new Set([...chosen, ...files.map((m) => m.id)]))}>
              Select all {files.length} file{files.length === 1 ? '' : 's'}
            </button>
          </div>
        )}

        {q && <p className="muted">Searching the whole {moduleName(module)} library.</p>}

        {empty ? (
          !data || q || here ? (
            <p className="muted">{!data ? 'Loading…' : q ? 'Nothing matches your search.' : 'This folder is empty.'}</p>
          ) : (
            <EmptyState help="media">
              No media yet. Upload your first video or image above. Each application has its own library, and you can sort files into folders.
            </EmptyState>
          )
        ) : view === 'grid' ? (
          <div className="media-grid">
            {subfolders.map((f) => (
              <div key={f.id} className={`media-tile folder-tile ${dropTarget === f.id ? 'drop-on' : ''}`} {...dropProps(f.id, f.id)}>
                <button className="folder-open" onClick={() => open(f.id)}>
                  <span className="folder-icon">📁</span>
                </button>
                <div className="media-info">
                  <b title={f.name}>{f.name}</b>
                  <span className="muted">
                    {itemCount(f)} item{itemCount(f) === 1 ? '' : 's'}
                    {f.site_id ? ` · ${scopeLabel(f.site_id, sites)} only` : ''}
                  </span>
                  {folderActions(f)}
                </div>
              </div>
            ))}
            {files.map((m) => (
              <div key={m.id} className={`media-tile ${selected.has(m.id) ? 'selected' : ''}`} {...dragProps(m)}>
                {canEdit(m.site_id) && (
                  <input
                    type="checkbox"
                    className="pick"
                    aria-label={`Select ${m.title}`}
                    checked={selected.has(m.id)}
                    onChange={() => toggle(m.id)}
                  />
                )}
                <Thumb m={m} />
                <div className="media-info">
                  <b title={m.title}>{m.title}</b>
                  <span className="muted">
                    {m.kind === 'video' ? 'Video' : 'Slide'} · {fmtBytes(m.size_bytes)} · {scopeLabel(m.site_id, sites)}
                  </span>
                  {q && m.folder_id && <span className="muted">in {folderPath(m.folder_id, byId)}</span>}
                  {usageLabel(m)}
                  {fileActions(m)}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="media-list">
            {subfolders.map((f) => (
              <div key={f.id} className={`media-row ${dropTarget === f.id ? 'drop-on' : ''}`} {...dropProps(f.id, f.id)}>
                <span className="pick-space" />
                <button className="folder-open small" onClick={() => open(f.id)} aria-label={`Open ${f.name}`}>
                  📁
                </button>
                <div className="media-row-main">
                  <button className="link row-title" onClick={() => open(f.id)}>
                    {f.name}
                  </button>
                  <span className="muted">
                    {itemCount(f)} item{itemCount(f) === 1 ? '' : 's'}
                    {f.site_id ? ` · ${scopeLabel(f.site_id, sites)} only` : ''}
                  </span>
                </div>
                {folderActions(f)}
              </div>
            ))}
            {files.map((m) => (
              <div key={m.id} className={`media-row ${selected.has(m.id) ? 'selected' : ''}`} {...dragProps(m)}>
                {canEdit(m.site_id) ? (
                  <input type="checkbox" aria-label={`Select ${m.title}`} checked={selected.has(m.id)} onChange={() => toggle(m.id)} />
                ) : (
                  <span className="pick-space" />
                )}
                <div className="row-thumb">
                  <Thumb m={m} />
                </div>
                <div className="media-row-main">
                  <b title={m.title}>{m.title}</b>
                  <span className="muted">
                    {m.kind === 'video' ? 'Video' : 'Slide'} · {fmtBytes(m.size_bytes)} · {scopeLabel(m.site_id, sites)}
                    {q && m.folder_id ? ` · in ${folderPath(m.folder_id, byId)}` : ''}
                  </span>
                  {usageLabel(m)}
                </div>
                {fileActions(m)}
              </div>
            ))}
          </div>
        )}
      </div>

      {picker?.kind === 'files' && (
        <FolderPicker
          title={`Move ${picker.ids.length} file${picker.ids.length === 1 ? '' : 's'} to…`}
          folders={folders}
          exclude={new Set()}
          currentId={picker.ids.length === 1 ? (media.find((m) => m.id === picker.ids[0])?.folder_id ?? null) : undefined}
          onPick={(id) => (moveFiles(picker.ids, id), setPicker(null))}
          onClose={() => setPicker(null)}
        />
      )}
      {picker?.kind === 'folder' && (
        <FolderPicker
          title={`Move "${picker.folder.name}" to…`}
          folders={folders}
          exclude={descendants(picker.folder.id)}
          currentId={picker.folder.parent_id}
          onPick={(id) => moveFolder(picker.folder, id)}
          onClose={() => setPicker(null)}
        />
      )}
    </div>
  )
}
