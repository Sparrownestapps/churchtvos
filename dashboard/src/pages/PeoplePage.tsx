import { useState, type FormEvent } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Membership, Module, Role } from '../types'
import { attempt, must, roleLabel, useLoad } from '../lib'
import { EmptyState } from '../ui'

const ROLES: { value: Role; help: string }[] = [
  { value: 'owner', help: 'Everything, including people' },
  { value: 'admin', help: 'Manage people, sites, screens and content' },
  { value: 'editor', help: 'Edit content in their modules' },
  { value: 'operator', help: 'View only (for now)' },
]
type Draft = { email: string; role: Role; modules: Module[]; site_ids: string[] | null }
/** A new person starts with every available module (from the registry). */
const blankFor = (modules: Module[]): Draft => ({ email: '', role: 'editor', modules, site_ids: null })

export default function PeoplePage() {
  const { org, userId, sites, modules, moduleName } = useApp()
  const blank = blankFor(modules.map((m) => m.id))
  const [draft, setDraft] = useState<Draft>(blank)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [edit, setEdit] = useState<Draft>(blank)

  const { data: people, reload } = useLoad(
    async () => must(await supabase.from('memberships').select('*').eq('organization_id', org.id).order('email')) as Membership[],
  )

  async function invite(e: FormEvent) {
    e.preventDefault()
    if (draft.site_ids && draft.site_ids.length === 0) return alert('Choose at least one site, or pick all sites.')
    const row = { organization_id: org.id, email: draft.email.trim().toLowerCase(), role: draft.role, modules: draft.modules, site_ids: draft.site_ids }
    if (await attempt(async () => must(await supabase.from('memberships').insert(row)))) {
      setDraft(blank)
      reload()
    }
  }

  async function saveEdit(m: Membership) {
    if (edit.site_ids && edit.site_ids.length === 0) return alert('Choose at least one site, or pick all sites.')
    const ok = await attempt(async () =>
      must(await supabase.from('memberships').update({ role: edit.role, modules: edit.modules, site_ids: edit.site_ids }).eq('id', m.id)),
    )
    if (ok) {
      setEditingId(null)
      reload()
    }
  }

  async function remove(m: Membership) {
    if (!confirm(`Remove ${m.email}'s access?`)) return
    if (await attempt(async () => must(await supabase.from('memberships').delete().eq('id', m.id)))) reload()
  }

  return (
    <div className="stack">
      <form className="card stack-sm" onSubmit={invite}>
        <h3>Invite someone</h3>
        <label className="field">
          <span>Email</span>
          <input type="email" value={draft.email} onChange={(e) => setDraft({ ...draft, email: e.target.value })} required />
        </label>
        <AccessFields value={draft} onChange={setDraft} sites={sites} />
        <div>
          <button className="btn primary">Give access</button>
        </div>
        <p className="muted">
          No email is sent. Ask them to open this dashboard and sign in (or create an account) with this same email
          address and they'll see {org.name} straight away.
        </p>
      </form>

      {people && people.length <= 1 && (
        <EmptyState help="people">
          It's just you so far. Invite volunteers and staff above and choose which applications and sites they can use.
        </EmptyState>
      )}

      <div className="stack-sm">
        {(people ?? []).map((m) => {
          const mine = m.user_id === userId
          const scope = m.site_ids === null ? 'All sites' : m.site_ids.map((id) => sites.find((s) => s.id === id)?.name ?? '?').join(', ')
          return (
            <div key={m.id} className="card stack-sm">
              <div className="row spread wrap-sm">
                <div>
                  <h3>
                    {m.email} {mine && <span className="muted">(you)</span>}
                  </h3>
                  <span className="muted">
                    {roleLabel(m.role)} · {m.role === 'owner' || m.role === 'admin' ? 'All modules' : m.modules.filter((x) => modules.some((o) => o.id === x)).map((x) => moduleName(x)).join(', ') || 'No modules'} ·{' '}
                    {m.role === 'owner' || m.role === 'admin' ? 'All sites' : scope} · {m.user_id ? 'Active' : 'Invited, not signed up yet'}
                  </span>
                </div>
                <span className="row">
                  <button
                    className="link"
                    onClick={() => (setEditingId(editingId === m.id ? null : m.id), setEdit({ email: m.email, role: m.role, modules: m.modules, site_ids: m.site_ids }))}
                  >
                    {editingId === m.id ? 'Cancel' : 'Edit'}
                  </button>
                  {!mine && (
                    <button className="link danger" onClick={() => remove(m)}>
                      Remove
                    </button>
                  )}
                </span>
              </div>
              {editingId === m.id && (
                <div className="stack-sm panel">
                  <AccessFields value={edit} onChange={setEdit} sites={sites} />
                  <div>
                    <button className="btn primary" onClick={() => saveEdit(m)}>
                      Save
                    </button>
                  </div>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}

function AccessFields({ value, onChange, sites }: { value: Draft; onChange: (d: Draft) => void; sites: { id: string; name: string }[] }) {
  const { modules } = useApp()
  const everything = value.role === 'owner' || value.role === 'admin'
  const toggleModule = (m: Module) =>
    onChange({ ...value, modules: value.modules.includes(m) ? value.modules.filter((x) => x !== m) : [...value.modules, m] })
  const toggleSite = (id: string) =>
    onChange({ ...value, site_ids: (value.site_ids ?? []).includes(id) ? (value.site_ids ?? []).filter((x) => x !== id) : [...(value.site_ids ?? []), id] })

  return (
    <div className="stack-sm">
      <label className="field">
        <span>Role</span>
        <select value={value.role} onChange={(e) => onChange({ ...value, role: e.target.value as Role })}>
          {ROLES.map((r) => (
            <option key={r.value} value={r.value}>
              {roleLabel(r.value)}: {r.help}
            </option>
          ))}
        </select>
      </label>
      {everything ? (
        <p className="muted">Owners and admins always have every module and every site.</p>
      ) : (
        <>
          <div className="field">
            <span>Modules</span>
            <div className="row wrap-sm">
              {modules.map((m) => (
                <label key={m.id} className="check">
                  <input type="checkbox" checked={value.modules.includes(m.id)} onChange={() => toggleModule(m.id)} />
                  {m.name}
                </label>
              ))}
            </div>
          </div>
          <div className="field">
            <span>Sites</span>
            <label className="check">
              <input
                type="checkbox"
                checked={value.site_ids === null}
                onChange={(e) => onChange({ ...value, site_ids: e.target.checked ? null : [] })}
              />
              All sites
            </label>
            {value.site_ids !== null && (
              <div className="row wrap-sm">
                {sites.map((s) => (
                  <label key={s.id} className="check">
                    <input type="checkbox" checked={value.site_ids?.includes(s.id) ?? false} onChange={() => toggleSite(s.id)} />
                    {s.name}
                  </label>
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}
