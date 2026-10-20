import { describeAudit, type AuditEntry } from './logic'
import { fmtWhen } from '../lib'

/** Audit entries as a simple list. `names` resolves church ids (omit to hide the church column). */
export default function AuditList({
  entries,
  moduleName,
  names,
}: {
  entries: AuditEntry[]
  moduleName: (id: string) => string
  names?: Map<string, string>
}) {
  if (entries.length === 0) return <p className="muted">Nothing recorded yet.</p>
  return (
    <div className="adm-audit">
      {entries.map((a) => (
        <div key={a.id} className="adm-audit-row">
          <div className="adm-audit-main">
            {names && <b>{(a.organization_id && names.get(a.organization_id)) || (a.organization_id ? 'Deleted church' : '—')}</b>}
            <span>{describeAudit(a, moduleName)}</span>
          </div>
          <div className="muted">
            {a.actor_email ?? 'system'} · {fmtWhen(a.at)}
          </div>
        </div>
      ))}
    </div>
  )
}
