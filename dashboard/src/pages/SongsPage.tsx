import { lazy, Suspense, useMemo, useState } from 'react'
import '../songs.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Song } from '../types'
import { attempt, fetchAll, must, useLoad } from '../lib'
import { EmptyState } from '../ui'
import { helpUrl } from '../links'

const SongEditor = lazy(() => import('./SongEditor'))
const SongImport = lazy(() => import('./SongImport'))

type Sort = 'title' | 'title-desc' | 'updated'

/** The church's shared song library (used by Kids lyrics items now, and the Slides module later). */
export default function SongsPage() {
  const { org, canEditRole, hasModule } = useApp()
  const canEdit = canEditRole && (hasModule('kids') || hasModule('slides'))
  const [editing, setEditing] = useState<Song | 'new' | null>(null)
  const [importing, setImporting] = useState<'paste' | 'files' | null>(null)
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<Sort>('title')

  const { data, error, reload } = useLoad(async () => {
    const songs = await fetchAll<Song>((a, b) => supabase.from('songs').select('*').eq('organization_id', org.id).order('title').range(a, b))
    // Usage is a nicety: if it can't be read the list still works.
    const usage = new Map<string, string[]>()
    const res = await supabase.rpc('song_usage', { p_org: org.id })
    if (!res.error) for (const r of (res.data ?? []) as { song_id: string; playlist_names: string[] }[]) usage.set(r.song_id, r.playlist_names)
    return { songs, usage }
  }, [org.id])

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    const list = (data?.songs ?? []).filter(
      (s) => !q || [s.title, s.authors, s.ccli_number].some((v) => (v ?? '').toLowerCase().includes(q)),
    )
    const byTitle = (a: Song, b: Song) => a.title.localeCompare(b.title, undefined, { sensitivity: 'base', numeric: true })
    return list.sort(sort === 'title' ? byTitle : sort === 'title-desc' ? (a, b) => byTitle(b, a) : (a, b) => b.updated_at.localeCompare(a.updated_at))
  }, [data, search, sort])

  if (editing) {
    return (
      <Suspense fallback={<p className="muted">Loading…</p>}>
        <SongEditor song={editing === 'new' ? null : editing} onDone={() => (setEditing(null), reload())} />
      </Suspense>
    )
  }

  async function duplicate(s: Song) {
    const ok = await attempt(async () =>
      must(
        await supabase.from('songs').insert({
          organization_id: org.id,
          title: `${s.title} (copy)`,
          authors: s.authors,
          ccli_number: s.ccli_number,
          copyright: s.copyright,
          sections: s.sections,
          arrangement: s.arrangement,
          lines_per_slide: s.lines_per_slide,
          source: s.source,
        }),
      ),
    )
    if (ok) reload()
  }

  async function remove(s: Song) {
    if (!confirm(`Delete "${s.title}"?`)) return
    // If a playlist still uses the song, the server refuses and says which ones; attempt() shows that message.
    if (await attempt(async () => must(await supabase.from('songs').delete().eq('id', s.id)))) reload()
  }

  const songs = data?.songs ?? []

  return (
    <div className="stack">
      {canEdit && (
        <div className="row wrap-sm">
          <button className="btn primary" onClick={() => setEditing('new')}>
            + New song
          </button>
          <button className="btn" onClick={() => setImporting('paste')}>
            Paste lyrics
          </button>
          <button className="btn" onClick={() => setImporting('files')}>
            Import files
          </button>
        </div>
      )}
      {error && <p className="error">Couldn't load the songs: {error}</p>}
      {songs.length > 0 && (
        <div className="toolbar">
          <input className="search" type="search" placeholder="Search title, author or CCLI number" value={search} onChange={(e) => setSearch(e.target.value)} />
          <select value={sort} onChange={(e) => setSort(e.target.value as Sort)} aria-label="Sort">
            <option value="title">Title A to Z</option>
            <option value="title-desc">Title Z to A</option>
            <option value="updated">Recently changed</option>
          </select>
          <span className="muted">{shown.length === songs.length ? `${songs.length} songs` : `${shown.length} of ${songs.length}`}</span>
        </div>
      )}
      {data && songs.length === 0 && (
        <EmptyState help="songs">
          Your song library is shared by every Kids playlist (and, later, Slides). Add a song by typing it, pasting lyrics, or importing lyric files you have downloaded, then pick it in a playlist's lyrics item.
        </EmptyState>
      )}
      {songs.length > 0 && shown.length === 0 && <p className="muted">No songs match "{search}".</p>}
      {shown.map((s) => {
        const used = data?.usage.get(s.id) ?? []
        return (
          <div key={s.id} className="card row spread song-row">
            <div>
              <h3>{s.title}</h3>
              <div className="muted song-meta">
                {s.authors && <span>{s.authors}</span>}
                {s.ccli_number && <span>CCLI {s.ccli_number}</span>}
                <span>
                  {s.sections.length} {s.sections.length === 1 ? 'section' : 'sections'}
                </span>
                <span title={used.join(', ')}>{used.length === 0 ? 'Not used yet' : `Used in ${used.length} ${used.length === 1 ? 'playlist' : 'playlists'}`}</span>
              </div>
            </div>
            {canEdit && (
              <div className="row">
                <button className="btn" onClick={() => setEditing(s)}>
                  Edit
                </button>
                <button className="btn" onClick={() => duplicate(s)}>
                  Duplicate
                </button>
                <button className="btn danger" onClick={() => remove(s)}>
                  Delete
                </button>
              </div>
            )}
          </div>
        )
      })}
      {songs.length > 0 && (
        <p className="muted">
          Only add lyrics your church is licensed to display (for example with a CCLI licence). <a href={helpUrl('songs')} target="_blank" rel="noreferrer">Songs help</a>
        </p>
      )}
      {importing && (
        <Suspense fallback={null}>
          <SongImport
            library={songs}
            initialTab={importing}
            onClose={() => setImporting(null)}
            onSaved={() => (setImporting(null), reload())}
          />
        </Suspense>
      )}
    </div>
  )
}
