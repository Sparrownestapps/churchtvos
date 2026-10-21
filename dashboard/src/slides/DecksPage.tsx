import { useMemo, useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Deck } from '../slidesTypes'
import { attempt, must, scopeLabel, timeAgo, useLoad } from '../lib'
import { ReadOnlyNote, useDefaultScope } from '../ui'
import DeckEditor from './DeckEditor'
import ImportDialog from '../importer/ImportDialog'
import { MiniSlide } from './DeckPreview'
import { useSlidesLibrary, useSongs, useThemes } from './data'

type Sort = 'updated' | 'name' | 'name-desc' | 'slides'

export default function DecksPage() {
  const { org, sites, canEditContent } = useApp()
  const defaultScope = useDefaultScope()
  const [editing, setEditing] = useState<Deck | 'new' | null>(null)
  const [search, setSearch] = useState('')
  const [sort, setSort] = useState<Sort>('updated')
  const [importing, setImporting] = useState(false)

  const { data, error, reload } = useLoad(async () => must(await supabase.from('decks').select('*').eq('organization_id', org.id).order('updated_at', { ascending: false })) as Deck[], [org.id])
  const themes = useThemes()
  const songs = useSongs()
  const lib = useSlidesLibrary()
  const songMap = useMemo(() => new Map((songs.data ?? []).map((s) => [s.id, s])), [songs.data])

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase()
    const list = (data ?? []).filter((d) => !q || d.name.toLowerCase().includes(q))
    const byName = (a: Deck, b: Deck) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true })
    if (sort === 'name') return list.sort(byName)
    if (sort === 'name-desc') return list.sort((a, b) => byName(b, a))
    if (sort === 'slides') return list.sort((a, b) => b.slides.length - a.slides.length)
    return list.sort((a, b) => b.updated_at.localeCompare(a.updated_at))
  }, [data, search, sort])

  if (editing) {
    if (!themes.data) return <p className={themes.error ? 'error' : 'muted'}>{themes.error ? `Couldn't load themes: ${themes.error}` : 'Loading…'}</p>
    return (
      <DeckEditor
        deck={editing === 'new' ? null : editing}
        lib={lib}
        themes={themes.data}
        songs={songs.data ?? []}
        onDone={() => (setEditing(null), reload())}
      />
    )
  }

  async function duplicate(d: Deck) {
    const ok = await attempt(async () =>
      must(await supabase.from('decks').insert({ organization_id: org.id, site_id: d.site_id, name: `${d.name} (copy)`, theme_id: d.theme_id, background: d.background, slides: d.slides, loops: d.loops })),
    )
    if (ok) reload()
  }

  async function rename(d: Deck) {
    const name = prompt('Rename deck', d.name)?.trim()
    if (!name || name === d.name) return
    if (await attempt(async () => must(await supabase.from('decks').update({ name }).eq('id', d.id).eq('organization_id', org.id)))) reload()
  }

  async function remove(d: Deck) {
    if (!confirm(`Delete "${d.name}"? It will also be removed from any dated schedules. A deck used in a repeating schedule can't be deleted until you take it out there.`)) return
    // The server refuses (and says why) if a repeating schedule uses the deck.
    const gone = await attempt(async () => {
      const rows = must(await supabase.from('decks').delete().eq('id', d.id).eq('organization_id', org.id).select('id'))
      if (!rows?.length) throw new Error(`Couldn't delete "${d.name}". You may not have permission.`)
    })
    if (gone) reload()
  }

  const decks = data ?? []
  const canCreate = canEditContent('slides', defaultScope)
  const themeName = (id: string | null) => (id ? themes.data?.find((t) => t.id === id)?.name : undefined)

  return (
    <div className="stack">
      {error && <p className="error">Couldn't load decks: {error}</p>}
      {!canCreate && !sites.some((s) => canEditContent('slides', s.id)) && <ReadOnlyNote />}
      <div className="sl-toolbar">
        {canCreate && (
          <button className="btn primary" onClick={() => setEditing('new')} disabled={!themes.data}>
            + New deck
          </button>
        )}
        {canCreate && (
          <button className="btn" onClick={() => setImporting(true)} title="Make a deck from a PDF, a PowerPoint or pictures">
            Import PDF / PowerPoint…
          </button>
        )}
        <input type="search" className="sl-search" aria-label="Search decks" placeholder="Search decks" value={search} onChange={(e) => setSearch(e.target.value)} />
        <label className="sl-sort">
          <span className="muted">Sort</span>
          <select value={sort} onChange={(e) => setSort(e.target.value as Sort)}>
            <option value="updated">Recently edited</option>
            <option value="name">Name A to Z</option>
            <option value="name-desc">Name Z to A</option>
            <option value="slides">Most slides</option>
          </select>
        </label>
      </div>

      {data && decks.length === 0 && (
        <p className="muted empty-state">A deck is a presentation: slides with words, pictures, songs, a countdown or a live stream, shown on a TV. Press New deck to build one, and use Themes to set the look.</p>
      )}
      {data && decks.length > 0 && shown.length === 0 && <p className="muted">No decks match that search.</p>}

      {shown.map((d) => {
        const canEdit = canEditContent('slides', d.site_id)
        const theme = d.theme_id ? themes.data?.find((t) => t.id === d.theme_id) : undefined
        return (
          <div key={d.id} className="card row spread sl-deckrow">
            <div className="row sl-deckmain">
              <button className="sl-deckthumb" onClick={() => setEditing(d)} aria-label={`${canEdit ? 'Edit' : 'View'} ${d.name}`}>
                {d.slides[0] ? <MiniSlide slide={d.slides[0]} deckBackground={d.background} theme={theme?.config} songs={songMap} /> : <span className="sl-none">Empty</span>}
              </button>
              <div>
                <h3>{d.name}</h3>
                <span className="muted">
                  {d.slides.length} {d.slides.length === 1 ? 'slide' : 'slides'} · {scopeLabel(d.site_id, sites)} · {themeName(d.theme_id) ?? 'No theme'}
                  {d.loops ? ' · loops' : ''} · edited {timeAgo(d.updated_at)}
                </span>
              </div>
            </div>
            <div className="row wrap-sm">
              <button className="btn" onClick={() => setEditing(d)}>
                {canEdit ? 'Edit' : 'View'}
              </button>
              {canEdit && (
                <>
                  <button className="btn" onClick={() => rename(d)}>
                    Rename
                  </button>
                  <button className="btn" onClick={() => duplicate(d)}>
                    Duplicate
                  </button>
                  <button className="btn danger" onClick={() => remove(d)}>
                    Delete
                  </button>
                </>
              )}
            </div>
          </div>
        )
      })}
      {importing && <ImportDialog mode="deck" onClose={() => setImporting(false)} onCreated={reload} />}
    </div>
  )
}
