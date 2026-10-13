import { useState } from 'react'
import { supabase } from './supabase'
import { useApp } from './context'
import type { ScreenModule, ScreenSchedule, SignageSlot, SignagePlaylist } from './types'
import { MODULE_NAME, WEEK, attempt, daysLabel, must, summarizeRules, timeLabel } from './lib'

export function DayPicker({ value, onChange }: { value: number[]; onChange: (days: number[]) => void }) {
  const toggle = (d: number) => onChange(value.includes(d) ? value.filter((x) => x !== d) : [...value, d])
  return (
    <div className="stack-sm">
      <div className="days">
        {WEEK.map((d) => (
          <button
            type="button"
            key={d.value}
            className={`day ${value.includes(d.value) ? 'on' : ''}`}
            onClick={() => toggle(d.value)}
          >
            {d.short}
          </button>
        ))}
      </div>
      <div className="row">
        <button type="button" className="link" onClick={() => onChange([0, 1, 2, 3, 4, 5, 6])}>
          Every day
        </button>
        <button type="button" className="link" onClick={() => onChange([1, 2, 3, 4, 5])}>
          Weekdays
        </button>
        <button type="button" className="link" onClick={() => onChange([6, 0])}>
          Weekend
        </button>
      </div>
    </div>
  )
}

type Target = { screen_id: string } | { group_id: string }

type Props =
  | { kind: 'module'; rules: ScreenSchedule[]; target: Target; canEdit: boolean; onChanged: () => void }
  | { kind: 'slot'; rules: SignageSlot[]; target: Target; canEdit: boolean; onChanged: () => void; playlists: SignagePlaylist[] }

/**
 * Weekly rules for one screen or group: either "which module runs when" (screen_schedules)
 * or "which Signage playlist plays when" (signage_slots). The highest priority wins when rules overlap.
 */
export default function ScheduleRules(props: Props) {
  const { org } = useApp()
  const { kind, target, canEdit, onChanged } = props
  const table = kind === 'module' ? 'screen_schedules' : 'signage_slots'
  const [module, setModule] = useState<ScreenModule>('signage')
  const [playlistId, setPlaylistId] = useState('')
  const [days, setDays] = useState<number[]>([0, 1, 2, 3, 4, 5, 6])
  const [start, setStart] = useState('00:00')
  const [end, setEnd] = useState('23:59')
  const [priority, setPriority] = useState(0)

  const playlistName = (id: string) => (props.kind === 'slot' ? props.playlists.find((p) => p.id === id)?.name : undefined) ?? '—'

  async function add() {
    if (days.length === 0) return alert('Choose at least one day.')
    if (end <= start) return alert('The end time must be after the start time.')
    if (kind === 'slot' && !playlistId) return alert('Choose a playlist.')
    const row: Record<string, unknown> = {
      organization_id: org.id,
      ...target,
      days,
      start_time: start,
      end_time: end === '23:59' ? '23:59:59' : end,
      priority,
    }
    if (kind === 'module') row.module = module
    else row.playlist_id = playlistId
    if (await attempt(async () => must(await supabase.from(table).insert(row)))) onChanged()
  }

  async function remove(id: string) {
    if (!confirm('Remove this rule?')) return
    if (await attempt(async () => must(await supabase.from(table).delete().eq('id', id)))) onChanged()
  }

  const rules = [...props.rules].sort((a, b) => b.priority - a.priority)

  return (
    <div className="stack-sm">
      {props.kind === 'module' && (
        <p>
          <b>{summarizeRules(props.rules)}</b>
          {props.rules.length === 0 && <span className="muted"> (the screen's default module runs all the time)</span>}
        </p>
      )}
      {rules.length === 0 && props.kind === 'slot' && <p className="muted">No slots yet.</p>}
      {rules.map((r) => (
        <div key={r.id} className="row spread list-row">
          <span>
            <b>{'module' in r ? MODULE_NAME[r.module] : playlistName(r.playlist_id)}</b> · {daysLabel(r.days)}
            {timeLabel(r.start_time, r.end_time) ? ` · ${timeLabel(r.start_time, r.end_time)}` : ' · all day'}
            {r.priority !== 0 && <span className="muted"> · priority {r.priority}</span>}
          </span>
          {canEdit && (
            <button className="link danger" onClick={() => remove(r.id)}>
              Remove
            </button>
          )}
        </div>
      ))}

      {canEdit && (
        <div className="stack-sm rule-form">
          <span className="field-label">Add a rule</span>
          <div className="row wrap">
            {kind === 'module' ? (
              <label className="field">
                <span>Run</span>
                <select value={module} onChange={(e) => setModule(e.target.value as ScreenModule)}>
                  <option value="signage">Signage</option>
                  <option value="kids">Kids</option>
                  <option value="off">Off (black screen)</option>
                </select>
              </label>
            ) : (
              <label className="field grow">
                <span>Playlist</span>
                <select value={playlistId} onChange={(e) => setPlaylistId(e.target.value)}>
                  <option value="">Choose…</option>
                  {props.kind === 'slot' && props.playlists.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </label>
            )}
            <label className="field">
              <span>From</span>
              <input type="time" value={start} onChange={(e) => setStart(e.target.value)} />
            </label>
            <label className="field">
              <span>Until</span>
              <input type="time" value={end} onChange={(e) => setEnd(e.target.value)} />
            </label>
            <label className="field">
              <span>Priority</span>
              <input type="number" value={priority} style={{ width: 80 }} onChange={(e) => setPriority(Number(e.target.value))} />
            </label>
          </div>
          <DayPicker value={days} onChange={setDays} />
          <div>
            <button className="btn primary" onClick={add}>
              Add rule
            </button>
          </div>
          <p className="muted">
            Times are in the site's time zone. When rules overlap, the higher priority wins. Nothing matching means
            {kind === 'module' ? " the screen's default module." : " the screen's default Signage playlist (or a black screen)."}
          </p>
        </div>
      )}
    </div>
  )
}

