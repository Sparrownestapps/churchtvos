import { useMemo, useState, type ReactNode } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { ContentFolder } from '../types'
import { attempt, folderPath, must, scopeLabel, useLoad } from '../lib'
import { ScopeSelect, useDefaultScope } from '../ui'
import FolderPicker from './FolderPicker'
import { loadUsage, type ContentModule } from './usage'

/** What every organizable list row (Kids playlist, Signage playlist, Slides deck) has. */
export type ContentRow = { id: string; name: string; site_id: string | null; folder_id?: string | null; archived_at?: string | null; source?: string | null }

type Filter = 'all' | 'used' | 'unused' | 'assistant' | 'archived'
const FILTERS: { id: Filter; label: string }[] = [
  { id: 'all', label: 'All' },
  { id: 'used', label: 'In use' },
  { id: 'unused', label: 'Not used' },
  { id: 'assistant', label: 'Made by assistant' },
  { id: 'archived', label: 'Archived' },
]

function folderOk(res: { error: { message: string } | null }) {
  if (!res.error) return
  throw new Error(/content_folders_unique_name|duplicate key/.test(res.error.message) ? 'A folder with that name already exists here.' : res.error.message)
}

/** Extra bits the browser gives each row: where it is used, and the Move / Archive buttons. */
export type RowExtras = { meta: ReactNode; actions: ReactNode }

/**
 * Folders, search, filters ("in use", "not used", "made by assistant", "archived"), "used by", move and archive for one
 * list of playlists or decks. The page still draws each row (render) and owns create / edit / delete.
 * `folder` is lifted to the page so new items can be created in the folder being viewed.
 */
