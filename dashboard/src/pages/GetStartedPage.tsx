import { useState, type ReactNode } from 'react'
import '../getstarted.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { isHex, useLoad } from '../lib'
import { AMAZON_APPSTORE_URL, GOOGLE_PLAY_URL, SIDELOAD_URL, helpUrl, type HelpTopic } from '../links'

const key = (what: string, orgId: string) => `churchtvos.${what}.${orgId}`
const readFlag = (k: string) => {
  try {
    return localStorage.getItem(k) === '1'
  } catch {
    return false
  }
}
const writeFlag = (k: string, on: boolean) => {
  try {
    if (on) localStorage.setItem(k, '1')
    else localStorage.removeItem(k)
  } catch {
    /* not remembered in private mode */
  }
}

/** Counts rows for this church. A failed query counts as 0 (the step simply stays open). */
async function count(table: string, orgId: string) {
  const { count: n } = await supabase.from(table).select('id', { count: 'exact', head: true }).eq('organization_id', orgId)
  return n ?? 0
}

type Step = { id: string; title: string; done: boolean; manual?: boolean; body: ReactNode; go?: { label: string; page: string }; help: HelpTopic }

function StoreLink({ name, url }: { name: string; url: string }) {
  return url ? (
    <a href={url} target="_blank" rel="noreferrer">
      {name}
    </a>
  ) : (
    <span>{name} (coming soon)</span>
  )
}

