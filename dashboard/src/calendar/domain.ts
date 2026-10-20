import type { Location, Schedule } from '../types'
import type { Domain, KidsSeries, SeriesException, SeriesOccurrence } from '../calendarTypes'

/**
 * Kids playlists and Slides decks are scheduled the same way (dated rows, repeating series with a rotation, per-date
 * exceptions), only in different tables and column names. The calendar normalises Slides rows into the Kids shapes
 * (deck id -> `playlist_id`, `deck_ids` -> `playlist_ids`) so one set of screens serves both; these descriptors say
 * which table and column to use when reading and writing.
 */
export const DOMAINS: Record<
  Domain,
  {
    label: string
    /** What is scheduled, for button and field labels. */
    item: string
    schedTable: string
    schedCol: string
    seriesTable: string
    seriesCol: string
    excTable: string
    excCol: string
    excAction: string
    rpc: string
  }
> = {
  kids: {
    label: 'Kids',
    item: 'playlist',
    schedTable: 'schedules',
    schedCol: 'playlist_id',
    seriesTable: 'kids_series',
    seriesCol: 'playlist_ids',
    excTable: 'kids_series_exceptions',
    excCol: 'playlist_id',
    excAction: 'playlist',
    rpc: 'kids_series_occurrences',
  },
  slides: {
    label: 'Slides',
    item: 'deck',
    schedTable: 'deck_schedules',
    schedCol: 'deck_id',
    seriesTable: 'deck_series',
    seriesCol: 'deck_ids',
    excTable: 'deck_series_exceptions',
    excCol: 'deck_id',
    excAction: 'deck',
    rpc: 'deck_series_occurrences',
  },
}

type Row = Record<string, unknown>

export function normSchedule(d: Domain, r: unknown): Schedule {
  const row = r as Row
  const { [DOMAINS[d].schedCol]: item, ...rest } = row
  return { ...rest, playlist_id: item } as unknown as Schedule
}

export function normSeries(d: Domain, r: unknown): KidsSeries {
  const row = r as Row
  const { [DOMAINS[d].seriesCol]: items, ...rest } = row
  return { ...rest, playlist_ids: items } as unknown as KidsSeries
}

export function normOcc(d: Domain, r: unknown): SeriesOccurrence {
  const row = r as Row
  const { [DOMAINS[d].excCol]: item, ...rest } = row
  return { ...rest, playlist_id: item } as unknown as SeriesOccurrence
}

export function normException(d: Domain, r: unknown): SeriesException {
  const row = r as Row
  const { [DOMAINS[d].excCol]: item, action, ...rest } = row
  return { ...rest, action: action === 'skip' ? 'skip' : 'playlist', playlist_id: item ?? null } as unknown as SeriesException
}

/** The database row for a series exception (the normalised 'playlist' action becomes the domain's own word). */
export function exceptionRow(d: Domain, seriesId: string, onDate: string, action: 'skip' | 'playlist', itemId: string | null) {
  return { series_id: seriesId, on_date: onDate, action: action === 'skip' ? 'skip' : DOMAINS[d].excAction, [DOMAINS[d].excCol]: action === 'playlist' ? itemId : null }
}

/**
 * Can this location run content of this kind? Slides use rooms tagged Slides, or Kids as well while a church has not
 * tagged anything for Slides yet.
 */
export const locationRuns = (d: Domain, l: Pick<Location, 'modules'>) => (d === 'kids' ? l.modules.includes('kids') : l.modules.includes('slides') || l.modules.includes('kids'))
