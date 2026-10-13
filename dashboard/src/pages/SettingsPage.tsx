import { useState, type FormEvent } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Entitlement, Module } from '../types'
import { attempt, entitled, isHex, must, randomName } from '../lib'

const DEFAULT_PRIMARY = '#1f3a5f'
const DEFAULT_ACCENT = '#e8833a'

export default function SettingsPage() {
  const { org, reloadOrgs, isPlatformAdmin } = useApp()
  const b = org.branding
  const [name, setName] = useState(org.name)
  const [primary, setPrimary] = useState(isHex(b.primary_color) ? b.primary_color : DEFAULT_PRIMARY)
  const [accent, setAccent] = useState(isHex(b.accent_color) ? b.accent_color : DEFAULT_ACCENT)
  const [logo, setLogo] = useState(b.logo_url ?? '')
  const [channel, setChannel] = useState(b.youtube_channel_id ?? '')
  const [uploading, setUploading] = useState(false)
  const [saved, setSaved] = useState(false)

  async function uploadLogo(file: File | undefined) {
    if (!file) return
    if (!file.type.startsWith('image/')) return alert('Choose an image file.')
    setUploading(true)
    const ok = await attempt(async () => {
      const path = `${org.id}/branding/${randomName(file.name)}`
      const { error } = await supabase.storage.from('media').upload(path, file, { contentType: file.type, cacheControl: '3600' })
      if (error) throw new Error(error.message)
      setLogo(supabase.storage.from('media').getPublicUrl(path).data.publicUrl)
    })
    setUploading(false)
    return ok
  }

  async function save(e: FormEvent) {
    e.preventDefault()
    setSaved(false)
    const id = channel.trim()
    if (id && !/^UC[\w-]{22}$/.test(id)) return alert("That doesn't look like a YouTube channel ID. It starts with UC and is 24 characters long.")
    const branding = {
      ...org.branding,
      logo_url: logo || undefined,
      primary_color: primary,
      accent_color: accent,
      youtube_channel_id: id || undefined,
    }
    const ok = await attempt(async () =>
      must(await supabase.from('organizations').update({ name: name.trim(), branding }).eq('id', org.id)),
    )
    if (ok) {
      setSaved(true)
      reloadOrgs()
    }
  }

  return (
    <div className="stack">
      <form className="card stack-sm" onSubmit={save}>
        <h3>Church</h3>
        <label className="field">
          <span>Name</span>
          <input value={name} onChange={(e) => setName(e.target.value)} required />
        </label>
        <p className="muted">Web address name: {org.slug}</p>

        <h3>Branding</h3>
        <div className="row wrap">
          {logo ? <img className="thumb logo-preview" src={logo} alt="Logo" /> : <span className="muted">No logo yet</span>}
          <label className="btn">
            {uploading ? 'Uploading…' : logo ? 'Replace logo' : 'Upload logo'}
            <input type="file" accept="image/*" hidden disabled={uploading} onChange={(e) => (uploadLogo(e.target.files?.[0]), (e.target.value = ''))} />
          </label>
          {logo && (
            <button type="button" className="link danger" onClick={() => setLogo('')}>
              Remove
            </button>
          )}
        </div>
        <div className="row wrap">
          <label className="field">
            <span>Primary colour</span>
            <input type="color" className="color" value={primary} onChange={(e) => setPrimary(e.target.value)} />
          </label>
          <label className="field">
            <span>Accent colour</span>
            <input type="color" className="color" value={accent} onChange={(e) => setAccent(e.target.value)} />
          </label>
          <button type="button" className="link align-end" onClick={() => (setPrimary(DEFAULT_PRIMARY), setAccent(DEFAULT_ACCENT))}>
            Reset colours
          </button>
        </div>
        <p className="muted">Colours apply to this dashboard and to the pairing, home, countdown and lyrics screens on your TVs.</p>
        <BrandPreview name={name} logo={logo} primary={primary} accent={accent} />

        <h3>YouTube (Kids)</h3>
        <label className="field">
          <span>YouTube channel ID</span>
          <input value={channel} onChange={(e) => setChannel(e.target.value)} placeholder="UC…" />
        </label>
        <p className="muted">
          Lets Kids playlists pick from your recent live streams and use "Live now". Find it in YouTube Studio under
          Settings, Channel, Advanced settings.
        </p>
        <div className="row">
          <button className="btn primary">Save settings</button>
          {saved && <span className="notice">Saved.</span>}
        </div>
      </form>

      <Plan />
      {isPlatformAdmin && <PlatformEntitlements />}
    </div>
  )
}