export default function GetStartedPage() {
  const { org, locations, modules, moduleOn, moduleName } = useApp()
  const [hidden, setHidden] = useState(() => readFlag(key('gsHidden', org.id)))
  const [installed, setInstalled] = useState(() => readFlag(key('gsInstalled', org.id)))

  const on = modules.filter((m) => (m.id === 'kids' || m.id === 'signage') && moduleOn(m.id))
  const kids = on.some((m) => m.id === 'kids')
  const signage = on.some((m) => m.id === 'signage')

  const { data } = useLoad(async () => {
    const [screens, media, kidsPlaylists, signagePlaylists, schedules, series, slots, rules, memberships] = await Promise.all(
      ['screens', 'media', 'playlists', 'signage_playlists', 'schedules', 'kids_series', 'signage_slots', 'screen_schedules', 'memberships'].map((t) =>
        count(t, org.id),
      ),
    )
    return { screens, media, playlists: kidsPlaylists + signagePlaylists, schedule: schedules + series + slots + rules, people: memberships }
  }, [org.id])

  const b = org.branding
  const branded =
    !!(b.logo_url || b.logo_dark_url) ||
    isHex(b.primary_color) ||
    isHex(b.accent_color) ||
    Object.values(b.modules ?? {}).some((l) => !!l && (l.logo_url || isHex(l.primary_color) || isHex(l.accent_color)))

  const mediaPage = `${kids ? 'kids' : 'signage'}-media`
  const playlistPage = `${kids ? 'kids' : 'signage'}-playlists`
  const names = on.map((m) => moduleName(m.id)).join(' and ')

  const steps: Step[] = [
    {
      id: 'brand',
      title: 'Make it yours',
      done: branded,
      help: 'branding',
      go: { label: 'Open Settings', page: 'settings' },
      body: <p>Set your church name, upload a logo and pick your colours. They show on the TVs and in this dashboard.</p>,
    },
    {
      id: 'sites',
      title: 'Add your sites and locations',
      done: locations.length > 0,
      help: 'ideas',
      go: { label: 'Open Sites & Locations', page: 'sites' },
      body: (
        <>
          <p>
            A <b>site</b> is a campus or building. A <b>location</b> is a room or area in it, like the Nursery or the Lobby.
            Tag each location with what it will show ({names || 'Kids or Signage'}): Kids rooms play curriculum, Signage
            locations play announcements.
          </p>
        </>
      ),
    },
    {
      id: 'app',
      title: 'Get the app on a TV',
      done: installed,
      manual: true,
      help: 'install',
      body: (
        <>
          <p>
            Church TV OS runs on Fire TV Stick 4K Max, Fire TV Cube and Fire OS Fire TVs, and on Google TV / Android TV
            devices. It does <b>not</b> run on the newest Fire TV sticks that use Vega OS.
          </p>
          <ul className="gs-list">
            <li>
              <StoreLink name="Amazon Appstore" url={AMAZON_APPSTORE_URL} />
            </li>
            <li>
              <StoreLink name="Google Play" url={GOOGLE_PLAY_URL} />
            </li>
            <li>
              Or install it directly:{' '}
              <a href={SIDELOAD_URL} target="_blank" rel="noreferrer">
                setup instructions
              </a>
            </li>
          </ul>
          <label className="check">
            <input
              type="checkbox"
              checked={installed}
              onChange={(e) => {
                setInstalled(e.target.checked)
                writeFlag(key('gsInstalled', org.id), e.target.checked)
              }}
            />
            I've installed the app
          </label>
        </>
      ),
    },
    {
      id: 'pair',
      title: 'Pair your first TV',
      done: (data?.screens ?? 0) > 0,
      help: 'screens',
      go: { label: 'Open Screens', page: 'screens' },
      body: <p>Open the app on the TV. It shows a 6-character code. Enter it under Screens, Pair a TV, and choose the location.</p>,
    },
    {
      id: 'media',
      title: 'Add media',
      done: (data?.media ?? 0) > 0,
      help: 'media',
      go: { label: 'Open Media', page: mediaPage },
      body: <p>Upload videos and images. Each application has its own library{on.length > 1 ? ` (${names})` : ''}, with folders to keep things tidy.</p>,
    },
    {
      id: 'playlist',
      title: 'Build a playlist',
      done: (data?.playlists ?? 0) > 0,
      help: kids ? 'kids' : 'signage',
      go: { label: 'Open Playlists', page: playlistPage },
      body: (
        <p>
          A playlist is the list of things a TV plays, in order.
          {signage && ' Signage playlists can include text signs and live streams, which need app version 1.1.0 or newer.'}
          {kids && ' Kids playlists can include videos, slides, countdowns, lyrics, YouTube and live streams.'}
        </p>
      ),
    },
    {
      id: 'schedule',
      title: 'Schedule it',
      done: (data?.schedule ?? 0) > 0,
      help: 'calendar',
      go: { label: 'Open Calendar', page: 'calendar' },
      body: <p>Drag across the calendar to say what plays, where and when. Repeat it weekly so you only do it once.</p>,
    },
    {
      id: 'people',
      title: 'Invite your team',
      done: (data?.people ?? 0) > 1,
      help: 'people',
      go: { label: 'Open People', page: 'people' },
      body: <p>Give volunteers and staff access to just the applications and sites they need. They sign in with the email you invite.</p>,
    },
  ]

  const doneCount = steps.filter((s) => s.done).length
  const pct = Math.round((doneCount / steps.length) * 100)
  const next = steps.find((s) => !s.done)
  const goTo = (page: string) => {
    location.hash = page
  }
  const setHide = (v: boolean) => {
    setHidden(v)
    writeFlag(key('gsHidden', org.id), v)
  }

  if (hidden)
    return (
      <div className="card stack-sm">
        <h3>The checklist is hidden</h3>
        <p className="muted">
          You can bring it back any time, or read the{' '}
          <a href={helpUrl()} target="_blank" rel="noreferrer">
            Help Center
          </a>
          .
        </p>
        <div>
          <button className="btn" onClick={() => setHide(false)}>
            Show checklist
          </button>
        </div>
      </div>
    )

  return (
    <div className="stack">
      <div className="card stack-sm">
        <div className="row spread wrap-sm">
          <h3>
            {doneCount} of {steps.length} steps done
          </h3>
          <button className="link" onClick={() => setHide(true)}>
            Hide checklist
          </button>
        </div>
        <div className="gs-progress" role="progressbar" aria-valuenow={pct} aria-valuemin={0} aria-valuemax={100} aria-label="Setup progress">
          <span style={{ width: `${pct}%` }} />
        </div>
        <p className="muted">
          Welcome to Church TV OS. Work through these in order, or jump to what you need. Each step ticks itself off when it
          is done. Stuck?{' '}
          <a href={helpUrl('quickstart')} target="_blank" rel="noreferrer">
            Read the 10-minute quick start
          </a>
          .
        </p>
      </div>

      {!next && (
        <div className="card gs-done stack-sm">
          <h3>You're all set</h3>
          <p>Everything is in place. Nice work. You can hide this checklist whenever you like, and the Help Center is always in the header.</p>
        </div>
      )}

      {steps.map((s, i) => (
        <div key={s.id} className={`card gs-step ${s.done ? 'done' : ''}`}>
          <span className="gs-mark" aria-label={s.done ? 'Done' : 'Not done yet'}>
            {s.done ? '✓' : i + 1}
          </span>
          <div className="gs-body">
            <h3>{s.title}</h3>
            {s.body}
            <div className="gs-actions">
              {s.go && (
                <button className={`btn${!s.done && s === next ? ' primary' : ''}`} onClick={() => goTo(s.go!.page)}>
                  {s.go.label}
                </button>
              )}
              <a href={helpUrl(s.help)} target="_blank" rel="noreferrer" title="Open the help page for this step">
                ? Help with this step
              </a>
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}
