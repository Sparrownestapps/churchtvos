import { supabase } from '../supabase'
import { daysLabel, must, timeLabel } from '../lib'

export type ContentModule = 'kids' | 'signage' | 'slides'

/**
 * Where each playlist / deck is in use right now or later: id -> short descriptions such as
 * "Kids Room · Sundays 9:00-12:00 (weekly)" or "Lobby TV · default". Past one-off schedules don't count.
 */
export async function loadUsage(module: ContentModule, orgId: string): Promise<Map<string, string[]>> {
  const out = new Map<string, string[]>()
  const add = (id: string, what: string) => out.set(id, [...(out.get(id) ?? []), what])
  const nowIso = new Date().toISOString()
  const today = nowIso.slice(0, 10)
  const [locs, screens] = await Promise.all([
    supabase.from('locations').select('id,name').eq('organization_id', orgId),
    supabase.from('screens').select('id,name,signage_default_playlist_id').eq('organization_id', orgId),
  ])
  const room = (id: string) => (must(locs) as { id: string; name: string }[]).find((l) => l.id === id)?.name ?? 'a room'
  const S = must(screens) as { id: string; name: string | null; signage_default_playlist_id: string | null }[]
  const screen = (id: string | null) => S.find((x) => x.id === id)?.name ?? 'a screen group'
  const when = (iso: string) => new Date(iso).toLocaleString(undefined, { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })

  if (module === 'signage') {
    const slots = must(await supabase.from('signage_slots').select('playlist_id,screen_id,days,start_time,end_time,end_date').eq('organization_id', orgId)) as {
      playlist_id: string; screen_id: string | null; days: number[]; start_time: string; end_time: string; end_date: string | null
    }[]
    for (const s of slots) {
      if (s.end_date && s.end_date < today) continue
      add(s.playlist_id, `${screen(s.screen_id)} · ${daysLabel(s.days)} ${timeLabel(s.start_time, s.end_time) || 'all day'}`)
    }
    for (const sc of S) if (sc.signage_default_playlist_id) add(sc.signage_default_playlist_id, `${sc.name ?? 'Screen'} · default`)
    return out
  }

  const kids = module === 'kids'
  const [ones, series, overrides] = await Promise.all([
    supabase.from(kids ? 'schedules' : 'deck_schedules').select(`location_id,starts_at,ends_at,${kids ? 'playlist_id' : 'deck_id'}`).eq('organization_id', orgId).or(`ends_at.is.null,ends_at.gt.${nowIso}`),
    supabase.from(kids ? 'kids_series' : 'deck_series').select(`location_id,days,start_time,end_time,end_date,${kids ? 'playlist_ids' : 'deck_ids'}`).eq('organization_id', orgId),
    supabase.from('screen_overrides').select('screen_id,ref_id,kind,until').eq('organization_id', orgId).eq('kind', kids ? 'playlist' : 'deck').gt('until', nowIso),
  ])
  for (const o of must(ones) as Record<string, string>[]) add(o[kids ? 'playlist_id' : 'deck_id'], `${room(o.location_id)} · ${when(o.starts_at)}`)
  for (const s of must(series) as Record<string, any>[]) {
    if (s.end_date && s.end_date < today) continue
    for (const id of s[kids ? 'playlist_ids' : 'deck_ids'] as string[]) add(id, `${room(s.location_id)} · ${daysLabel(s.days)} ${timeLabel(s.start_time, s.end_time)} (weekly)`)
  }
  // Overrides are only readable by people who can control screens; others just don't see them here.
  if (!overrides.error) for (const o of overrides.data as { screen_id: string; ref_id: string }[]) add(o.ref_id, `${screen(o.screen_id)} · playing now`)
  return out
}
