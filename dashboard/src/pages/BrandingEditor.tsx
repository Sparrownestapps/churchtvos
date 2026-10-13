import { useState } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Branding, Look } from '../types'
import { attempt, isHex, randomName } from '../lib'

const DEFAULT_PRIMARY = '#1f3a5f'
const DEFAULT_ACCENT = '#e8833a'
const DEFAULT_SPLASH_SECONDS = 5

type Scope = 'org' | 'kids' | 'signage'
const SCOPES: { id: Scope; label: string }[] = [
  { id: 'org', label: 'Church (default)' },
  { id: 'kids', label: 'Kids' },
  { id: 'signage', label: 'Signage' },
]

function lookOf(b: Branding, scope: Scope): Look {
  return scope === 'org' ? b : (b.modules?.[scope] ?? {})
}

/** The look a module actually uses: its own settings, else the church's. */
function resolve(b: Branding, scope: Scope) {
  const org = lookOf(b, 'org')
  const own = lookOf(b, scope)
  return {
    logo: own.logo_url ?? org.logo_url,
    logoDark: own.logo_dark_url ?? org.logo_dark_url,
    primary: isHex(own.primary_color) ? own.primary_color : isHex(org.primary_color) ? org.primary_color : DEFAULT_PRIMARY,
    accent: isHex(own.accent_color) ? own.accent_color : isHex(org.accent_color) ? org.accent_color : DEFAULT_ACCENT,
    splash: { ...org.splash, ...own.splash },
  }
}

function luminance(hex: string) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/** Dark logo on dark backgrounds when there is one; otherwise whichever logo exists. */
function logoFor(bg: string, light?: string, dark?: string) {
  return luminance(bg) < 0.4 ? (dark ?? light) : (light ?? dark)
}

