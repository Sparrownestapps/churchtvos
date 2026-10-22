import { describe, expect, it } from 'vitest'
import {
  NEW_SITE, buildLocationRow, buildSiteRow, claimFailedAfterCreate, cleanName, defaultTimeZone, friendlyCreateError, hasErrors, isValidTimeZone, validateNewRoom,
} from './pairRoom'

const sites = [{ id: 's1', name: 'Main Campus' }]
const locs = [{ site_id: 's1', name: 'Nursery' }]
const ok = { name: 'Lobby', siteChoice: 's1', siteName: '', timeZone: 'America/Toronto' }

describe('new room validation', () => {
  it('accepts a fresh room at an existing site', () => expect(hasErrors(validateNewRoom(ok, sites, locs))).toBe(false))
  it('requires a name', () => expect(validateNewRoom({ ...ok, name: '   ' }, sites, locs).name).toBeTruthy())
  it('rejects a duplicate name at the site, ignoring case and spacing', () =>
    expect(validateNewRoom({ ...ok, name: '  nursery ' }, sites, locs).name).toMatch(/already a room/))
  it('allows the same name at another site', () =>
    expect(hasErrors(validateNewRoom({ ...ok, name: 'Nursery', siteChoice: 's2' }, sites, locs))).toBe(false))
  it('needs a site', () => expect(validateNewRoom({ ...ok, siteChoice: '' }, sites, locs).site).toBeTruthy())
  it('validates a new site', () => {
    const base = { ...ok, siteChoice: NEW_SITE, siteName: 'North' }
    expect(hasErrors(validateNewRoom(base, sites, locs))).toBe(false)
    expect(validateNewRoom({ ...base, siteName: ' ' }, sites, locs).siteName).toBeTruthy()
    expect(validateNewRoom({ ...base, siteName: 'main campus' }, sites, locs).siteName).toMatch(/already exists/)
    expect(validateNewRoom({ ...base, timeZone: 'Mars/Base' }, sites, locs).timeZone).toBeTruthy()
  })
})

describe('payloads', () => {
  it('builds trimmed rows', () => {
    expect(buildSiteRow('o', '  North   Campus ', ' America/Toronto ')).toEqual({ organization_id: 'o', name: 'North Campus', timezone: 'America/Toronto' })
    expect(buildLocationRow('o', 's', ' Lobby ', ['kids', 'kids', 'signage'])).toEqual({ organization_id: 'o', site_id: 's', name: 'Lobby', modules: ['kids', 'signage'] })
  })
  it('cleans names', () => expect(cleanName('  a   b ')).toBe('a b'))
})

describe('time zones', () => {
  it('prefers the church, then browser, then Toronto', () => {
    expect(defaultTimeZone([{ timezone: 'America/Vancouver' }], 'Europe/London')).toBe('America/Vancouver')
    expect(defaultTimeZone([], 'Europe/London')).toBe('Europe/London')
    expect(defaultTimeZone([])).toBe('America/Toronto')
  })
  it('checks validity', () => {
    expect(isValidTimeZone('America/Toronto')).toBe(true)
    expect(isValidTimeZone('nope')).toBe(false)
    expect(isValidTimeZone('')).toBe(false)
    expect(isValidTimeZone('A/B', ['A/B'])).toBe(true)
  })
})

describe('messages', () => {
  it('maps duplicates and permissions', () => {
    expect(friendlyCreateError('room', { message: 'x', code: '23505' })).toMatch(/already exists/)
    expect(friendlyCreateError('site', { message: 'new row violates row-level security policy', code: '42501' })).toMatch(/owners and admins/)
  })
  it('explains a claim failure after create', () => expect(claimFailedAfterCreate('Main · Lobby', 'Plan full.')).toMatch(/was created/))
})
