import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { attempt, must } from '../lib'
import type { Domain } from '../calendarTypes'
import { DOMAINS, locationRuns, normSchedule } from './domain'
import { addDays, fmtDay, fromWall, toWall, weekStartOf, wallOf, ymd } from './tz'
import { Drawer } from './parts'
import '../calendar.css'

/**
 * Copies a week's Kids and Slides one-time schedules (rows in `schedules` and `deck_schedules`) to later weeks. Weekly
 * Signage slots, module switches and repeating Kids / Slides schedules already repeat by themselves, so they are never copied.
 */
export default function CopyWeek({
  weekStart,
  tz,
  locationIds,
  onClose,
  onDone,
}: {
  /** Monday 00:00 (wall) of the week to copy. */
  weekStart: Date
  tz: string
  locationIds: string[]
  onClose: () => void
  onDone: () => void
}) {
  const { org, canEditContent, locations, hasModule, modules } = useApp()
  const [mode, setMode] = useState<'next' | 'range'>('next')
  const [from, setFrom] = useState(ymd(addDays(weekStart, 7)))
  const [to, setTo] = useState(ymd(addDays(weekStart, 14)))
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState('')

  const slidesListed = hasModule('slides') && modules.some((m) => m.id === 'slides')
  const domains: Domain[] = [...(hasModule('kids') ? (['kids'] as const) : []), ...(slidesListed ? (['slides'] as const) : [])]
  const editableFor = (d: Domain) =>
    locationIds.filter((id) => {
      const l = locations.find((x) => x.id === id)
      return l && locationRuns(d, l) && canEditContent(d, l.site_id)
    })
  const editableAny = domains.some((d) => editableFor(d).length > 0)
  const label = slidesListed && hasModule('kids') ? 'Kids and Slides' : slidesListed ? 'Slides' : 'Kids'

  // Monday of each target week.
  const weeks: Date[] = []
  if (mode === 'next') weeks.push(addDays(weekStart, 7))
  else if (from && to && to >= from) {
    for (let w = weekStartOf(wallOf(from)); ymd(w) <= to && weeks.length < 52; w = addDays(w, 7)) weeks.push(w)
  }
  const offsets = weeks.map((w) => Math.round((w.getTime() - weekStart.getTime()) / 86_400_000)).filter((n) => n > 0)

  async function run() {
    if (!editableAny) return alert(`There is nothing here you can copy: you need edit access to a ${label} location.`)
    if (offsets.length === 0) return alert('Choose weeks after the one you are copying.')
    setBusy(true)
    const ok = await attempt(async () => {
      const from0 = fromWall(weekStart, tz).toISOString()
      const to0 = fromWall(addDays(weekStart, 7), tz).toISOString()
      const lastOffset = Math.max(...offsets)
      let copied = 0
      let skippedCount = 0
      let found = 0
      for (const d of domains) {
        const editable = editableFor(d)
        if (editable.length === 0) continue
        const dn = DOMAINS[d]
        const source = (must(
          await supabase.from(dn.schedTable).select('*').eq('organization_id', org.id).in('location_id', editable).gte('starts_at', from0).lt('starts_at', to0),
        ) as unknown[]).map((r) => normSchedule(d, r))
        if (source.length === 0) continue
        found += source.length
        // Skip anything already there (same room, playlist or deck, and start).
        const existing = (must(
          await supabase
            .from(dn.schedTable)
            .select(`location_id, ${dn.schedCol}, starts_at`)
            .eq('organization_id', org.id)
            .in('location_id', editable)
            .gte('starts_at', fromWall(addDays(weekStart, 7), tz).toISOString())
            .lt('starts_at', fromWall(addDays(weekStart, lastOffset + 7), tz).toISOString()),
        ) as unknown[]).map((r) => normSchedule(d, r))
        const have = new Set(existing.map((e) => `${e.location_id}|${e.playlist_id}|${Date.parse(e.starts_at)}`))
        const rows: Record<string, unknown>[] = []
        for (const off of offsets) {
          for (const s of source) {
            const starts = fromWall(addDays(toWall(Date.parse(s.starts_at), tz), off), tz)
            if (have.has(`${s.location_id}|${s.playlist_id}|${starts.getTime()}`)) continue
            rows.push({
              organization_id: org.id,
              location_id: s.location_id,
              [dn.schedCol]: s.playlist_id,
              starts_at: starts.toISOString(),
              ends_at: s.ends_at ? fromWall(addDays(toWall(Date.parse(s.ends_at), tz), off), tz).toISOString() : null,
            })
          }
        }
        if (rows.length) must(await supabase.from(dn.schedTable).insert(rows))
        copied += rows.length
        skippedCount += source.length * offsets.length - rows.length
      }
      if (found === 0) {
        setResult(`There are no one-time ${label} schedules in that week to copy.`)
        return
      }
      setResult(`Copied ${copied} block${copied === 1 ? '' : 's'}${skippedCount > 0 ? ` (skipped ${skippedCount} that already existed)` : ''}.`)
      onDone()
    })
    setBusy(false)
    if (!ok) setResult('')
  }

  return (
    <Drawer title="Copy this week" onClose={onClose}>
      <p>
        Copies the one-time {label} schedules in the week of <b>{fmtDay(ymd(weekStart))}</b> to later weeks, at the same days and times
        (daylight saving is handled).
      </p>
      <p className="muted">
        Weekly Signage slots, module switches and repeating {label} schedules already repeat every week, so they are not copied.
        Only locations you can edit are included.
      </p>
      <div className="segmented">
        <button className={mode === 'next' ? 'on' : ''} onClick={() => setMode('next')}>
          Next week
        </button>
        <button className={mode === 'range' ? 'on' : ''} onClick={() => setMode('range')}>
          A range of weeks
        </button>
      </div>
      {mode === 'range' && (
        <div className="row wrap">
          <label className="field">
            <span>From</span>
            <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          </label>
          <label className="field">
            <span>Through</span>
            <input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
          </label>
        </div>
      )}
      <p className="muted">
        {offsets.length} week{offsets.length === 1 ? '' : 's'} will be filled
        {offsets.length ? `, starting ${fmtDay(ymd(addDays(weekStart, Math.min(...offsets))))}` : ''}.
      </p>
      <button className="btn primary wide" disabled={busy} onClick={run}>
        {busy ? 'Copying…' : 'Copy'}
      </button>
      {result && <p className="notice">{result}</p>}
    </Drawer>
  )
}
