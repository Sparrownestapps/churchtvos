import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Screen, ScreenGroup, SignagePlaylist, SignageSlot } from '../types'
import { daysLabel, must, timeLabel, useLoad } from '../lib'
import ScheduleRules from '../ScheduleRules'
import { EmptyState, ReadOnlyNote } from '../ui'

export default function SignageSlotsPage() {
  const { org, canEditContent } = useApp()
  const [target, setTarget] = useState('')

  const { data, reload } = useLoad(async () => {
    const [screens, groups, playlists, slots] = await Promise.all([
      supabase.from('screens').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('screen_groups').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('signage_playlists').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('signage_slots').select('*').eq('organization_id', org.id),
    ])
    return {
      screens: must(screens) as Screen[],
      groups: must(groups) as ScreenGroup[],
      playlists: must(playlists) as SignagePlaylist[],
      slots: must(slots) as SignageSlot[],
    }
  })

  if (!data) return null
  // Slots are organization-wide in the database, so editing needs all-sites editor access.
  const canEdit = canEditContent('signage', null)
  const [kind, id] = target.split(':')
  const rulesFor = (k: string, i: string) => data.slots.filter((s) => (k === 'screen' ? s.screen_id === i : s.group_id === i))
  const screenName = (s: Screen) => s.name || `Screen ${s.id.slice(0, 6)}`
  const playlistName = (pid: string) => data.playlists.find((p) => p.id === pid)?.name ?? '—'

  return (
    <div className="stack">
      {!canEdit && <ReadOnlyNote />}
      <div className="card stack-sm">
        <label className="field">
          <span>Show slots for</span>
          <select value={target} onChange={(e) => setTarget(e.target.value)}>
            <option value="">Choose a screen or group…</option>
            <optgroup label="Screen groups">
              {data.groups.map((g) => (
                <option key={g.id} value={`group:${g.id}`}>
                  {g.name} ({rulesFor('group', g.id).length} slots)
                </option>
              ))}
            </optgroup>
            <optgroup label="Screens">
              {data.screens.map((s) => (
                <option key={s.id} value={`screen:${s.id}`}>
                  {screenName(s)} ({rulesFor('screen', s.id).length} slots)
                </option>
              ))}
            </optgroup>
          </select>
        </label>
        {target ? (
          <ScheduleRules
            kind="slot"
            rules={rulesFor(kind, id)}
            target={kind === 'screen' ? { screen_id: id } : { group_id: id }}
            playlists={data.playlists}
            canEdit={canEdit}
            onChanged={reload}
          />
        ) : (
          <p className="muted">
            A slot says which Signage playlist plays on a screen (or a whole group) on certain days and times. When no
            slot is active, the screen plays its default playlist, or shows a black screen if it has none. A screen
            only shows Signage when its module schedule (Screens page) says so.
          </p>
        )}
      </div>

      <div className="card">
        <h3>All slots</h3>
        {data.slots.length === 0 ? (
          <EmptyState help="signage">
            Nothing set up yet. A slot picks the Signage playlist for a screen on certain days and times. Choose a screen or group above to add one.
          </EmptyState>
        ) : (
          data.slots.map((s) => {
            const label = s.screen_id
              ? screenName(data.screens.find((x) => x.id === s.screen_id) ?? ({ id: s.screen_id, name: null } as Screen))
              : `Group: ${data.groups.find((g) => g.id === s.group_id)?.name ?? '—'}`
            return (
              <div key={s.id} className="list-row">
                <b>{label}</b> · {playlistName(s.playlist_id)} · {daysLabel(s.days)}
                {timeLabel(s.start_time, s.end_time) ? ` · ${timeLabel(s.start_time, s.end_time)}` : ' · all day'}
              </div>
            )
          })
        )}
      </div>
    </div>
  )
}
