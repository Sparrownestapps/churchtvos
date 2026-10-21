import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Screen } from '../types'
import { MODULE_NAME, locationLabel } from '../lib'
import { EmptyState } from '../ui'
import '../control.css'
import GroupBar from './GroupBar'
import Remote from './Remote'
import {
  MIN_CONTROL_VERSION,
  STATE_LABEL,
  agoLabel,
  canControlNav,
  isOnline,
  progress,
  shownState,
  versionOk,
  type ScreenStatus,
} from './logic'

type Live = Pick<Screen, 'id' | 'last_seen_at' | 'app_version'>

export default function ControlPage() {
  const { org, role, moduleOn, sites, locations } = useApp()
  const allowed = canControlNav(role, moduleOn)
  const [screens, setScreens] = useState<Screen[] | null>(null)
  const [statuses, setStatuses] = useState<Record<string, ScreenStatus>>({})
  const [error, setError] = useState<string | null>(null)
  const [linkError, setLinkError] = useState(false)
  const [now, setNow] = useState(() => Date.now())
  const [hidden, setHidden] = useState(() => document.visibilityState === 'hidden')
  const [openId, setOpenId] = useState<string | null>(null)
  const [group, setGroup] = useState(false)
  const [selected, setSelected] = useState<string[]>([])
  const inflight = useRef(false)
  const ids = useRef<string[]>([])
  const polls = useRef(0)

  // The full list of screens, then light refreshes of status and last-seen.
  const poll = useCallback(async () => {
    if (!allowed || inflight.current) return
    inflight.current = true
    try {
      // Re-read the full list now and then so newly paired screens appear.
      if (ids.current.length === 0 || ++polls.current % 20 === 0) {
        const res = await supabase.from('screens').select('*').eq('organization_id', org.id).order('created_at')
        if (res.error) throw new Error(res.error.message)
        const list = (res.data ?? []) as Screen[]
        ids.current = list.map((s) => s.id)
        setScreens(list)
        if (list.length === 0) {
          setError(null)
          return
        }
      }
      const [live, st] = await Promise.all([
        supabase.from('screens').select('id, last_seen_at, app_version').in('id', ids.current),
        supabase.from('screen_status').select('*').in('screen_id', ids.current),
      ])
      if (live.error) throw new Error(live.error.message)
      if (st.error) throw new Error(st.error.message)
      const byId = new Map((live.data as Live[]).map((s) => [s.id, s]))
      setScreens((cur) => cur && cur.map((s) => ({ ...s, ...(byId.get(s.id) ?? {}) })))
      setStatuses(Object.fromEntries((st.data as ScreenStatus[]).map((r) => [r.screen_id, r])))
      setError(null)
      setLinkError(false)
    } catch (e) {
      setError((e as Error).message)
      setLinkError(true)
    } finally {
      inflight.current = false
      setNow(Date.now())
    }
  }, [allowed, org.id])

  useEffect(() => {
    if (!allowed) return
    const onVis = () => {
      const h = document.visibilityState === 'hidden'
      setHidden(h)
      if (!h) void poll()
    }
    document.addEventListener('visibilitychange', onVis)
    void poll()
    const t = window.setInterval(() => document.visibilityState === 'visible' && void poll(), 3000)
    const tick = window.setInterval(() => document.visibilityState === 'visible' && setNow(Date.now()), 1000)
    return () => {
      document.removeEventListener('visibilitychange', onVis)
      clearInterval(t)
      clearInterval(tick)
    }
  }, [allowed, poll])

  const openScreen = screens?.find((s) => s.id === openId) ?? null
  const online = useMemo(() => (screens ?? []).filter((s) => isOnline(s.last_seen_at, now)).length, [screens, now])

  if (!allowed)
    return (
      <div className="card stack-sm">
        <h3>Control isn't available to you</h3>
        <p className="muted">
          The remote is for owners, admins, editors and operators at a church that has Kids, Slides or Signage switched on. Ask your church's owner if you need it.
        </p>
      </div>
    )
  if (!screens && !error) return <p className="muted">Loading screens…</p>
  if (!screens)
    return (
      <div className="card stack-sm">
        <p className="error">Couldn't load your screens: {error}</p>
        <button className="btn" onClick={() => void poll()}>
          Try again
        </button>
      </div>
    )
  if (screens.length === 0)
    return (
      <EmptyState help="control">
        No screens are paired yet. Pair a TV on the <a href="#screens">Screens page</a>, and it will appear here as a remote.
      </EmptyState>
    )

  const toggle = (id: string) => setSelected((s) => (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]))

  return (
    <div className="stack ctl-page">
      <div className="row spread wrap-sm">
        <div className="row">
          <span className={`ctl-live ${linkError ? 'bad' : hidden ? 'paused' : 'ok'}`} title="Status refreshes every 3 seconds">
            <span className="ctl-live-dot" /> {linkError ? 'Connection problem' : hidden ? 'Paused' : 'Live'}
          </span>
          <span className="muted">
            {online} of {screens.length} online
          </span>
        </div>
        <div className="row wrap-sm">
          {group && (
            <button className="btn" onClick={() => setSelected(screens.filter((s) => isOnline(s.last_seen_at, now)).map((s) => s.id))}>
              Select online
            </button>
          )}
          <button
            className={`btn ${group ? 'primary' : ''}`}
            aria-pressed={group}
            onClick={() => {
              setGroup((g) => !g)
              setSelected([])
              setOpenId(null)
            }}
          >
            {group ? 'Done' : 'Send to several screens'}
          </button>
        </div>
      </div>
      {error && !linkError && <p className="error">{error}</p>}
      {linkError && <p className="ctl-warn">Can't reach the server right now ({error}). Showing the last known status; retrying.</p>}

      <div className="ctl-grid">
        {screens.map((s) => {
          const st = statuses[s.id]
          const state = shownState(s, st, now)
          const on = isOnline(s.last_seen_at, now)
          const p = progress(st)
          const showing = state !== 'idle' && state !== 'offline'
          const checked = selected.includes(s.id)
          const loc = locationLabel(locations.find((l) => l.id === s.location_id), sites)
          return (
            <div key={s.id} className={`ctl-cardwrap ${checked ? 'checked' : ''}`}>
              {group && (
                <input
                  type="checkbox"
                  className="ctl-check"
                  checked={checked}
                  onChange={() => toggle(s.id)}
                  aria-label={`Select ${s.name ?? 'screen'}`}
                />
              )}
              <button className="ctl-card card" onClick={() => (group ? toggle(s.id) : setOpenId(s.id))} aria-label={`${group ? 'Select' : 'Open remote for'} ${s.name ?? 'screen'}`}>
                <div className="ctl-card-top">
                  <span className={`ctl-dot ${on ? 'on' : ''}`} title={on ? 'Online' : 'Offline'} />
                  <div className="ctl-card-name">
                    <b>{s.name ?? 'Unnamed screen'}</b>
                    <span className="muted">{loc}</span>
                  </div>
                  <span className="badge">{MODULE_NAME[(showing && st?.module) || s.default_module]}</span>
                </div>
                <div className="ctl-card-state">
                  <span className={`ctl-chip s-${state}`}>{STATE_LABEL[state]}</span>
                  <span className="muted">{on ? agoLabel(st?.updated_at ?? s.last_seen_at, now) : `Seen ${agoLabel(s.last_seen_at, now)}`}</span>
                </div>
                <div className="ctl-showing">
                  {showing ? (
                    <>
                      <b>{st?.title || 'Untitled'}</b>
                      {st?.item_label && <span>{st.item_label}</span>}
                      {st?.slide_index != null && st.slide_count ? (
                        <span className="muted">
                          Slide {st.slide_index + 1} of {st.slide_count}
                        </span>
                      ) : null}
                    </>
                  ) : (
                    <span className="muted">{state === 'offline' ? 'Not connected' : 'Nothing playing'}</span>
                  )}
                </div>
                <div className="ctl-bar" aria-hidden="true">
                  <div style={{ width: `${Math.round((showing && p != null ? p : 0) * 100)}%` }} />
                </div>
                {!on && <div className="ctl-card-warn">TV offline</div>}
                {!versionOk(s.app_version) && (
                  <div className="ctl-card-warn">Needs app {MIN_CONTROL_VERSION}+ (this TV: {s.app_version ?? 'unknown'})</div>
                )}
              </button>
            </div>
          )
        })}
      </div>

      {group && <GroupBar screens={screens} selected={selected} refresh={() => void poll()} />}
      {openScreen && !group && (
        <Remote key={openScreen.id} screen={openScreen} status={statuses[openScreen.id]} now={now} refresh={() => void poll()} onClose={() => setOpenId(null)} />
      )}
    </div>
  )
}
