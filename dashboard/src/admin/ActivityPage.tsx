import { useState } from 'react'
import './../admin.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import { must, useLoad } from '../lib'
import AuditList from './AuditList'
import { AUDIT_ACTIONS, loadAdminOrgs, loadAllModules, type AuditEntry } from './logic'

const PAGE = 50

export default function ActivityPage() {
  const { isPlatformAdmin } = useApp()
  if (!isPlatformAdmin) return <p className="muted">This page is for the platform administrator.</p>
  return <Activity />
}

function Activity() {
  const [church, setChurch] = useState('')
  const [action, setAction] = useState('')
  const [page, setPage] = useState(0)

  const { data: meta, error: metaError } = useLoad(async () => {
    const [orgs, modules] = await Promise.all([loadAdminOrgs(), loadAllModules()])
    return { orgs, modules }
  })
  const { data: rows, error } = useLoad(async () => {
    let q = supabase.from('admin_audit_log').select('*').order('at', { ascending: false }).order('id', { ascending: false })
    if (church) q = q.eq('organization_id', church)
    if (action) q = q.eq('action', action)
    return must(await q.range(page * PAGE, page * PAGE + PAGE)) as AuditEntry[] // one extra row tells us there is a next page
  }, [church, action, page])

  const names = new Map((meta?.orgs ?? []).map((o) => [o.id, o.name]))
  const moduleName = (id: string) => meta?.modules.find((m) => m.id === id)?.name ?? id.charAt(0).toUpperCase() + id.slice(1)
  const shown = (rows ?? []).slice(0, PAGE)

  return (
    <div className="stack">
      <div className="card row wrap">
        <label className="field">
          <span>Church</span>
          <select value={church} onChange={(e) => (setChurch(e.target.value), setPage(0))}>
            <option value="">All churches</option>
            {(meta?.orgs ?? []).map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          <span>Action</span>
          <select value={action} onChange={(e) => (setAction(e.target.value), setPage(0))}>
            <option value="">All actions</option>
            {AUDIT_ACTIONS.map((a) => (
              <option key={a} value={a}>
                {a.replace('_', ' ')}
              </option>
            ))}
          </select>
        </label>
      </div>
      {(error || metaError) && <p className="error">{error ?? metaError}</p>}
      <div className="card stack-sm">
        {!rows ? <p className="muted">Loading…</p> : <AuditList entries={shown} moduleName={moduleName} names={names} />}
        <div className="row">
          <button className="btn" disabled={page === 0} onClick={() => setPage(page - 1)}>
            Newer
          </button>
          <button className="btn" disabled={!rows || rows.length <= PAGE} onClick={() => setPage(page + 1)}>
            Older
          </button>
          <span className="muted">Page {page + 1}</span>
        </div>
      </div>
    </div>
  )
}
