import type { Schedule, ScreenSchedule, SignageSlot } from './types'

/** A repeating Kids schedule (public.kids_series). */
export type KidsSeries = {
  id: string
  organization_id: string
  location_id: string
  name: string | null
  /** 0 = Sunday */
  days: number[]
  start_time: string
  end_time: string
  start_date: string
  end_date: string | null
  /** The rotation, in order. */
  playlist_ids: string[]
  on_end: 'stop' | 'loop'
  created_at: string
}

export type SeriesException = {
  series_id: string
  on_date: string
  action: 'skip' | 'playlist'
  playlist_id: string | null
}

/** One row of the kids_series_occurrences() RPC. */
export type SeriesOccurrence = {
  series_id: string
  location_id: string
  on_date: string
  starts_at: string
  ends_at: string
  playlist_id: string
  occurrence_no: number
  is_override: boolean
}

export type NamedRow = { id: string; name: string; site_id?: string | null }

type BlockBase = { editable: boolean; lockReason?: string; warn?: string; label: string; sub?: string }
/** What a calendar event stands for (kept in event.extendedProps.block). */
export type Block =
  | (BlockBase & { kind: 'oneoff'; row: Schedule; openEnded: boolean })
  | (BlockBase & { kind: 'series'; occ: SeriesOccurrence; series: KidsSeries })
  | (BlockBase & { kind: 'slot'; row: SignageSlot; date: string })
  | (BlockBase & { kind: 'module'; row: ScreenSchedule; date: string })

export type PanelState =
  | { mode: 'create'; date: string; start: string; end: string; touch?: boolean; prefill?: Prefill }
  | { mode: 'edit'; block: Block }
  | { mode: 'series'; focusId?: string }

export type Prefill = {
  type?: 'kids' | 'signage' | 'module'
  playlistId?: string
  module?: string
  keys?: string[]
  days?: number[]
}

/** What the calendar is currently showing, resolved from the view picker. */
export type ResolvedTarget = {
  kind: 'screen' | 'group' | 'location'
  id: string
  label: string
  /** The site time zone the grid is drawn in. */
  tz: string
  /** Rows (slots / module rules) matching these screen ids or group ids are shown. */
  screenIds: string[]
  groupIds: string[]
  /** Kids schedules for these locations are shown. */
  locationIds: string[]
  /** Several time zones among the target's locations. */
  mixedTz: boolean
}
