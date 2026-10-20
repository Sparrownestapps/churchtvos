import { useCallback, useMemo, useRef, useState } from 'react'
import FullCalendar from '@fullcalendar/react'
import timeGridPlugin from '@fullcalendar/timegrid'
import dayGridPlugin from '@fullcalendar/daygrid'
import interactionPlugin from '@fullcalendar/interaction'
import type { DateSelectArg, DatesSetArg, EventClickArg, EventContentArg, EventDropArg, EventInput } from '@fullcalendar/core'
import type { DateClickArg, EventResizeDoneArg } from '@fullcalendar/interaction'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { MODULE_NAME, locationLabel, must, useLoad } from '../lib'
import type { Block, KidsSeries, NamedRow, PanelState, ResolvedTarget, SeriesOccurrence } from '../calendarTypes'
import type { Schedule, Screen, ScreenGroup, ScreenSchedule, SignageSlot } from '../types'
import SchedulePage from '../pages/SchedulePage'
import SignageSlotsPage from '../pages/SignageSlotsPage'
import { ChoiceDialog, Drawer, type DialogState } from './parts'
import { CreatePanel, EditPanel, type CalCtx } from './CalendarPanel'
import SeriesManager from './SeriesManager'
import { EmptyState } from '../ui'
import CopyWeek from './CopyWeek'
import { DAY_NAMES, addDays, browserTz, endToRule, fromWall, hm, hourDiff, ruleEnd, safeTz, toWall, tzAbbr, wallOf, weekStartOf, ymd } from './tz'
import '../calendar.css'

const screenName = (s: Screen) => s.name || `Screen ${s.id.slice(0, 6)}`
const TARGET_KEY = 'churchtvos.cal.target'
const readTarget = () => {
  try {
    return localStorage.getItem(TARGET_KEY) ?? ''
  } catch {
    return ''
  }
}

export default function CalendarPage() {
  const { hasModule } = useApp()
  const [mode, setMode] = useState<'calendar' | 'list'>('calendar')
  const [listKind, setListKind] = useState<'kids' | 'signage'>(hasModule('kids') ? 'kids' : 'signage')
  return (
    <div className="stack cal-page">
      <div className="segmented cal-mode">
        <button className={mode === 'calendar' ? 'on' : ''} onClick={() => setMode('calendar')}>
          Calendar
        </button>
        <button className={mode === 'list' ? 'on' : ''} onClick={() => setMode('list')}>
          List
        </button>
      </div>
      {mode === 'calendar' ? (
        <CalendarView />
      ) : (
        <div className="stack">
          {hasModule('kids') && hasModule('signage') && (
            <div className="segmented">
              <button className={listKind === 'kids' ? 'on' : ''} onClick={() => setListKind('kids')}>
                Kids schedule
              </button>
              <button className={listKind === 'signage' ? 'on' : ''} onClick={() => setListKind('signage')}>
                Signage slots
              </button>
            </div>
          )}
          {listKind === 'kids' && hasModule('kids') ? <SchedulePage /> : <SignageSlotsPage />}
        </div>
      )}
    </div>
  )
}

// ───────────────────────── overlap hints ─────────────────────────

type Hint = { id: string; group: string; s: number; e: number; prio: number; created: number; label: string; kids: boolean }
function overlapHints(items: Hint[]) {
  const out = new Map<string, string>()
  for (let i = 0; i < items.length; i++) {
    for (let j = i + 1; j < items.length; j++) {
      const a = items[i]
      const b = items[j]
      if (a.group !== b.group || !(a.s < b.e && b.s < a.e)) continue
      const aWins = a.prio !== b.prio ? a.prio > b.prio : a.created >= b.created
      const [w, l] = aWins ? [a, b] : [b, a]
      const reason = w.kids
        ? w.prio !== l.prio
          ? 'a one-time schedule replaces a repeating one'
          : 'the one that starts later takes over'
        : w.prio !== l.prio
          ? 'higher priority wins'
          : 'same priority, the newest wins'
      if (!out.has(l.id)) out.set(l.id, `Overlaps "${w.label}" (${reason}), so this one is overridden where they overlap.`)
      if (!out.has(w.id)) out.set(w.id, `Overlaps "${l.label}" (${reason}), so this one takes over where they overlap.`)
    }
  }
  return out
}

