import { Suspense, lazy, useCallback, useEffect, useMemo, useState, type FormEvent, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'
import { AppContext, useApp, type AppState } from './context'
import type { Entitlement, Location, Membership, Module, ModuleDef, Organization, Role, Site } from './types'
import { FALLBACK_MODULES, entitled, isHex, must, roleLabel, slugify, useLoad } from './lib'
import { ModuleOff } from './ui'
import { onColor, readableOnDark, setThemeMode, useTheme, type ThemeMode } from './theme'
import SchedulePage from './pages/SchedulePage'
import PlaylistsPage from './pages/PlaylistsPage'
import MediaPage from './pages/MediaPage'
import SignagePlaylistsPage from './pages/SignagePlaylistsPage'
import SignageSlotsPage from './pages/SignageSlotsPage'
import ScreensPage from './pages/ScreensPage'
import SitesPage from './pages/SitesPage'
import PeoplePage from './pages/PeoplePage'
import SettingsPage from './pages/SettingsPage'
import GetStartedPage from './pages/GetStartedPage'
import { helpUrl } from './links'
import { canControlNav } from './control/logic'
import TrialBanner from './admin/TrialBanner'
import { canLeave } from './slides/unsaved'
import './getstarted.css'

// The calendar (and FullCalendar) loads on first visit so the main bundle stays small.
// The Control page (live remote for the TVs) is lazy too.
const ControlPage = lazy(() => import('./control/ControlPage'))
const CalendarPage = lazy(() => import('./calendar/CalendarPage'))
// The shared song library (and its editor/importer) loads on first visit too.
const SongsPage = lazy(() => import('./pages/SongsPage'))
// The Slides module (decks, themes, schedule) is lazy too, so the main bundle does not grow.
const DecksPage = lazy(() => import('./slides/DecksPage'))
const ThemesPage = lazy(() => import('./slides/ThemesPage'))
const SlidesSchedulePage = lazy(() => import('./slides/SlidesSchedulePage'))
// The platform Admin console (all churches) is lazy too and only reachable by the platform owner.
const AdminChurchesPage = lazy(() => import('./admin/ChurchesPage'))
const AdminActivityPage = lazy(() => import('./admin/ActivityPage'))
const adminPage = (page: ReactNode) => <Suspense fallback={<p className="muted">Loading…</p>}>{page}</Suspense>
const slidesPage = (page: ReactNode) => <Suspense fallback={<p className="muted">Loading…</p>}>{page}</Suspense>

type PageDef = { label: string; title?: string; render: () => ReactNode; module?: Module; adminOnly?: boolean; /** Only the platform owner; hidden from everyone else. */ platformOnly?: boolean; /** Shown to anyone who has at least one of these applications. */ anyModule?: Module[]; /** Extra rule, given the app state (e.g. a role check). */ visibleIf?: (s: AppState) => boolean }

/**
 * Pages each application contributes to its nav group. Adding an application = one row in the `modules`
 * table plus an entry here; an application without an entry still gets its Media library.
 */
const MODULE_PAGES: Record<string, { slug: string; label: string; render: () => ReactNode }[]> = {
  kids: [
    { slug: 'schedule', label: 'Schedule', render: () => <SchedulePage /> },
    { slug: 'playlists', label: 'Playlists', render: () => <PlaylistsPage /> },
  ],
  signage: [
    { slug: 'playlists', label: 'Playlists', render: () => <SignagePlaylistsPage /> },
    { slug: 'slots', label: 'Slots & schedule', render: () => <SignageSlotsPage /> },
  ],
  // Only shown once the registry row (modules.id = 'slides') is available; FALLBACK_MODULES deliberately leaves it out.
  slides: [
    { slug: 'decks', label: 'Decks', render: () => slidesPage(<DecksPage />) },
    { slug: 'themes', label: 'Themes', render: () => slidesPage(<ThemesPage />) },
    { slug: 'schedule', label: 'Schedule', render: () => slidesPage(<SlidesSchedulePage />) },
  ],
}

const MANAGE_PAGES: Record<string, PageDef> = {
  screens: { label: 'Screens', render: () => <ScreensPage /> },
  sites: { label: 'Sites & Locations', render: () => <SitesPage /> },
  people: { label: 'People', render: () => <PeoplePage />, adminOnly: true },
  settings: { label: 'Settings', render: () => <SettingsPage />, adminOnly: true },
}

/** Page definitions and nav groups, derived from the application registry. */
function buildNav(modules: ModuleDef[]) {
  const pages: Record<string, PageDef> = {}
  const groups: { title: string; module?: Module; pages: string[] }[] = []
  for (const m of modules) {
    const keys: string[] = []
    for (const p of MODULE_PAGES[m.id] ?? []) {
      const key = `${m.id}-${p.slug}`
      pages[key] = { label: p.label, render: p.render, module: m.id }
      keys.push(key)
    }
    const key = `${m.id}-media`
    pages[key] = { label: 'Media', title: `${m.name} media`, render: () => <MediaPage key={m.id} module={m.id} />, module: m.id }
    keys.push(key)
    groups.push({ title: m.name, module: m.id, pages: keys })
  }
  pages.calendar = {
    label: 'Calendar',
    anyModule: ['kids', 'signage', 'slides'],
    render: () => (
      <Suspense fallback={<p className="muted">Loading the calendar…</p>}>
        <CalendarPage />
      </Suspense>
    ),
  }
  groups.unshift({ title: 'Schedule', pages: ['calendar'] })
  pages.control = {
    label: 'Control',
    title: 'Control',
    visibleIf: (s) => canControlNav(s.role, s.moduleOn),
    render: () => (
      <Suspense fallback={<p className="muted">Loading the remote…</p>}>
        <ControlPage />
      </Suspense>
    ),
  }
  groups.unshift({ title: 'Control', pages: ['control'] })
  pages.getstarted = { label: 'Get started', adminOnly: true, render: () => <GetStartedPage /> }
  groups.unshift({ title: 'Start', pages: ['getstarted'] })
  // The song library belongs to the church, not to one application, so it sits outside the Kids group.
  pages.songs = {
    label: 'Songs',
    anyModule: ['kids', 'slides'],
    render: () => (
      <Suspense fallback={<p className="muted">Loading songs…</p>}>
        <SongsPage />
      </Suspense>
    ),
  }
  groups.push({ title: 'Library', pages: ['songs'] })
  Object.assign(pages, MANAGE_PAGES)
  groups.push({ title: 'Manage', pages: Object.keys(MANAGE_PAGES) })
  pages['admin-churches'] = { label: 'Churches', title: 'Admin: churches', platformOnly: true, render: () => adminPage(<AdminChurchesPage />) }
  pages['admin-activity'] = { label: 'Activity', title: 'Admin: activity', platformOnly: true, render: () => adminPage(<AdminActivityPage />) }
  groups.push({ title: 'Admin', pages: ['admin-churches', 'admin-activity'] })
  return { pages, groups }
}

const ORG_KEY = 'churchtvos.org'
const readStoredOrg = () => {
  try {
    return localStorage.getItem(ORG_KEY)
  } catch {
    return null
  }
}

export default function App() {
  const [session, setSession] = useState<Session | null>()

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_event, s) => setSession(s))
    return () => data.subscription.unsubscribe()
  }, [])

  if (session === undefined) return null
  if (!session) return <Login />
  return <SignedIn session={session} />
}