export default function ContentBrowser<T extends ContentRow>(props: {
  module: ContentModule
  table: 'playlists' | 'signage_playlists' | 'decks'
  noun: string // 'playlist' / 'deck'
  items: T[]
  folder: string | null
  onFolder: (id: string | null) => void
  onChanged: () => void
  render: (item: T, extras: RowExtras) => ReactNode
  /** Page buttons (New, Import…) shown in the toolbar. */
  toolbar?: ReactNode
  /** Sorts the rows shown (default: as given). */
  sort?: (a: T, b: T) => number
  empty: ReactNode
}) {
  const { module, table, noun, items, folder, onFolder, onChanged, render } = props
  const { org, sites, canEditContent } = useApp()
  const defaultScope = useDefaultScope()
  const allSites = sites.length > 1
  const [filter, setFilter] = useState<Filter>('all')
  const [search, setSearch] = useState('')
  const [newFolder, setNewFolder] = useState<{ name: string; site: string | null } | null>(null)
  const [picker, setPicker] = useState<{ kind: 'item'; item: T } | { kind: 'folder'; folder: ContentFolder } | null>(null)

  const { data, reload } = useLoad(async () => {
    const [folders, usage] = await Promise.all([
      supabase.from('content_folders').select('*').eq('organization_id', org.id).eq('module', module).order('name'),
      loadUsage(module, org.id),
    ])
    return { folders: must(folders) as ContentFolder[], usage }
  }, [org.id, module, items])
  const folders = useMemo(() => data?.folders ?? [], [data])
  const usage = data?.usage ?? new Map<string, string[]>()
  const byId = useMemo(() => new Map(folders.map((f) => [f.id, f])), [folders])
  const here = folder && byId.has(folder) ? folder : null
  const current = here ? byId.get(here) : undefined
  const crumbs: ContentFolder[] = []
  for (let f = current; f && crumbs.length < 100; f = f.parent_id ? byId.get(f.parent_id) : undefined) crumbs.unshift(f)
  const assistantIds = new Set(folders.filter((f) => f.system === 'assistant').map((f) => f.id))

  const q = search.trim().toLowerCase()
  // Searching or filtering looks across every folder; otherwise show what is in the folder being viewed.
  const flat = !!q || filter !== 'all'
  const matches = (x: T) => {
    if (q && !x.name.toLowerCase().includes(q)) return false
    if (filter === 'archived') return !!x.archived_at
    if (x.archived_at) return false
    if (filter === 'used') return usage.has(x.id)
    if (filter === 'unused') return !usage.has(x.id)
    if (filter === 'assistant') return x.source === 'mcp' || (!!x.folder_id && assistantIds.has(x.folder_id))
    return true
  }
  // In folder view: the items in this folder. At the top level that includes items whose folder this person can't see
  // (e.g. another site's folder), so nothing goes missing.
  const inFolder = (x: T) => !x.archived_at && (here === null ? !x.folder_id || !byId.has(x.folder_id) : x.folder_id === here)
  const shown = items.filter(flat ? matches : inFolder)
  if (props.sort) shown.sort(props.sort)
  const subfolders = flat ? [] : folders.filter((f) => f.parent_id === here).sort((a, b) => (a.system ? -1 : b.system ? 1 : a.name.localeCompare(b.name)))
  const count = (f: ContentFolder) => items.filter((x) => x.folder_id === f.id && !x.archived_at).length + folders.filter((x) => x.parent_id === f.id).length
  const canMakeFolder = canEditContent(module, current?.site_id ?? defaultScope)

  async function refresh() {
    reload()
    onChanged()
  }
  async function createFolder() {
    if (!newFolder?.name.trim()) return
    const site = current ? current.site_id : newFolder.site
    const ok = await attempt(async () =>
      folderOk(await supabase.from('content_folders').insert({ organization_id: org.id, module, parent_id: here, site_id: site, name: newFolder.name.trim() })),
    )
    if (ok) (setNewFolder(null), reload())
  }
  async function renameFolder(f: ContentFolder) {
    const name = prompt('Rename folder', f.name)?.trim()
    if (!name || name === f.name) return
    if (await attempt(async () => folderOk(await supabase.from('content_folders').update({ name }).eq('id', f.id).eq('organization_id', org.id)))) reload()
  }
  async function removeFolder(f: ContentFolder) {
    const parent = f.parent_id ? byId.get(f.parent_id)?.name : null
    if (!confirm(`Delete the folder "${f.name}"?\n\nNothing inside it is deleted: its ${noun}s and sub-folders move up to ${parent ? `"${parent}"` : 'the top level'}.`)) return
    if (await attempt(async () => must(await supabase.from('content_folders').delete().eq('id', f.id).eq('organization_id', org.id)))) {
      if (here === f.id) onFolder(f.parent_id)
      refresh()
    }
  }
  async function move(target: string | null) {
    if (!picker) return
    const ok = await attempt(async () =>
      picker.kind === 'item'
        ? must(await supabase.from(table).update({ folder_id: target }).eq('id', picker.item.id).eq('organization_id', org.id).select('id'))
        : folderOk(await supabase.from('content_folders').update({ parent_id: target }).eq('id', picker.folder.id).eq('organization_id', org.id)),
    )
    setPicker(null)
    if (ok) refresh()
  }
  async function archive(x: T, on: boolean) {
    if (on && usage.has(x.id)) {
      alert(`"${x.name}" is still in use:\n\n${usage.get(x.id)!.join('\n')}\n\nTake it out of those first, then archive it.`)
      return
    }
    if (await attempt(async () => must(await supabase.from(table).update({ archived_at: on ? new Date().toISOString() : null }).eq('id', x.id).eq('organization_id', org.id).select('id')))) refresh()
  }
  const descendants = (f: ContentFolder) => {
    const out = new Set([f.id])
    for (let grew = true; grew; ) {
      grew = false
      for (const x of folders) if (x.parent_id && out.has(x.parent_id) && !out.has(x.id)) (out.add(x.id), (grew = true))
    }
    return out
  }

  const extras = (x: T): RowExtras => {
    const used = usage.get(x.id)
    const canEdit = canEditContent(module, x.site_id)
    return {
      meta: (
        <>
          {flat && x.folder_id && byId.has(x.folder_id) && <span className="muted"> · in {folderPath(x.folder_id, byId)}</span>}
          {x.archived_at ? (
            <span className="muted"> · archived</span>
          ) : used ? (
            <span className="muted" title={used.join('\n')}>
              {' '}
              · used by {used.length === 1 ? used[0] : `${used[0]} and ${used.length - 1} more`}
            </span>
          ) : (
            data && <span className="muted"> · not used anywhere</span>
          )}
        </>
      ),
      actions: canEdit ? (
        <>
          {!x.archived_at && (
            <button className="btn" onClick={() => setPicker({ kind: 'item', item: x })}>
              Move to…
            </button>
          )}
          <button className="btn" onClick={() => archive(x, !x.archived_at)} title={x.archived_at ? 'Bring it back to the list' : 'Hide it from lists and menus without deleting it'}>
            {x.archived_at ? 'Restore' : 'Archive'}
          </button>
        </>
      ) : null,
    }
  }

  return (
    <div className="stack">
      <div className="row spread wrap-sm">
        <div className="row wrap-sm">{props.toolbar}</div>
        <div className="row wrap-sm">
          <input type="search" aria-label={`Search ${noun}s`} placeholder={`Search ${noun}s…`} value={search} onChange={(e) => setSearch(e.target.value)} />
          {!flat && canMakeFolder && (
            <button className="btn" onClick={() => setNewFolder(newFolder ? null : { name: '', site: defaultScope })}>
              + New folder
            </button>
          )}
        </div>
      </div>

      <div className="row spread wrap-sm">
        <nav className="crumbs" aria-label="Folder path">
          {flat ? (
            <span className="muted">Showing matches from every folder</span>
          ) : (
            <>
              <button className="crumb" disabled={!here} onClick={() => onFolder(null)}>
                All {noun}s
              </button>
              {crumbs.map((c, i) => (
                <span key={c.id} className="row">
                  <span className="muted">/</span>
                  <button className="crumb" disabled={i === crumbs.length - 1} onClick={() => onFolder(c.id)}>
                    {c.name}
                  </button>
                </span>
              ))}
            </>
          )}
        </nav>
        <span className="segmented" role="group" aria-label="Show">
          {FILTERS.map((f) => (
            <button key={f.id} className={filter === f.id ? 'on' : ''} onClick={() => setFilter(f.id)}>
              {f.label}
            </button>
          ))}
        </span>
      </div>

      {newFolder && (
        <div className="row wrap panel">
          <label className="field grow">
            <span>Folder name{current ? ` (inside ${current.name})` : ''}</span>
            <input
              autoFocus
              value={newFolder.name}
              onChange={(e) => setNewFolder({ ...newFolder, name: e.target.value })}
              onKeyDown={(e) => e.key === 'Enter' && createFolder()}
              placeholder={module === 'kids' ? 'e.g. Fall series' : module === 'signage' ? 'e.g. Events' : 'e.g. Sunday services'}
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

      {subfolders.map((f) => {
        const canEdit = canEditContent(module, f.site_id)
        return (
          <div key={f.id} className="card row spread">
            <button className="link" style={{ fontWeight: 700, fontSize: '1.05em' }} onClick={() => onFolder(f.id)}>
              📁 {f.name}
              <span className="muted" style={{ fontWeight: 400 }}>
                {' '}
                · {count(f)} {count(f) === 1 ? 'item' : 'items'}
                {f.site_id ? ` · ${scopeLabel(f.site_id, sites)} only` : ''}
                {f.system === 'assistant' ? ' · filled by your AI assistant' : ''}
              </span>
            </button>
            {canEdit && (
              <span className="row">
                <button className="link" onClick={() => renameFolder(f)}>
                  Rename
                </button>
                {!f.system && (
                  <button className="link" onClick={() => setPicker({ kind: 'folder', folder: f })}>
                    Move
                  </button>
                )}
                <button className="link danger" onClick={() => removeFolder(f)}>
                  Delete
                </button>
              </span>
            )}
          </div>
        )
      })}

      {shown.length === 0 && subfolders.length === 0 && (items.length === 0 ? props.empty : <p className="muted">{flat ? `No ${noun}s match.` : 'This folder is empty.'}</p>)}
      {shown.map((x) => render(x, extras(x)))}

      {picker && (
        <FolderPicker
          title={picker.kind === 'item' ? `Move "${picker.item.name}" to…` : `Move folder "${picker.folder.name}" to…`}
          folders={folders}
          exclude={picker.kind === 'folder' ? descendants(picker.folder) : new Set()}
          currentId={picker.kind === 'item' ? (picker.item.folder_id ?? null) : picker.folder.parent_id}
          rootLabel={`All ${noun}s`}
          onPick={move}
          onClose={() => setPicker(null)}
        />
      )}
    </div>
  )
}
