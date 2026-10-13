import { useState, type FormEvent } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Entitlement, Module } from '../types'
import { attempt, entitled, must } from '../lib'
import type { Branding } from '../types'
import BrandingEditor from './BrandingEditor'

export default function SettingsPage() {
  const { org, reloadOrgs, isPlatformAdmin } = useApp()
  const b = org.branding
  const [name, setName] = useState(org.name)
  const [look, setLook] = useState<Branding>(() => ({ ...b }))
  const [channel, setChannel] = useState(b.youtube_channel_id ?? '')
  const [saved, setSaved] = useState(false)

  async function save(e: FormEvent) {
    e.preventDefault()
    setSaved(false)
    const id = channel.trim()
    if (id && !/^UC[\w-]{22}$/.test(id)) return alert("That doesn't look like a YouTube channel ID. It starts with UC and is 24 characters long.")
    const branding = {
      ...look,
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
        <BrandingEditor value={look} onChange={setLook} name={name} />

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