function Wordmark() {
  return <span className="wordmark">Church TV OS</span>
}

/** Loads who you are and which churches you can see, then picks the active one. */
function SignedIn({ session }: { session: Session }) {
  const uid = session.user.id
  const email = session.user.email ?? ''
  const [orgId, setOrgId] = useState<string | null>(readStoredOrg)
  const [creating, setCreating] = useState(false)

  const { data, error, reload } = useLoad(async () => {
    const [orgs, memberships, platform] = await Promise.all([
      supabase.from('organizations').select('*').order('name'),
      supabase.from('memberships').select('*').eq('user_id', uid),
      supabase.rpc('is_platform_admin'),
    ])
    return {
      orgs: must(orgs) as Organization[],
      memberships: must(memberships) as Membership[],
      platform: must(platform) === true,
    }
  }, [uid])

  const signOut = () => supabase.auth.signOut()

  function switchOrg(id: string) {
    setOrgId(id)
    setCreating(false)
    try {
      localStorage.setItem(ORG_KEY, id)
    } catch {
      /* private mode: the choice just isn't remembered */
    }
  }

  if (error)
    return (
      <div className="center-screen">
        <div className="card narrow">
          <Wordmark />
          <p className="error">Couldn't load your account: {error}</p>
          <button className="btn" onClick={reload}>
            Try again
          </button>
          <button className="link" onClick={signOut}>
            Sign out
          </button>
        </div>
      </div>
    )
  if (!data) return null

  const org = data.orgs.find((o) => o.id === orgId) ?? data.orgs[0]
  if (!org || creating) {
    return (
      <CreateOrg
        email={email}
        canCancel={!!org}
        onCancel={() => setCreating(false)}
        onCreated={(id) => {
          location.hash = 'getstarted' // a brand-new church lands on the checklist
          reload()
          switchOrg(id)
        }}
        signOut={signOut}
      />
    )
  }

  return (
    <OrgApp
      key={org.id}
      uid={uid}
      email={email}
      org={org}
      orgs={data.orgs}
      membership={data.memberships.find((m) => m.organization_id === org.id) ?? null}
      isPlatformAdmin={data.platform}
      switchOrg={switchOrg}
      startCreateOrg={() => setCreating(true)}
      reloadOrgs={reload}
      signOut={signOut}
    />
  )
}