export default function BrandingEditor({ value, onChange, name }: { value: Branding; onChange: (b: Branding) => void; name: string }) {
  const { org } = useApp()
  const [scope, setScope] = useState<Scope>('org')
  const [uploading, setUploading] = useState(false)
  const own = lookOf(value, scope)
  const isModule = scope !== 'org'
  const eff = resolve(value, scope)
  const customColours = isHex(own.primary_color) || isHex(own.accent_color)

  function patch(p: Partial<Look>) {
    if (scope === 'org') onChange({ ...value, ...p })
    else onChange({ ...value, modules: { ...value.modules, [scope]: { ...value.modules?.[scope], ...p } } })
  }

  async function upload(file: File | undefined, key: 'logo_url' | 'logo_dark_url') {
    if (!file) return
    if (!file.type.startsWith('image/')) return alert('Choose an image file.')
    setUploading(true)
    await attempt(async () => {
      const path = `${org.id}/branding/${randomName(file.name)}`
      const { error } = await supabase.storage.from('media').upload(path, file, { contentType: file.type, cacheControl: '3600' })
      if (error) throw new Error(error.message)
      patch({ [key]: supabase.storage.from('media').getPublicUrl(path).data.publicUrl })
    })
    setUploading(false)
  }

  function logoField(key: 'logo_url' | 'logo_dark_url', label: string, hint: string, dark: boolean) {
    const url = own[key]
    const inherited = isModule && !url ? lookOf(value, 'org')[key] : undefined
    return (
      <div className="stack-sm">
        <b>{label}</b>
        <div className="row wrap">
          {url || inherited ? (
            <img className="thumb logo-preview" src={url ?? inherited} alt="" style={{ background: dark ? '#1b2a4a' : '#fff', padding: 6 }} />
          ) : (
            <span className="muted">None</span>
          )}
          <label className="btn">
            {uploading ? 'Uploading…' : url ? 'Replace' : 'Upload'}
            <input type="file" accept="image/*" hidden disabled={uploading} onChange={(e) => (upload(e.target.files?.[0], key), (e.target.value = ''))} />
          </label>
          {url && (
            <button type="button" className="link danger" onClick={() => patch({ [key]: undefined })}>
              {isModule ? 'Use church logo' : 'Remove'}
            </button>
          )}
        </div>
        <p className="muted">{inherited && !url ? 'Using the church logo. ' : ''}{hint}</p>
      </div>
    )
  }

  const splash = eff.splash
  return (
    <div className="stack">
      <div className="row wrap">
        {SCOPES.map((s) => (
          <button key={s.id} type="button" className={`btn${scope === s.id ? ' primary' : ''}`} onClick={() => setScope(s.id)}>
            {s.label}
          </button>
        ))}
      </div>
      {isModule && <p className="muted">Anything you leave alone follows the church's look.</p>}

      {logoField('logo_url', 'Logo', 'Shown on light backgrounds (the pairing and home screens).', false)}
      {logoField('logo_dark_url', 'Logo for dark backgrounds', 'Optional. Used on the full-screen splash and on dark colours. Falls back to the logo above.', true)}

      <div className="stack-sm">
        <b>Colours</b>
        {isModule && (
          <label className="row">
            <input
              type="checkbox"
              checked={customColours}
              onChange={(e) =>
                e.target.checked
                  ? patch({ primary_color: eff.primary, accent_color: eff.accent })
                  : patch({ primary_color: undefined, accent_color: undefined })
              }
            />
            <span>Use different colours for {scope === 'kids' ? 'Kids' : 'Signage'}</span>
          </label>
        )}
        {(!isModule || customColours) && (
          <div className="row wrap">
            <label className="field">
              <span>Primary</span>
              <input type="color" className="color" value={eff.primary} onChange={(e) => patch({ primary_color: e.target.value })} />
            </label>
            <label className="field">
              <span>Accent</span>
              <input type="color" className="color" value={eff.accent} onChange={(e) => patch({ accent_color: e.target.value })} />
            </label>
            <button type="button" className="link align-end" onClick={() => patch({ primary_color: isModule ? eff.primary : DEFAULT_PRIMARY, accent_color: isModule ? eff.accent : DEFAULT_ACCENT })}>
              Reset colours
            </button>
          </div>
        )}
      </div>

      <div className="stack-sm">
        <b>Full-screen logo splash</b>
        <label className="row">
          <input type="checkbox" checked={!!splash.enabled} onChange={(e) => patch({ splash: { ...own.splash, enabled: e.target.checked } })} />
          <span>Show the logo full screen when the TV starts{isModule ? ' or switches to this module' : ' or switches module'}</span>
        </label>
        {splash.enabled && (
          <label className="field">
            <span>Seconds on screen</span>
            <input
              type="number"
              min={2}
              max={30}
              value={splash.seconds ?? DEFAULT_SPLASH_SECONDS}
              onChange={(e) => patch({ splash: { ...own.splash, enabled: true, seconds: Math.min(30, Math.max(2, Number(e.target.value) || DEFAULT_SPLASH_SECONDS)) } })}
            />
          </label>
        )}
      </div>

      <Preview name={name} eff={eff} />
    </div>
  )
}

/** Live mock-ups of what a TV will show with these settings. */
function Preview({ name, eff }: { name: string; eff: ReturnType<typeof resolve> }) {
  const tooLight = luminance(eff.primary) > 0.45
  const lightLogo = logoFor('#ffffff', eff.logo, eff.logoDark)
  const splashLogo = logoFor(eff.primary, eff.logo, eff.logoDark)
  const mark = lightLogo ? <img src={lightLogo} alt="" className="tv-logo" /> : <span className="tv-name">{name.toUpperCase()}</span>
  return (
    <div className="stack-sm">
      <div className="tv-previews">
        <div className="tv-mock" style={{ background: eff.primary }}>
          <div className="tv-center">
            {splashLogo ? <img src={splashLogo} alt="" className="tv-splash-logo" /> : <span className="tv-clock" style={{ fontSize: 18 }}>{name.toUpperCase()}</span>}
          </div>
          <span className="tv-tag">Splash</span>
        </div>
        <div className="tv-mock" style={{ background: '#fff' }}>
          {mark}
          <div className="tv-center">
            <div className="tv-title" style={{ color: eff.primary }}>Pair this TV</div>
            <div className="tv-code" style={{ background: eff.primary }}>RJH CM5</div>
          </div>
          <span className="tv-tag dark">Pairing / home</span>
        </div>
        <div className="tv-mock" style={{ background: eff.primary }}>
          <div className="tv-center">
            <div className="tv-kicker" style={{ color: eff.accent }}>SERVICE STARTS IN</div>
            <div className="tv-clock">4:59</div>
          </div>
          <span className="tv-tag">Countdown</span>
        </div>
      </div>
      {tooLight && <p className="notice warn">This primary colour is quite light. White text on the TV countdown and lyrics screens may be hard to read.</p>}
    </div>
  )
}
