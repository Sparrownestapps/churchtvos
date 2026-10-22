import { useMemo, useState } from 'react'
import { useApp } from './context'
import { supabase } from './supabase'
import { locationLabel } from './lib'
import { LocationOptions } from './ui'
import type { Module, Site } from './types'
import {
  NEW_ROOM, NEW_SITE, browserTimeZone, buildLocationRow, buildSiteRow, cleanName, defaultRoomModules, defaultTimeZone, friendlyCreateError, hasErrors,
  validateNewRoom, type NewRoomErrors,
} from './pairRoom'

const zones: string[] = typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : []

export type ResolvedRoom = { ok: true; locationId: string; label: string; created: boolean } | { ok: false; error: string }

/** State for the "Location" choice used when pairing a TV; can create the site and room first. */
export function usePairTarget() {
  const { org, sites, mySites, locations, modules, moduleOn, reloadOrg } = useApp()
  const [locationId, setLocationId] = useState(() => (locations.length === 1 ? locations[0].id : locations.length === 0 ? NEW_ROOM : ''))
  const [roomName, setRoomName] = useState('')
  const [siteChoice, setSiteChoice] = useState(() => (mySites.length === 1 ? mySites[0].id : mySites.length === 0 ? NEW_SITE : ''))
  const [siteName, setSiteName] = useState('')
  const [timeZone, setTimeZone] = useState(() => defaultTimeZone(sites, browserTimeZone()))
  const offered = useMemo<Module[]>(() => {
    const on = modules.filter((m) => m.available !== false && moduleOn(m.id)).map((m) => m.id)
    return on.length > 0 ? on : modules.filter((m) => m.available !== false).map((m) => m.id)
  }, [modules, moduleOn])
  const [tags, setTags] = useState<Module[]>(() => defaultRoomModules(offered.filter((id) => moduleOn(id))))
  const [errors, setErrors] = useState<NewRoomErrors>({})
  // Rows we created that the reloaded org context may not show yet; kept so a retry never duplicates them.
  const [madeSite, setMadeSite] = useState<Site | null>(null)
  const [madeRoom, setMadeRoom] = useState<{ id: string; label: string } | null>(null)

  const isNew = locationId === NEW_ROOM
  const siteList = madeSite && !mySites.some((s) => s.id === madeSite.id) ? [...mySites, madeSite] : mySites

  async function resolve(): Promise<ResolvedRoom> {
    if (!isNew) {
      const loc = locations.find((l) => l.id === locationId)
      return { ok: true, locationId, label: loc ? locationLabel(loc, sites) : madeRoom?.label ?? 'the room', created: false }
    }
    const found = validateNewRoom({ name: roomName, siteChoice, siteName, timeZone }, sites, locations, zones)
    setErrors(found)
    if (hasErrors(found)) return { ok: false, error: 'Check the highlighted fields.' }

    let siteId = siteChoice
    let site = siteList.find((s) => s.id === siteId)
    if (siteChoice === NEW_SITE) {
      const { data, error } = await supabase.from('sites').insert(buildSiteRow(org.id, siteName, timeZone)).select('id, organization_id, name, timezone').single()
      if (error) return { ok: false, error: friendlyCreateError('site', error) }
      site = data as Site
      siteId = site.id
      setMadeSite(site)
      setSiteChoice(site.id)
    }
    const { data, error } = await supabase.from('locations').insert(buildLocationRow(org.id, siteId, roomName, tags)).select('id').single()
    if (error) {
      reloadOrg()
      return { ok: false, error: friendlyCreateError('room', error) }
    }
    const label = `${site?.name ?? ''}${site ? ' · ' : ''}${cleanName(roomName)}`
    setMadeRoom({ id: data.id as string, label })
    setLocationId(data.id as string) // a retry now just pairs; it won't create the room again
    reloadOrg()
    return { ok: true, locationId: data.id as string, label, created: true }
  }

  return {
    locationId, setLocationId, roomName, setRoomName, siteChoice, setSiteChoice, siteName, setSiteName, timeZone, setTimeZone,
    tags, setTags, offered, errors, isNew, siteList, madeRoom, resolve,
  }
}
export type PairTarget = ReturnType<typeof usePairTarget>

/** The Location select, plus the new room / new site fields when "+ New room…" is chosen. */
export function PairLocationField({ target: t }: { target: PairTarget }) {
  const { locations, moduleName } = useApp()
  const hasMade = t.madeRoom && !locations.some((l) => l.id === t.madeRoom!.id)
  const siteIsNew = t.siteChoice === NEW_SITE
  return (
    <>
      <label className="field grow">
        <span>Location</span>
        <select value={t.locationId} onChange={(e) => t.setLocationId(e.target.value)} required>
          <option value="">Choose…</option>
          <LocationOptions />
          {hasMade && <option value={t.madeRoom!.id}>{t.madeRoom!.label}</option>}
          <option value={NEW_ROOM}>+ New room…</option>
        </select>
      </label>
      {t.isNew && (
        <div className="stack-sm panel" style={{ flexBasis: '100%' }}>
          <label className="field">
            <span>Room name</span>
            <input value={t.roomName} onChange={(e) => t.setRoomName(e.target.value)} placeholder="e.g. Nursery or Lobby" maxLength={80} autoComplete="off" aria-invalid={!!t.errors.name} />
            {t.errors.name && <span className="error" style={{ textTransform: 'none', letterSpacing: 0 }}>{t.errors.name}</span>}
          </label>
          <label className="field">
            <span>Site</span>
            <select value={t.siteChoice} onChange={(e) => t.setSiteChoice(e.target.value)} aria-invalid={!!t.errors.site}>
              <option value="">Choose…</option>
              {t.siteList.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
              <option value={NEW_SITE}>+ New site…</option>
            </select>
            {t.errors.site && <span className="error" style={{ textTransform: 'none', letterSpacing: 0 }}>{t.errors.site}</span>}
          </label>
          {siteIsNew && (
            <div className="row wrap">
              <label className="field grow">
                <span>Site name</span>
                <input value={t.siteName} onChange={(e) => t.setSiteName(e.target.value)} placeholder="e.g. North Campus" maxLength={80} autoComplete="off" aria-invalid={!!t.errors.siteName} />
                {t.errors.siteName && <span className="error" style={{ textTransform: 'none', letterSpacing: 0 }}>{t.errors.siteName}</span>}
              </label>
              <label className="field grow">
                <span>Time zone</span>
                <input list="pair-zones" value={t.timeZone} onChange={(e) => t.setTimeZone(e.target.value)} aria-invalid={!!t.errors.timeZone} />
                <datalist id="pair-zones">
                  {zones.map((z) => (
                    <option key={z} value={z} />
                  ))}
                </datalist>
                {t.errors.timeZone && <span className="error" style={{ textTransform: 'none', letterSpacing: 0 }}>{t.errors.timeZone}</span>}
              </label>
            </div>
          )}
          <div className="field">
            <span>Used by</span>
            <span className="days">
              {t.offered.map((id) => {
                const on = t.tags.includes(id)
                return (
                  <button type="button" key={id} className={`day ${on ? 'on' : ''}`} aria-pressed={on} onClick={() => t.setTags(on ? t.tags.filter((x) => x !== id) : [...t.tags, id])}>
                    {moduleName(id)}
                  </button>
                )
              })}
            </span>
          </div>
        </div>
      )}
    </>
  )
}