// ───────────────────────── the calendar ─────────────────────────

function CalendarView() {
  const { org, hasModule, isAdmin, canEditContent, locations, sites, mySites } = useApp()
  const calRef = useRef<FullCalendar>(null)
  const [targetKey, setTargetKey] = useState(readTarget)
  const [range, setRange] = useState<{ start: Date; end: Date; title: string; view: string } | null>(null)
  const [panel, setPanel] = useState<PanelState | null>(null)
  const [panelKey, setPanelKey] = useState(0)
  const [dialog, setDialog] = useState<DialogState | null>(null)
  const [copyOpen, setCopyOpen] = useState(false)
  const [phone] = useState(() => window.innerWidth < 640)

  const kidsOn = hasModule('kids')
  const signageOn = hasModule('signage')

  const base = useLoad(async () => {
    const none = Promise.resolve({ data: [], error: null })
    const [screens, groups, kp, sp, slots, rules, series] = await Promise.all([
      supabase.from('screens').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('screen_groups').select('*').eq('organization_id', org.id).order('name'),
      kidsOn ? supabase.from('playlists').select('id, name, site_id').eq('organization_id', org.id).order('name') : none,
      signageOn ? supabase.from('signage_playlists').select('id, name, site_id').eq('organization_id', org.id).order('name') : none,
      signageOn ? supabase.from('signage_slots').select('*').eq('organization_id', org.id) : none,
      supabase.from('screen_schedules').select('*').eq('organization_id', org.id),
      kidsOn ? supabase.from('kids_series').select('*').eq('organization_id', org.id) : none,
    ])
    return {
      screens: must(screens) as Screen[],
      groups: must(groups) as ScreenGroup[],
      kidsPlaylists: must(kp) as NamedRow[],
      signagePlaylists: must(sp) as NamedRow[],
      slots: must(slots) as SignageSlot[],
      rules: must(rules) as ScreenSchedule[],
      series: must(series) as KidsSeries[],
    }
  })
  const b = base.data

  const siteTz = useCallback(
    (locId: string | null) => safeTz(sites.find((s) => s.id === locations.find((l) => l.id === locId)?.site_id)?.timezone ?? sites[0]?.timezone),
    [sites, locations],
  )

  const options = useMemo(() => {
    const myLocs = locations.filter((l) => mySites.some((s) => s.id === l.site_id))
    return {
      screens: (b?.screens ?? []).map((s) => ({ key: `screen:${s.id}`, label: `${screenName(s)} · ${locations.find((l) => l.id === s.location_id)?.name ?? 'unpaired'}` })),
      groups: (b?.groups ?? []).map((g) => ({ key: `group:${g.id}`, label: g.name })),
      locations: myLocs.map((l) => ({ key: `loc:${l.id}`, label: locationLabel(l, sites) })),
    }
  }, [b, locations, mySites, sites])

  const target = useMemo<ResolvedTarget | null>(() => {
    if (!b) return null
    const all = [...options.screens, ...options.groups, ...options.locations]
    const key = all.some((o) => o.key === targetKey) ? targetKey : all[0]?.key
    if (!key) return null
    const [kind, id] = key.split(':')
    if (kind === 'screen') {
      const s = b.screens.find((x) => x.id === id)!
      return { kind: 'screen', id, label: screenName(s), tz: siteTz(s.location_id), screenIds: [id], groupIds: s.group_id ? [s.group_id] : [], locationIds: s.location_id ? [s.location_id] : [], mixedTz: false }
    }
    if (kind === 'group') {
      const members = b.screens.filter((s) => s.group_id === id)
      const locs = [...new Set(members.map((s) => s.location_id).filter((x): x is string => !!x))]
      const tzs = [...new Set(locs.map(siteTz))]
      return { kind: 'group', id, label: b.groups.find((g) => g.id === id)?.name ?? 'Group', tz: tzs[0] ?? siteTz(null), screenIds: [], groupIds: [id], locationIds: locs, mixedTz: tzs.length > 1 }
    }
    const members = b.screens.filter((s) => s.location_id === id)
    return {
      kind: 'location',
      id,
      label: locations.find((l) => l.id === id)?.name ?? 'Location',
      tz: siteTz(id),
      screenIds: members.map((s) => s.id),
      groupIds: [...new Set(members.map((s) => s.group_id).filter((x): x is string => !!x))],
      locationIds: [id],
      mixedTz: false,
    }
  }, [b, options, targetKey, siteTz, locations])

  const tz = target?.tz ?? browserTz()
  const rangeStart = range?.start.getTime()
  const rangeEnd = range?.end.getTime()

  // Things that depend on the visible dates: Kids one-offs, and repeating-schedule occurrences from the server.
  const dated = useLoad(
    async () => {
      if (!range || !kidsOn) return { schedules: [] as Schedule[], occ: [] as SeriesOccurrence[] }
      const from = fromWall(addDays(range.start, -1), tz)
      const to = fromWall(addDays(range.end, 1), tz)
      const openCutoff = new Date(from.getTime() - 14 * 86_400_000).toISOString()
      const [schedules, occ] = await Promise.all([
        supabase
          .from('schedules')
          .select('*')
          .eq('organization_id', org.id)
          .lt('starts_at', to.toISOString())
          .or(`ends_at.gt.${from.toISOString()},and(ends_at.is.null,starts_at.gt.${openCutoff})`),
        supabase.rpc('kids_series_occurrences', { p_org: org.id, p_from: from.toISOString(), p_to: to.toISOString(), p_location: null }),
      ])
      return { schedules: must(schedules) as Schedule[], occ: (must(occ) ?? []) as SeriesOccurrence[] }
    },
    [rangeStart, rangeEnd, tz, kidsOn],
  )

  const reloadAll = useCallback(() => {
    base.reload()
    dated.reload()
  }, [base, dated])

  const playlistName = useCallback(
    (kind: 'kids' | 'signage', id: string) => (kind === 'kids' ? b?.kidsPlaylists : b?.signagePlaylists)?.find((p) => p.id === id)?.name ?? 'Unknown playlist',
    [b],
  )

  // ───── permissions ─────
  const siteOfLoc = (locId: string) => locations.find((l) => l.id === locId)?.site_id ?? null
  const canKidsAt = (locId: string) => canEditContent('kids', siteOfLoc(locId))
  const canSignage = canEditContent('signage', null)
  const canCreate = canSignage || isAdmin || locations.some((l) => l.modules.includes('kids') && canEditContent('kids', l.site_id))

  // ───── events ─────
  const built = useMemo(() => {
    const events: EventInput[] = []
    if (!b || !target || !range) return { events, bandsOn: false }
    const blocks: { id: string; block: Block; start: Date; end: Date; group: string; prio: number; created: number }[] = []
    const locName = (id: string) => locations.find((l) => l.id === id)?.name ?? ''
    const multiLoc = target.locationIds.length > 1
    const mine = <T extends { screen_id: string | null; group_id: string | null }>(rows: T[]) =>
      rows.filter((r) => (r.screen_id && target.screenIds.includes(r.screen_id)) || (r.group_id && target.groupIds.includes(r.group_id)))
    const ruleSub = (r: { screen_id: string | null; group_id: string | null }) =>
      r.group_id ? `Group: ${b.groups.find((g) => g.id === r.group_id)?.name ?? '—'}` : target.kind === 'location' || target.kind === 'group' ? screenName(b.screens.find((s) => s.id === r.screen_id) ?? ({ id: r.screen_id ?? '', name: null } as Screen)) : undefined
    const ruleKey = (r: { screen_id: string | null; group_id: string | null }) => (target.kind === 'location' ? (r.screen_id ?? r.group_id ?? '') : 'x')

    // weekly rows on every visible day
    const slotRows = mine(b.slots)
    const moduleRows = mine(b.rules)
    for (let d = range.start, n = 0; d < range.end && n < 14; d = addDays(d, 1), n++) {
      const date = ymd(d)
      const dow = d.getUTCDay()
      for (const r of slotRows) {
        if (!r.days.includes(dow)) continue
        blocks.push({
          id: `slot:${r.id}:${date}`,
          start: wallOf(date, r.start_time),
          end: ruleEnd(date, r.end_time),
          group: `slot:${ruleKey(r)}`,
          prio: r.priority,
          created: Date.parse(r.created_at),
          block: {
            kind: 'slot',
            row: r,
            date,
            label: playlistName('signage', r.playlist_id),
            sub: ruleSub(r),
            editable: canSignage,
            lockReason: 'Signage slots can only be changed by editors with access to all sites.',
          },
        })
      }
      for (const r of moduleRows) {
        if (!r.days.includes(dow)) continue
        blocks.push({
          id: `mod:${r.id}:${date}`,
          start: wallOf(date, r.start_time),
          end: ruleEnd(date, r.end_time),
          group: `mod:${ruleKey(r)}`,
          prio: r.priority,
          created: Date.parse(r.created_at),
          block: {
            kind: 'module',
            row: r,
            date,
            label: r.module === 'off' ? 'Screen off' : `Switch to ${MODULE_NAME[r.module]}`,
            sub: ruleSub(r),
            editable: isAdmin,
            lockReason: 'Only owners and admins can change which module a screen runs.',
          },
        })
      }
    }

    // Kids one-offs (an open-ended one lasts until the next one in that room, else an hour on the grid)
    const all = (dated.data?.schedules ?? []).slice().sort((x, y) => Date.parse(x.starts_at) - Date.parse(y.starts_at))
    for (const s of all) {
      if (!target.locationIds.includes(s.location_id)) continue
      const next = all.find((o) => o.location_id === s.location_id && Date.parse(o.starts_at) > Date.parse(s.starts_at))
      const openEnded = !s.ends_at
      const endMs = s.ends_at ? Date.parse(s.ends_at) : next ? Date.parse(next.starts_at) : Date.parse(s.starts_at) + 3_600_000
      const editable = canKidsAt(s.location_id)
      blocks.push({
        id: `one:${s.id}`,
        start: toWall(Date.parse(s.starts_at), tz),
        end: toWall(endMs, tz),
        group: `kids:${s.location_id}`,
        prio: 1,
        created: Date.parse(s.starts_at),
        block: {
          kind: 'oneoff',
          row: s,
          openEnded,
          label: playlistName('kids', s.playlist_id),
          sub: multiLoc ? locName(s.location_id) : undefined,
          editable,
          lockReason: 'Kids schedules need editor access to this site.',
        },
      })
    }

    // Kids repeating (server-expanded occurrences)
    for (const o of dated.data?.occ ?? []) {
      if (!target.locationIds.includes(o.location_id)) continue
      const series = b.series.find((x) => x.id === o.series_id)
      if (!series) continue
      const sameTz = siteTz(o.location_id) === tz
      const editable = canKidsAt(o.location_id) && sameTz
      blocks.push({
        id: `ser:${o.series_id}:${o.on_date}`,
        start: toWall(Date.parse(o.starts_at), tz),
        end: toWall(Date.parse(o.ends_at), tz),
        group: `kids:${o.location_id}`,
        prio: 0,
        created: Date.parse(series.created_at),
        block: {
          kind: 'series',
          occ: o,
          series,
          label: o.is_override ? `${playlistName('kids', o.playlist_id)} (this date)` : `Week ${o.occurrence_no}: ${playlistName('kids', o.playlist_id)}`,
          sub: series.name || (multiLoc ? locName(o.location_id) : undefined),
          editable,
          lockReason: sameTz ? 'Kids schedules need editor access to this site.' : "This repeating schedule is in a different time zone than the one shown, so it can't be edited here.",
        },
      })
    }

    const hints = overlapHints(blocks.map((x) => ({ id: x.id, group: x.group, s: x.start.getTime(), e: x.end.getTime(), prio: x.prio, created: x.created, label: x.block.label, kids: x.group.startsWith('kids:') })))
    for (const x of blocks) {
      x.block.warn = hints.get(x.id)
      const resize = x.block.kind === 'oneoff' ? !x.block.openEnded : true
      events.push({
        id: x.id,
        title: x.block.label,
        start: x.start,
        end: x.end,
        classNames: ['cal-ev', `cal-ev-${x.block.kind}`, ...(x.block.kind === 'module' ? [`cal-ev-mod-${x.block.row.module === 'kids' || x.block.row.module === 'signage' || x.block.row.module === 'off' ? x.block.row.module : 'other'}`] : []), ...(x.block.editable ? [] : ['cal-locked'])],
        startEditable: x.block.editable,
        durationEditable: x.block.editable && resize,
        extendedProps: { block: x.block },
      })
    }

    // background band: which module is active when (a screen or group view only)
    const bandsOn = target.kind !== 'location'
    if (bandsOn) {
      const fallback = target.kind === 'screen' ? b.screens.find((s) => s.id === target.id)?.default_module : undefined
      for (let d = range.start, n = 0; d < range.end && n < 14; d = addDays(d, 1), n++) {
        const dow = d.getUTCDay()
        const date = ymd(d)
        const todays = moduleRows.filter((r) => r.days.includes(dow))
        const mins = (t: string) => (t >= '23:59' ? 1440 : Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5)))
        const cuts = [...new Set([0, 1440, ...todays.flatMap((r) => [mins(r.start_time), mins(r.end_time)])])].sort((x, y) => x - y)
        let run: { from: number; to: number; module: string } | null = null
        const flush = () => {
          if (!run) return
          events.push({
            id: `band:${date}:${run.from}`,
            start: new Date(wallOf(date).getTime() + run.from * 60_000),
            end: new Date(wallOf(date).getTime() + run.to * 60_000),
            display: 'background',
            classNames: ['cal-band', `cal-band-${run.module === 'kids' || run.module === 'signage' || run.module === 'off' ? run.module : 'other'}`],
          })
          run = null
        }
        for (let i = 0; i + 1 < cuts.length; i++) {
          const [from, to] = [cuts[i], cuts[i + 1]]
          const winner = todays
            .filter((r) => mins(r.start_time) <= from && from < mins(r.end_time))
            .sort((x, y) => y.priority - x.priority || Date.parse(y.created_at) - Date.parse(x.created_at))[0]
          const module = winner?.module ?? fallback
          if (run && module === run.module) run.to = to
          else {
            flush()
            if (module) run = { from, to, module }
          }
        }
        flush()
      }
    }
    return { events, bandsOn }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [b, target, range, dated.data, tz, canSignage, isAdmin, locations, playlistName, siteTz])

  // ───── actions ─────
  const api = () => calRef.current?.getApi()
  const openPanel = useCallback((p: PanelState | null) => {
    setPanel(p)
    setPanelKey((k) => k + 1)
  }, [])
  const closePanel = useCallback(() => {
    setPanel(null)
    calRef.current?.getApi().unselect()
  }, [])

  const ctx: CalCtx | null =
    b && target
      ? { tz, target, screens: b.screens, groups: b.groups, kidsPlaylists: b.kidsPlaylists, signagePlaylists: b.signagePlaylists, slots: b.slots, rules: b.rules, reload: reloadAll, openPanel }
      : null

  const openCreateAt = (s: Date, e: Date | null) => {
    const end = e && ymd(e) === ymd(s) ? hm(e) : e ? '23:59' : hm(new Date(Math.min(s.getTime() + 3_600_000, wallOf(ymd(s), '23:59').getTime())))
    openPanel({ mode: 'create', date: ymd(s), start: hm(s), end })
  }
  const onSelect = (sel: DateSelectArg) => {
    if (canCreate) openCreateAt(sel.start, sel.end)
  }
  const onDateClick = (info: DateClickArg) => {
    if (canCreate) openCreateAt(info.date, null)
  }
  const onEventClick = (info: EventClickArg) => {
    const block = info.event.extendedProps.block as Block | undefined
    if (block) openPanel({ mode: 'edit', block })
  }

  async function write(p: PromiseLike<{ error: { message: string } | null; data?: unknown }>, revert?: () => void) {
    try {
      must(await (p as PromiseLike<{ data: unknown; error: { message: string } | null }>))
    } catch (e) {
      alert((e as Error).message)
      revert?.()
      return false
    }
    reloadAll()
    return true
  }

  /** A block was dragged or resized. */
  async function onChange(info: EventDropArg | EventResizeDoneArg) {
    const block = info.event.extendedProps.block as Block
    const revert = info.revert
    const newStart = info.event.start
    const newEnd = info.event.end
    const oldStart = info.oldEvent.start
    if (!newStart || !newEnd || !oldStart || !block.editable) return revert()
    const fail = (msg: string) => (alert(msg), revert())
    const ask = (d: Omit<DialogState, 'onCancel'>) => setDialog({ ...d, onCancel: revert })

    if (block.kind === 'oneoff') {
      const patch = { starts_at: fromWall(newStart, tz).toISOString(), ends_at: block.openEnded ? null : fromWall(newEnd, tz).toISOString() }
      await write(supabase.from('schedules').update(patch).eq('id', block.row.id), revert)
      return
    }

    const endRule = endToRule(newStart, newEnd)
    if (!endRule) return fail("A block can't run past midnight. Make it end by midnight, or add a second block for the next day.")
    const startRule = `${hm(newStart)}:00`
    const newDow = newStart.getUTCDay()
    const oldDow = oldStart.getUTCDay()

    if (block.kind === 'series') {
      const s = block.series
      const diff = Math.round((wallOf(ymd(newStart)).getTime() - wallOf(ymd(oldStart)).getTime()) / 86_400_000)
      const shift = (date: string) => ymd(addDays(wallOf(date), diff))
      const patch = {
        days: [...new Set(s.days.map((d) => (((d + diff) % 7) + 7) % 7))],
        start_time: startRule,
        end_time: endRule,
        start_date: shift(s.start_date),
        end_date: s.end_date ? shift(s.end_date) : null,
      }
      ask({
        title: 'Change the whole repeating schedule?',
        message: `Times for a repeating schedule can only be changed for every date at once. It will run ${diff ? `${diff > 0 ? '+' : ''}${diff} day${Math.abs(diff) === 1 ? '' : 's'} from now on, ` : ''}at ${hm(newStart)}-${hm(newEnd)}. Skipped or changed dates keep their original dates. To change just one date, click it instead.`,
        choices: [{ label: 'Change the whole series', run: async () => void (await write(supabase.from('kids_series').update(patch).eq('id', s.id), revert)) }],
      })
      return
    }

    const row = block.row
    const table = block.kind === 'slot' ? 'signage_slots' : 'screen_schedules'
    const times = { start_time: startRule, end_time: endRule }
    if (row.days.length === 1) {
      await write(supabase.from(table).update({ days: [newDow], ...times }).eq('id', row.id), revert)
      return
    }
    const delta = (newDow - oldDow + 7) % 7
    ask({
      title: 'This rule repeats on several days',
      message: `"${block.label}" runs ${row.days.length} days a week, and rules repeat every week (there is no one-time version).`,
      choices: [
        {
          label: `Change every day of the rule`,
          hint: delta ? `all days move ${delta} day${delta === 1 ? '' : 's'} later` : 'same days, new times',
          run: async () => void (await write(supabase.from(table).update({ days: [...new Set(row.days.map((d) => (d + delta) % 7))], ...times }).eq('id', row.id), revert)),
        },
        {
          label: `Only ${DAY_NAMES[oldDow]}s`,
          hint: `${DAY_NAMES[oldDow]} leaves the rule and gets its own rule on ${DAY_NAMES[newDow]}s`,
          run: async () => {
            const { id: _id, created_at: _c, ...rest } = row
            const copy: Record<string, unknown> = { ...rest, days: [newDow], ...times }
            const ok = await write(supabase.from(table).insert(copy), revert)
            if (ok) await write(supabase.from(table).update({ days: row.days.filter((d) => d !== oldDow) }).eq('id', row.id))
          },
        },
      ],
    })
  }

  // ───── render ─────
  const changeTarget = (k: string) => {
    setTargetKey(k)
    try {
      localStorage.setItem(TARGET_KEY, k)
    } catch {
      /* not remembered */
    }
  }
  const diffH = hourDiff(tz)
  const tzNote = `Times are in ${tz.replace(/_/g, ' ')} (${tzAbbr(tz)})${diffH ? `, ${Math.abs(diffH)} hour${Math.abs(diffH) === 1 ? '' : 's'} ${diffH > 0 ? 'ahead of' : 'behind'} your device` : ''}`
  const now = useCallback(() => toWall(Date.now(), tz), [tz])
  const view = range?.view ?? (phone ? 'timeGridDay' : 'timeGridWeek')
  const weekStart = weekStartOf(range?.start ?? now())

  const renderBlock = (arg: EventContentArg) => {
    const bl = arg.event.extendedProps.block as Block | undefined
    if (!bl) return <></>
    return (
      <div className="cal-ev-in" title={bl.warn}>
        <div className="cal-ev-title">
          {!bl.editable && <span className="cal-lock" role="img" aria-label="Locked">🔒</span>}
          {bl.kind === 'series' && <span aria-hidden>↻ </span>}
          <b>{bl.label}</b>
          {bl.warn && <span className="cal-warn" role="img" aria-label="Overlap warning">⚠</span>}
        </div>
        <div className="cal-ev-time">{arg.timeText}</div>
        {bl.sub && <div className="cal-ev-sub">{bl.sub}</div>}
      </div>
    )
  }

  if (base.error) return <p className="error">Couldn't load the calendar: {base.error}</p>
  if (!b || !target || !ctx) return base.data === undefined ? <p className="muted">Loading…</p> : <EmptyState help="calendar">The calendar shows what plays on a screen and when. Pair a TV under Screens (or add a location under Sites & Locations) first, then come back to drag out your schedule.</EmptyState>

  const go = (fn: 'prev' | 'next' | 'today') => api()?.[fn]()
  const setView = (v: string) => api()?.changeView(v)
  const panelTitle = panel?.mode === 'create' ? 'Add to the calendar' : panel?.mode === 'series' ? 'Repeating schedules' : panel?.mode === 'edit' ? 'Edit' : ''

  return (
    <div className="stack-sm">
      <div className="cal-bar">
        <label className="field cal-target">
          <span>Showing</span>
          <select value={`${target.kind === 'location' ? 'loc' : target.kind}:${target.id}`} onChange={(e) => changeTarget(e.target.value)}>
            {options.screens.length > 0 && (
              <optgroup label="Screens">
                {options.screens.map((o) => (
                  <option key={o.key} value={o.key}>
                    {o.label}
                  </option>
                ))}
              </optgroup>
            )}
            {options.groups.length > 0 && (
              <optgroup label="Screen groups">
                {options.groups.map((o) => (
                  <option key={o.key} value={o.key}>
                    {o.label}
                  </option>
                ))}
              </optgroup>
            )}
            {options.locations.length > 0 && (
              <optgroup label="Locations (Kids)">
                {options.locations.map((o) => (
                  <option key={o.key} value={o.key}>
                    {o.label}
                  </option>
                ))}
              </optgroup>
            )}
          </select>
        </label>
        <div className="row wrap-sm cal-actions">
          {canCreate && (
            <button
              className="btn primary"
              onClick={() => openPanel({ mode: 'create', date: ymd(range && range.start <= now() && now() < range.end ? now() : (range?.start ?? now())), start: '09:00', end: '10:00' })}
            >
              + Add
            </button>
          )}
          {kidsOn && (
            <button className="btn" onClick={() => openPanel({ mode: 'series' })}>
              Repeating schedules
            </button>
          )}
          {kidsOn && canCreate && (
            <button className="btn" onClick={() => setCopyOpen(true)}>
              Copy week
            </button>
          )}
        </div>
      </div>

      <div className="cal-nav">
        <div className="row">
          <button className="btn" onClick={() => go('prev')} aria-label="Previous">
            ‹
          </button>
          <button className="btn" onClick={() => go('today')}>
            Today
          </button>
          <button className="btn" onClick={() => go('next')} aria-label="Next">
            ›
          </button>
        </div>
        <b className="cal-title">{range?.title}</b>
        <div className="segmented">
          {[
            ['timeGridDay', 'Day'],
            ['timeGridThreeDay', '3 days'],
            ['timeGridWeek', 'Week'],
          ].map(([v, l]) => (
            <button key={v} className={view === v ? 'on' : ''} onClick={() => setView(v)}>
              {l}
            </button>
          ))}
        </div>
      </div>

      <div className="cal-meta">
        <span className={`cal-tz ${diffH || target.mixedTz ? 'differs' : ''}`} title={tz}>
          🕒 {tzNote}
          {target.mixedTz ? '. This group spans several time zones; Kids times are shown in the first' : ''}
        </span>
        <span className="cal-legend">
          <i className="lg cal-lg-oneoff" />Kids one-time <i className="lg cal-lg-series" />Kids repeating <i className="lg cal-lg-slot" />Signage <i className="lg cal-lg-module" />Module switch
          {built.bandsOn && <span className="muted"> · tinted background = module running</span>}
        </span>
      </div>

      <div className="cal-wrap card">
        <FullCalendar
          ref={calRef}
          plugins={[timeGridPlugin, dayGridPlugin, interactionPlugin]}
          initialView={phone ? 'timeGridDay' : 'timeGridWeek'}
          views={{ timeGridThreeDay: { type: 'timeGrid', duration: { days: 3 } } }}
          headerToolbar={false}
          timeZone="UTC"
          now={now}
          nowIndicator
          firstDay={1}
          allDaySlot={false}
          slotMinTime="00:00:00"
          slotMaxTime="24:00:00"
          slotDuration="00:30:00"
          snapDuration="00:15:00"
          slotLabelInterval="01:00"
          scrollTime="06:00:00"
          expandRows={false}
          height="100%"
          selectable={canCreate}
          selectMirror
          selectMinDistance={6}
          selectAllow={(span) => ymd(span.start) === ymd(new Date(span.end.getTime() - 1))}
          longPressDelay={350}
          eventLongPressDelay={350}
          selectLongPressDelay={350}
          editable
          eventStartEditable
          eventDurationEditable
          slotEventOverlap={false}
          dayHeaderFormat={{ weekday: 'short', month: 'numeric', day: 'numeric' }}
          events={built.events}
          eventContent={renderBlock}
          select={onSelect}
          dateClick={onDateClick}
          eventClick={onEventClick}
          eventDrop={onChange}
          eventResize={onChange}
          datesSet={(arg: DatesSetArg) =>
            setRange((r) => (r && r.start.getTime() === arg.start.getTime() && r.end.getTime() === arg.end.getTime() && r.view === arg.view.type && r.title === arg.view.title ? r : { start: arg.start, end: arg.end, title: arg.view.title, view: arg.view.type }))
          }
        />
      </div>
      <p className="muted">
        Drag across an empty time to add something (snaps to 15 minutes); on a phone, tap an empty time, or press and hold to drag.
        Drag a block to move it, or its bottom edge to resize. A ⚠ means two blocks overlap; a 🔒 means you can only view it.
      </p>

      {panel && (
        <Drawer title={panelTitle} onClose={closePanel} wide={panel.mode === 'series'}>
          {panel.mode === 'create' && <CreatePanel key={panelKey} ctx={ctx} state={panel} onClose={closePanel} />}
          {panel.mode === 'edit' && <EditPanel key={panelKey} ctx={ctx} block={panel.block} onClose={closePanel} />}
          {panel.mode === 'series' && (
            <SeriesManager key={panelKey} locationIds={panel.focusId || target.locationIds.length === 0 ? undefined : target.locationIds} focusId={panel.focusId} onChanged={reloadAll} />
          )}
        </Drawer>
      )}
      {copyOpen && (
        <CopyWeek
          weekStart={weekStart}
          tz={tz}
          locationIds={target.locationIds}
          onClose={() => setCopyOpen(false)}
          onDone={reloadAll}
        />
      )}
      {dialog && <ChoiceDialog dialog={dialog} close={() => setDialog(null)} />}
    </div>
  )
}
