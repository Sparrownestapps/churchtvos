import { describe, expect, it } from 'vitest'
import { NO_FILTER, groupScreens, isOlderApp } from './screenGroups'
import type { Location, Screen, Site } from './types'

const now = Date.parse('2026-11-05T15:00:00Z')
const sites: Site[] = [
  { id: 's1', organization_id: 'o', name: 'Cambridge', timezone: 'America/Toronto' },
  { id: 's2', organization_id: 'o', name: 'Guelph', timezone: 'America/Toronto' },
]
const loc = (id: string, site: string, name: string, area: string | null): Location => ({ id, organization_id: 'o', site_id: site, name, modules: ['kids'], area })
const locations = [loc('l1', 's1', 'Theatre', null), loc('l2', 's1', 'Preschool', 'Kids Wing'), loc('l3', 's1', 'Nursery', 'Kids Wing'), loc('l4', 's2', 'Lobby', null)]
const tv = (id: string, location_id: string | null, name: string, online: boolean, app_version = '1.7.0'): Screen => ({
  id, organization_id: 'o', location_id, group_id: null, name, orientation: 'landscape', default_module: 'kids',
  signage_default_playlist_id: null, pairing_code: null, model: null, app_version,
  last_seen_at: new Date(online ? now - 10_000 : now - 3_600_000).toISOString(), created_at: '',
})
const screens = [tv('a', 'l2', 'Preschool 2', true), tv('b', 'l2', 'Preschool 1', false), tv('c', 'l1', 'Theatre', true, '1.6.0'), tv('d', 'l4', 'Lobby', true), tv('e', null, 'Spare', false)]

describe('groupScreens', () => {
  it('groups site, area, room with no-area rooms first and unassigned last', () => {
    const g = groupScreens(screens, sites, locations, NO_FILTER, now)
    expect(g.map((s) => s.label)).toEqual(['Cambridge', 'Guelph', 'No location'])
    expect(g[0].areas.map((a) => a.label)).toEqual(['', 'Kids Wing'])
    expect(g[0].areas[1].rooms[0].screens.map((s) => s.name)).toEqual(['Preschool 1', 'Preschool 2'])
    expect(g[0].count).toBe(3)
    expect(g[0].offline).toBe(1)
  })
  it('filters by text, status and site', () => {
    expect(groupScreens(screens, sites, locations, { ...NO_FILTER, text: 'kids wing' }, now)[0].count).toBe(2)
    expect(groupScreens(screens, sites, locations, { ...NO_FILTER, status: 'offline' }, now).flatMap((s) => s.areas.flatMap((a) => a.rooms.flatMap((r) => r.screens.map((x) => x.id))))).toEqual(['b', 'e'])
    expect(groupScreens(screens, sites, locations, { ...NO_FILTER, site: 's2' }, now).map((s) => s.label)).toEqual(['Guelph'])
  })
  it('flags TVs behind the newest version', () => {
    expect(isOlderApp(screens[2], screens)).toBe(true)
    expect(isOlderApp(screens[0], [...screens, tv('v', 'l1', 'Vega', true, '1.7.0-vega')])).toBe(false)
  })
})