function Plan() {
  const { entitlements } = useApp()
  const modules: Module[] = ['kids', 'signage']
  return (
    <div className="card stack-sm">
      <h3>Your plan</h3>
      {modules.map((m) => {
        const e = entitlements.find((x) => x.module === m)
        return (
          <div key={m} className="list-row">
            <b>{m === 'kids' ? 'Kids' : 'Signage'}</b> ·{' '}
            {e ? (
              <>
                <span className={entitled(e) ? 'notice' : 'error'}>{entitled(e) ? 'Enabled' : 'Not enabled'}</span>
                <span className="muted">
                  {' '}
                  · {e.status} · {e.plan} · up to {e.tv_limit} TV{e.tv_limit === 1 ? '' : 's'}
                </span>
              </>
            ) : (
              <span className="muted">Not included</span>
            )}
          </div>
        )
      })}
    </div>
  )
}

/** Platform admins (and only they, by row-level security) can switch modules on for a church. */
function PlatformEntitlements() {
  const { org, entitlements, reloadOrg } = useApp()
  return (
    <div className="card stack-sm">
      <h3>Platform admin: modules for {org.name}</h3>
      {(['kids', 'signage'] as Module[]).map((m) => (
        <EntitlementRow key={m} module={m} current={entitlements.find((e) => e.module === m)} onSaved={reloadOrg} orgId={org.id} />
      ))}
    </div>
  )
}

function EntitlementRow({ module, current, orgId, onSaved }: { module: Module; current?: Entitlement; orgId: string; onSaved: () => void }) {
  const [status, setStatus] = useState<Entitlement['status']>(current?.status ?? 'active')
  const [limit, setLimit] = useState(current?.tv_limit ?? 5)
  const [plan, setPlan] = useState(current?.plan ?? 'standard')
  const [grace, setGrace] = useState(current?.grace_ends_at?.slice(0, 10) ?? '')

  async function save() {
    const row = {
      organization_id: orgId,
      module,
      status,
      tv_limit: limit,
      plan,
      grace_ends_at: grace ? new Date(grace).toISOString() : null,
    }
    if (await attempt(async () => must(await supabase.from('entitlements').upsert(row)))) onSaved()
  }

  return (
    <div className="row wrap list-row">
      <b style={{ width: 70 }}>{module === 'kids' ? 'Kids' : 'Signage'}</b>
      <label className="field">
        <span>Status</span>
        <select value={status} onChange={(e) => setStatus(e.target.value as Entitlement['status'])}>
          {['trialing', 'active', 'past_due', 'canceled'].map((s) => (
            <option key={s}>{s}</option>
          ))}
        </select>
      </label>
      <label className="field">
        <span>TV limit</span>
        <input type="number" min={0} style={{ width: 80 }} value={limit} onChange={(e) => setLimit(Number(e.target.value))} />
      </label>
      <label className="field">
        <span>Plan</span>
        <input value={plan} style={{ width: 120 }} onChange={(e) => setPlan(e.target.value)} />
      </label>
      <label className="field">
        <span>Grace ends</span>
        <input type="date" value={grace} onChange={(e) => setGrace(e.target.value)} />
      </label>
      <button className="btn align-end" onClick={save}>
        Save
      </button>
    </div>
  )
}

function luminance(hex: string) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

/** Live mock-ups of what the TVs will show with the chosen logo and colours. */
function BrandPreview({ name, logo, primary, accent }: { name: string; logo: string; primary: string; accent: string }) {
  const tooLight = luminance(primary) > 0.45
  const mark = logo ? <img src={logo} alt="" className="tv-logo" /> : <span className="tv-name">{name.toUpperCase()}</span>
  return (
    <div className="stack-sm">
      <div className="tv-previews">
        <div className="tv-mock" style={{ background: '#fff' }}>
          {mark}
          <div className="tv-center">
            <div className="tv-title" style={{ color: primary }}>Pair this TV</div>
            <div className="tv-code" style={{ background: primary }}>RJH CM5</div>
          </div>
        </div>
        <div className="tv-mock" style={{ background: primary }}>
          <div className="tv-center">
            <div className="tv-kicker" style={{ color: accent }}>SERVICE STARTS IN</div>
            <div className="tv-clock">4:59</div>
          </div>
        </div>
      </div>
      {tooLight && <p className="notice warn">Your primary colour is quite light. White text on the TV countdown and lyrics screens may be hard to read.</p>}
    </div>
  )
}