type OrgAppProps = {
  uid: string
  email: string
  org: Organization
  orgs: Organization[]
  membership: Membership | null
  isPlatformAdmin: boolean
  switchOrg: (id: string) => void
  startCreateOrg: () => void
  reloadOrgs: () => void
  signOut: () => void
}

/** Everything inside one church: its sites, locations, plan and navigation. */
function OrgApp(props: OrgAppProps) {
  const { uid, email, org, orgs, membership, isPlatformAdmin } = props

  const { data, error, reload } = useLoad(async () => {
    const [sites, locations, entitlements, modules] = await Promise.all([
      supabase.from('sites').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('locations').select('*').eq('organization_id', org.id).order('name'),
      supabase.from('entitlements').select('*').eq('organization_id', org.id),
      supabase.from('modules').select('*').eq('available', true).order('sort'),
    ])
    return {
      // If the registry can't be read, fall back to the built-in applications rather than locking people out.
      modules: modules.error || !modules.data?.length ? FALLBACK_MODULES : (modules.data as ModuleDef[]),
      sites: must(sites) as Site[],
      locations: must(locations) as Location[],
      entitlements: must(entitlements) as Entitlement[],
    }
  })

  const modules = data?.modules ?? FALLBACK_MODULES
  const nav = useMemo(() => buildNav(modules), [modules])
  const PAGES = nav.pages

  const [page, setPage] = useState(() => location.hash.slice(1))
  const [menuOpen, setMenuOpen] = useState(false)

  // Pages can link to each other by setting location.hash (e.g. the Get started checklist).
  useEffect(() => {
    const onHash = () => setPage(location.hash.slice(1))
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  // Apply the church's colours to the whole dashboard. In dark mode they are lightened until they read on the dark surface.
  const { resolved: theme } = useTheme()
  useEffect(() => {
    const root = document.documentElement
    const { primary_color: primary, accent_color: accent } = org.branding
    const dark = theme === 'dark'
    if (isHex(primary)) {
      const p = dark ? readableOnDark(primary) : primary
      root.style.setProperty('--primary', p)
      root.style.setProperty('--on-primary', onColor(p))
    }
    if (isHex(accent)) root.style.setProperty('--accent', dark ? readableOnDark(accent) : accent)
    return () => {
      root.style.removeProperty('--primary')
      root.style.removeProperty('--on-primary')
      root.style.removeProperty('--accent')
    }
  }, [org.branding, theme])

  const role: Role = membership?.role ?? 'owner' // platform admins without a membership act as owners
  const isAdmin = role === 'owner' || role === 'admin'
  const canEditRole = isAdmin || role === 'editor'
  const allSites = isAdmin || !membership || membership.site_ids === null

  const state = useMemo<AppState | null>(() => {
    if (!data) return null
    const hasModule = (m: Module) => isAdmin || !!membership?.modules.includes(m)
    const moduleOn = (m: Module) => hasModule(m) && entitled(data.entitlements.find((e) => e.module === m), org.status)
    const mySites = allSites ? data.sites : data.sites.filter((s) => membership?.site_ids?.includes(s.id))
    return {
      userId: uid,
      email,
      org,
      orgs,
      switchOrg: props.switchOrg,
      startCreateOrg: props.startCreateOrg,
      reloadOrgs: props.reloadOrgs,
      isPlatformAdmin,
      membership,
      role,
      isAdmin,
      canEditRole,
      entitlements: data.entitlements,
      modules: data.modules,
      moduleName: (id) => data.modules.find((m) => m.id === id)?.name ?? id.charAt(0).toUpperCase() + id.slice(1),
      hasModule,
      moduleOn,
      allSites,
      mySites,
      canEditContent: (m, siteId) =>
        canEditRole && moduleOn(m) && (allSites || (siteId !== null && !!membership?.site_ids?.includes(siteId))),
      sites: data.sites,
      locations: data.locations,
      reloadOrg: reload,
      signOut: props.signOut,
    }
  }, [data, org, orgs, membership, isPlatformAdmin, uid, email, role, isAdmin, canEditRole, allSites, reload, props])

  const visible = useCallback(
    (key: string) => {
      const def = PAGES[key]
      if (!state) return false
      if (def.platformOnly && !state.isPlatformAdmin) return false
      if (def.adminOnly && !state.isAdmin) return false
      if (def.module && !state.hasModule(def.module)) return false
      if (def.anyModule && !def.anyModule.some((m) => state.hasModule(m))) return false
      if (def.visibleIf && !def.visibleIf(state)) return false
      return true
    },
    [state, PAGES],
  )

  // Get started is reached from the nav (and right after a church is created), not as the everyday landing page.
  const firstPage = Object.keys(PAGES).find((k) => k !== 'getstarted' && visible(k)) ?? 'screens'
  const current = page in PAGES && visible(page) ? page : firstPage

  useEffect(() => {
    location.hash = current
    setMenuOpen(false)
  }, [current])

  if (error)
    return (
      <div className="center-screen">
        <div className="card narrow">
          <Wordmark />
          <p className="error">Couldn't load {org.name}: {error}</p>
          <button className="btn" onClick={reload}>
            Try again
          </button>
        </div>
      </div>
    )
  if (!state) return null

  const def = PAGES[current]
    const notEnabled = def.module ? !state.moduleOn(def.module) : false
  const logo = theme === 'dark' ? org.branding.logo_dark_url || org.branding.logo_url : org.branding.logo_url

  return (
    <AppContext.Provider value={state}>
      <div className="layout">
        <header className="appbar">
          <button className="menu-btn" aria-label="Menu" onClick={() => setMenuOpen((o) => !o)}>
            {menuOpen ? '✕' : '☰'}
          </button>
          <Wordmark />
          <OrgSwitcher />
          <a className="help-link" href={helpUrl()} target="_blank" rel="noreferrer">
            ? Help
          </a>
          <ThemeSwitch />
        </header>
        <div className="body">
          <nav className={`sidebar ${menuOpen ? 'open' : ''}`}>
            {nav.groups.map((group) => {
              const pages = group.pages.filter(visible)
              const showGroup = group.module ? state.hasModule(group.module) : true
              if (!showGroup || pages.length === 0) return null
              const locked = group.module ? !state.moduleOn(group.module) : false
              return (
                <div key={group.title} className="nav-group">
                  <div className="nav-title">
                    {group.title}
                    {locked && <span title="Not enabled for your church"> 🔒</span>}
                  </div>
                  {pages.map((key) => (
                    <button
                      key={key}
                      className={`nav-item ${current === key ? 'active' : ''}`}
                      onClick={() => canLeave() && setPage(key)}
                    >
                      {PAGES[key].label}
                    </button>
                  ))}
                </div>
              )
            })}
            <div className="sidebar-foot">
              <a className="help-link" href={helpUrl()} target="_blank" rel="noreferrer">
                ? Help Center
              </a>
              <div className="sidebar-email">{email}</div>
              <span className="muted">{state.isPlatformAdmin ? 'Platform admin' : roleLabel(role)}</span>
              <button className="link" onClick={state.signOut}>
                Sign out
              </button>
            </div>
          </nav>
          {menuOpen && <div className="scrim" onClick={() => setMenuOpen(false)} />}
          <main className="content">
            <TrialBanner />
            <div className="topbar">
              <h1>{def.title ?? def.label}</h1>
              {logo && <img className="org-logo" src={logo} alt={org.name} />}
            </div>
            {notEnabled && def.module ? <ModuleOff module={def.module} /> : def.render()}
          </main>
        </div>
      </div>
    </AppContext.Provider>
  )
}

function ThemeSwitch() {
  const { mode } = useTheme()
  return (
    <select className="theme-select" value={mode} aria-label="Theme" onChange={(e) => setThemeMode(e.target.value as ThemeMode)}>
      <option value="system">◐ System</option>
      <option value="light">☀ Light</option>
      <option value="dark">☾ Dark</option>
    </select>
  )
}

function OrgSwitcher() {
  const { org, orgs, switchOrg, startCreateOrg, isPlatformAdmin } = useApp()
  if (orgs.length <= 1 && !isPlatformAdmin) return <span className="pill org-pill">{org.name}</span>
  return (
    <select
      className="org-select"
      value={org.id}
      aria-label="Church"
      onChange={(e) => (e.target.value === '__new__' ? startCreateOrg() : switchOrg(e.target.value))}
    >
      {orgs.map((o) => (
        <option key={o.id} value={o.id}>
          {o.name}
        </option>
      ))}
      {isPlatformAdmin && <option value="__new__">+ New church…</option>}
    </select>
  )
}

function CreateOrg({
  email,
  canCancel,
  onCancel,
  onCreated,
  signOut,
}: {
  email: string
  canCancel: boolean
  onCancel: () => void
  onCreated: (id: string) => void
  signOut: () => void
}) {
  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [slugTouched, setSlugTouched] = useState(false)
  const [site, setSite] = useState('Main Campus')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const { data, error } = await supabase.rpc('create_organization', {
      p_name: name.trim(),
      p_slug: slug.trim(),
      p_site: site.trim() || 'Main Campus',
    })
    setBusy(false)
    if (error) {
      setError(/organizations_slug/.test(error.message) ? 'That web address is already taken. Try another.' : error.message)
      return
    }
    onCreated(data as string)
  }

  return (
    <div className="center-screen primary">
      <form className="card narrow" onSubmit={submit}>
        <Wordmark />
        <h2>Create your church</h2>
        <p className="muted">
          You're signed in as <b>{email}</b>, which isn't part of a church yet. Create one and you'll be its owner. If
          you were invited to an existing church, sign out and use the email address you were invited with.
        </p>
        <label className="field">
          <span>Church name</span>
          <input
            value={name}
            onChange={(e) => {
              setName(e.target.value)
              if (!slugTouched) setSlug(slugify(e.target.value))
            }}
            required
            autoFocus
          />
        </label>
        <label className="field">
          <span>Short name (letters, numbers, dashes)</span>
          <input
            value={slug}
            onChange={(e) => (setSlugTouched(true), setSlug(slugify(e.target.value)))}
            pattern="[a-z0-9][a-z0-9\-]{1,38}"
            title="2-39 characters: lowercase letters, numbers and dashes"
            required
          />
        </label>
        <label className="field">
          <span>First site (campus)</span>
          <input value={site} onChange={(e) => setSite(e.target.value)} required />
        </label>
        {error && <p className="error">{error}</p>}
        <button className="btn primary wide" disabled={busy}>
          {busy ? 'Creating…' : 'Create church'}
        </button>
        {canCancel && (
          <button type="button" className="link" onClick={onCancel}>
            Cancel
          </button>
        )}
        <button type="button" className="link" onClick={signOut}>
          Sign out
        </button>
      </form>
    </div>
  )
}

function Login() {
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setBusy(true)
    setError(null)
    setMessage(null)
    if (mode === 'signin') {
      const { error } = await supabase.auth.signInWithPassword({ email, password })
      if (error) setError(error.message)
    } else {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: { emailRedirectTo: location.origin },
      })
      if (error) setError(error.message)
      else if (!data.session) setMessage('Check your email for a confirmation link, then come back and sign in.')
    }
    setBusy(false)
  }

  return (
    <div className="center-screen primary">
      <form className="card narrow" onSubmit={submit}>
        <Wordmark />
        <h2>{mode === 'signin' ? 'Sign in' : 'Create your account'}</h2>
        <label className="field">
          <span>Email</span>
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required autoFocus autoComplete="email" />
        </label>
        <label className="field">
          <span>Password</span>
          <input
            type="password"
            value={password}
            minLength={8}
            onChange={(e) => setPassword(e.target.value)}
            required
            autoComplete={mode === 'signin' ? 'current-password' : 'new-password'}
          />
        </label>
        {error && <p className="error">{error}</p>}
        {message && <p className="notice">{message}</p>}
        <button className="btn primary wide" disabled={busy}>
          {mode === 'signin' ? 'Sign in' : 'Create account'}
        </button>
        <button type="button" className="link" onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}>
          {mode === 'signin' ? 'First time? Create an account' : 'Have an account? Sign in'}
        </button>
      </form>
    </div>
  )
}
