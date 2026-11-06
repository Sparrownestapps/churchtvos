import { describe, expect, it } from 'vitest'
import { folderPath, pickerSections, type PickerInput } from './pickerGroups'

const items = [
  { id: 'cafe', name: 'Cafe - Signage', site_id: null, folder_id: 'lobby' },
  { id: 'maps', name: 'Cameron Hall - Maps', site_id: 's1', folder_id: 'maps' },
  { id: 'kt', name: 'Keith Test', site_id: null, folder_id: null },
  { id: 'youth', name: 'Youth', site_id: 's2', folder_id: null },
  { id: 'old', name: 'Old', site_id: null, folder_id: null, archived_at: '2026-01-01' },
]
const folders = [
  { id: 'lobby', parent_id: null, name: 'Lobby' },
  { id: 'maps', parent_id: 'lobby', name: 'Maps' },
]
const base: PickerInput = { items, folders, inUse: new Set(), recent: [], siteIds: [], includeOtherSites: false, query: '' }
const titles = (i: PickerInput) => pickerSections(i).sections.map((s) => `${s.title}: ${s.items.map((p) => p.id).join(',')}`)

describe('pickerSections', () => {
  it('builds folder paths', () => expect(folderPath('maps', folders)).toBe('Lobby / Maps'))
  it('orders on this TV, recent, folders, then loose items; hides archived', () => {
    expect(titles({ ...base, inUse: new Set(['maps']), recent: ['kt', 'maps'] })).toEqual([
      'On this TV: maps',
      'Recently used: kt',
      'Lobby: cafe',
      'Not in a folder: youth',
    ])
  })
  it('filters by site with a count of hidden ones, and by search including folder names', () => {
    const r = pickerSections({ ...base, siteIds: ['s1'] })
    expect(r.hiddenBySite).toBe(1)
    expect(r.sections.flatMap((s) => s.items.map((p) => p.id))).not.toContain('youth')
    expect(titles({ ...base, query: 'lobby' })).toEqual(['Lobby: cafe', 'Lobby / Maps: maps'])
  })
  it('keeps the current choice even when archived', () => {
    expect(titles({ ...base, selected: 'old' }).join('|')).toContain('old')
  })
})
