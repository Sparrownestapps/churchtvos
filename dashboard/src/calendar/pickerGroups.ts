// Sorting and grouping for the calendar's playlist / deck picker: what's on this TV, recently used, then by folder.
import type { NamedRow } from '../calendarTypes'

export type PickerItem = NamedRow & { folder_id?: string | null }
export type PickerFolder = { id: string; parent_id: string | null; name: string; site_id?: string | null }
export type PickerSection = { title: string; items: PickerItem[] }

export type PickerInput = {
  items: PickerItem[]
  folders: PickerFolder[]
  /** Ids already scheduled on the screen / group / room the calendar is showing. */
  inUse: Set<string>
  /** Most recent first. */
  recent: string[]
  /** Sites of what the calendar is showing; empty = don't filter by site. */
  siteIds: string[]
  includeOtherSites: boolean
  query: string
  /** The current choice: always listed, even when archived or filtered out. */
  selected?: string
}

const byName = (a: PickerItem, b: PickerItem) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base', numeric: true })

/** "Lobby / Maps" for a folder inside a folder. */
export function folderPath(id: string, folders: PickerFolder[]): string {
  const byId = new Map(folders.map((f) => [f.id, f]))
  const parts: string[] = []
  let f = byId.get(id)
  for (let guard = 0; f && guard < 10; guard++) {
    parts.unshift(f.name)
    f = f.parent_id ? byId.get(f.parent_id) : undefined
  }
  return parts.join(' / ')
}

export function pickerSections(input: PickerInput): { sections: PickerSection[]; hiddenBySite: number } {
  const { items, folders, inUse, recent, siteIds, includeOtherSites, selected } = input
  const q = input.query.trim().toLowerCase()
  const paths = new Map(folders.map((f) => [f.id, folderPath(f.id, folders)]))
  const pathOf = (p: PickerItem) => (p.folder_id ? paths.get(p.folder_id) ?? '' : '')

  const live = items.filter((p) => !p.archived_at || p.id === selected)
  const siteOk = (p: PickerItem) => siteIds.length === 0 || !p.site_id || siteIds.includes(p.site_id) || p.id === selected
  const hiddenBySite = includeOtherSites ? 0 : live.filter((p) => !siteOk(p)).length
  const visible = live.filter((p) => (includeOtherSites || siteOk(p)) && (!q || p.name.toLowerCase().includes(q) || pathOf(p).toLowerCase().includes(q)))

  const used = new Set<string>()
  const take = (list: PickerItem[]) => list.filter((p) => !used.has(p.id) && used.add(p.id))
  const sections: PickerSection[] = []
  const push = (title: string, list: PickerItem[]) => list.length && sections.push({ title, items: list })

  push('On this TV', take(visible.filter((p) => inUse.has(p.id)).sort(byName)))
  const recentRank = new Map(recent.map((id, i) => [id, i]))
  push('Recently used', take(visible.filter((p) => recentRank.has(p.id)).sort((a, b) => recentRank.get(a.id)! - recentRank.get(b.id)!)))

  const rest = visible.filter((p) => !used.has(p.id))
  const byFolder = new Map<string, PickerItem[]>()
  for (const p of rest) {
    const key = pathOf(p)
    byFolder.set(key, [...(byFolder.get(key) ?? []), p])
  }
  const names = [...byFolder.keys()].filter((k) => k !== '').sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }))
  for (const name of names) push(name, byFolder.get(name)!.sort(byName))
  // Playlists not in a folder: "All" when nothing else is grouped, otherwise "Not in a folder".
  push(sections.length === 0 ? 'All' : 'Not in a folder', (byFolder.get('') ?? []).sort(byName))
  return { sections, hiddenBySite }
}

// ───── recently used (per browser, per church and kind) ─────

const recentKey = (orgId: string, kind: string) => `ctvos:recent-picks:${orgId}:${kind}`

export function readRecent(orgId: string, kind: string): string[] {
  try {
    const v = JSON.parse(localStorage.getItem(recentKey(orgId, kind)) ?? '[]')
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []
  } catch {
    return []
  }
}

export function rememberRecent(orgId: string, kind: string, id: string) {
  try {
    const next = [id, ...readRecent(orgId, kind).filter((x) => x !== id)].slice(0, 5)
    localStorage.setItem(recentKey(orgId, kind), JSON.stringify(next))
  } catch {
    /* storage blocked: no recent list */
  }
}
