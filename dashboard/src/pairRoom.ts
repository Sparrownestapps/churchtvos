/** Create-a-room-while-pairing: validation and payload builders (contract: ROOM-CREATE-CONTRACT.md). */
import type { Location, Module, Site } from './types'

export const NEW_ROOM = '__new_room__'
export const NEW_SITE = '__new_site__'
export const FALLBACK_TIME_ZONE = 'America/Toronto'

/** Trim and collapse inner whitespace. */
export const cleanName = (s: string) => s.trim().replace(/\s+/g, ' ')
const same = (a: string, b: string) => cleanName(a).toLowerCase() === cleanName(b).toLowerCase()

/** The church's time zone (its first site's), else the browser's, else Toronto. */
export function defaultTimeZone(sites: Pick<Site, 'timezone'>[], browserZone?: string): string {
  const fromSite = sites.find((s) => s.timezone?.trim())?.timezone.trim()
  return fromSite || browserZone || FALLBACK_TIME_ZONE
}

export function browserTimeZone(): string | undefined {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || undefined
  } catch {
    return undefined
  }
}

export function isValidTimeZone(tz: string, known?: string[]): boolean {
  const z = tz.trim()
  if (!z) return false
  if (known && known.length > 0) return known.includes(z)
  try {
    new Intl.DateTimeFormat('en', { timeZone: z })
    return true
  } catch {
    return false
  }
}

/** Module tags a new room starts with: the modules the church has switched on. */
export function defaultRoomModules(offered: Module[]): Module[] {
  return [...offered]
}

export type NewRoomInput = {
  name: string
  /** An existing site id, or NEW_SITE. */
  siteChoice: string
  siteName: string
  timeZone: string
}
export type NewRoomErrors = { name?: string; site?: string; siteName?: string; timeZone?: string }

export function validateNewRoom(
  input: NewRoomInput,
  sites: Pick<Site, 'id' | 'name'>[],
  locations: Pick<Location, 'site_id' | 'name'>[],
  knownZones?: string[],
): NewRoomErrors {
  const errors: NewRoomErrors = {}
  const name = cleanName(input.name)
  if (!name) errors.name = 'Enter a name for the room.'
  if (!input.siteChoice) errors.site = 'Choose a site, or add a new one.'
  else if (input.siteChoice === NEW_SITE) {
    const siteName = cleanName(input.siteName)
    if (!siteName) errors.siteName = 'Enter a name for the new site.'
    else if (sites.some((s) => same(s.name, siteName))) errors.siteName = `A site called "${siteName}" already exists. Choose it from the list instead.`
    if (!isValidTimeZone(input.timeZone, knownZones)) errors.timeZone = 'Choose a valid time zone, like America/Toronto.'
  } else if (name && locations.some((l) => l.site_id === input.siteChoice && same(l.name, name))) {
    errors.name = `There is already a room called "${name}" at that site. Choose it from the Location list, or use another name.`
  }
  return errors
}
export const hasErrors = (e: NewRoomErrors) => Object.keys(e).length > 0

export const buildSiteRow = (organizationId: string, name: string, timezone: string) => ({
  organization_id: organizationId,
  name: cleanName(name),
  timezone: timezone.trim(),
})

export const buildLocationRow = (organizationId: string, siteId: string, name: string, modules: Module[]) => ({
  organization_id: organizationId,
  site_id: siteId,
  name: cleanName(name),
  modules: [...new Set(modules)],
})

/** Plain-language message for a failed site/location insert. */
export function friendlyCreateError(kind: 'site' | 'room', error: { message: string; code?: string }): string {
  if (error.code === '23505' || /duplicate key|unique/i.test(error.message))
    return kind === 'site' ? 'A site with that name already exists. Choose it from the list.' : 'A room with that name already exists at this site.'
  if (error.code === '42501' || /row-level security|permission/i.test(error.message))
    return `Only owners and admins can add ${kind === 'site' ? 'sites' : 'rooms'}.`
  return error.message
}

/** Shown when the room was created but the TV could not be paired. */
export const claimFailedAfterCreate = (roomLabel: string, reason: string) =>
  `${roomLabel} was created, but the TV was not paired: ${reason} The room is selected, so press Pair TV again once that is fixed.`
