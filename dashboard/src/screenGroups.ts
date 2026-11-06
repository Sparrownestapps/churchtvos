// Groups the Screens page by site, then area, then room, and applies its search and status filters.
import type { Location, Screen, Site } from './types'

export const isOnline = (s: Screen, now = Date.now()) => !!s.last_seen_at && now - new Date(s.last_seen_at).getTime() < 90_000

export type StatusFilter = 'all' | 'online' | 'offline' | 'old'
export type Filter = { text: string; site: string; status: StatusFilter }
export const NO_FILTER: Filter = { text: '', site: '', status: 'all' }

/** "1.7.0-vega" -> [1, 7, 0]; null when the TV hasn't reported a version. */
function versionParts(v: string | null): number[] | null {
  const m = v?.match(/^(\d+)\.(\d+)(?:\.(\d+))?/)
  return m ? [Number(m[1]), Number(m[2]), Number(m[3] ?? 0)] : null
}

function compare(a: number[], b: number[]) {
  for (let i = 0; i < 3; i++) if (a[i] !== b[i]) return a[i] - b[i]
  return 0
}

/** True when this TV runs an older app than the newest one any of the church's TVs has reported. */
export function isOlderApp(s: Screen, all: Screen[]): boolean {
  const mine = versionParts(s.app_version)
  if (!mine) return false
  let newest: number[] | null = null
  for (const o of all) {
    const v = versionParts(o.app_version)
    if (v && (!newest || compare(v, newest) > 0)) newest = v
  }
  return !!newest && compare(mine, newest) < 0
}

export type RoomGroup = { key: string; label: string; screens: Screen[] }
export type AreaGroup = { key: string; label: string; rooms: RoomGroup[]; count: number; offline: number }
export type SiteGroup = { key: string; label: string; areas: AreaGroup[]; count: number; offline: number }

const byName = (a: { label: string }, b: { label: string }) => a.label.localeCompare(b.label, undefined, { sensitivity: 'base' })
const screenLabel = (s: Screen) => s.name || `Screen ${s.id.slice(0, 6)}`

/**
 * Site -> area -> room -> TVs, keeping only TVs that match [filter]. Rooms with no area come first under their site.
 * TVs with no room (or a room that was deleted) go in a last "No location" group.
 */
export function groupScreens(screens: Screen[], sites: Site[], locations: Location[], filter: Filter, now = Date.now()): SiteGroup[] {
  const text = filter.text.trim().toLowerCase()
  const locById = new Map(locations.map((l) => [l.id, l]))
  const siteById = new Map(sites.map((s) => [s.id, s]))

  const matches = (s: Screen) => {
    const loc = s.location_id ? locById.get(s.location_id) : undefined
    if (filter.site && loc?.site_id !== filter.site) return false
    if (filter.status === 'online' && !isOnline(s, now)) return false
    if (filter.status === 'offline' && isOnline(s, now)) return false
    if (filter.status === 'old' && !isOlderApp(s, screens)) return false
    if (!text) return true
    const site = loc ? siteById.get(loc.site_id) : undefined
    return [screenLabel(s), loc?.name, loc?.area, site?.name, s.model].some((v) => v?.toLowerCase().includes(text))
  }

  const tree = new Map<string, { label: string; areas: Map<string, { label: string; rooms: Map<string, RoomGroup> }> }>()
  for (const s of screens) {
    if (!matches(s)) continue
    const loc = s.location_id ? locById.get(s.location_id) : undefined
    const site = loc ? siteById.get(loc.site_id) : undefined
    const siteKey = site ? `site:${site.id}` : 'site:none'
    const areaLabel = loc?.area?.trim() ?? ''
    const areaKey = `${siteKey}|area:${areaLabel.toLowerCase()}`
    const roomKey = loc ? `${areaKey}|room:${loc.id}` : `${areaKey}|room:none`

    let siteNode = tree.get(siteKey)
    if (!siteNode) tree.set(siteKey, (siteNode = { label: site?.name ?? 'No location', areas: new Map() }))
    let areaNode = siteNode.areas.get(areaKey)
    if (!areaNode) siteNode.areas.set(areaKey, (areaNode = { label: areaLabel, rooms: new Map() }))
    let room = areaNode.rooms.get(roomKey)
    if (!room) areaNode.rooms.set(roomKey, (room = { key: roomKey, label: loc?.name ?? 'Not assigned to a room', screens: [] }))
    room.screens.push(s)
  }

  const off = (list: Screen[]) => list.filter((s) => !isOnline(s, now)).length
  const result: SiteGroup[] = []
  for (const [key, node] of tree) {
    const areas: AreaGroup[] = []
    for (const [areaKey, a] of node.areas) {
      const rooms = [...a.rooms.values()].sort(byName)
      rooms.forEach((r) => r.screens.sort((x, y) => screenLabel(x).localeCompare(screenLabel(y), undefined, { numeric: true })))
      const all = rooms.flatMap((r) => r.screens)
      areas.push({ key: areaKey, label: a.label, rooms, count: all.length, offline: off(all) })
    }
    // Rooms without an area first, then areas A-Z.
    areas.sort((x, y) => (x.label === '' ? -1 : y.label === '' ? 1 : byName(x, y)))
    const count = areas.reduce((n, a) => n + a.count, 0)
    result.push({ key, label: node.label, areas, count, offline: areas.reduce((n, a) => n + a.offline, 0) })
  }
  // Sites in the church's order, "No location" last.
  const order = new Map(sites.map((s, i) => [`site:${s.id}`, i]))
  return result.sort((a, b) => (order.get(a.key) ?? 1e9) - (order.get(b.key) ?? 1e9))
}
