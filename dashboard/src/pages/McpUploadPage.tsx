import { useEffect, useMemo, useState } from 'react'
import { SUPABASE_URL, supabase } from '../supabase'
import { must, useLoad } from '../lib'
import { uploadMedia } from '../importer/uploadMedia'
import type { Module } from '../types'

/**
 * Opened from a link an AI assistant gave the user (/upload?request=<id>). Chat apps can't hand attached files to the assistant's
 * tools, so the person picks the file(s) here. When the request carries a plan (a signage schedule the assistant prepared), this page
 * is also the confirmation: "Upload & schedule" uploads the files and then runs the schedule through the MCP server as this person.
 */
export const isUploadPath = (pathname: string) => pathname.replace(/\/+$/, '') === '/upload'

type Request = {
  id: string
  organization_id: string
  module: Module
  title: string
  media_id: string | null
  media_ids: string[] | null
  plan: (Record<string, unknown> & { files?: number }) | null
  summary: string | null
  result: string | null
}

/** Calls one MCP tool as the signed-in person (same server and permissions as the assistant). */
async function callTool(name: string, args: Record<string, unknown>): Promise<{ ok: boolean; text: string }> {
  const { data } = await supabase.auth.getSession()
  const res = await fetch(`${SUPABASE_URL}/functions/v1/mcp`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${data.session?.access_token}` },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name, arguments: args } }),
  })
  if (!res.ok) return { ok: false, text: `The server said ${res.status}. Try again in a moment.` }
  const json = await res.json()
  const result = json.result ?? {}
  return { ok: !result.isError, text: result.content?.[0]?.text ?? json.error?.message ?? 'No answer from the server.' }
}

export default function McpUploadPage() {
  const requestId = new URLSearchParams(location.search).get('request') ?? ''
  const { data, error, reload } = useLoad(async () => {
    const req = must(await supabase.from('mcp_upload_requests').select('*').eq('id', requestId).maybeSingle()) as Request | null
    if (!req) return null
    const org = must(await supabase.from('organizations').select('name').eq('id', req.organization_id).maybeSingle()) as { name: string } | null
    return { req, orgName: org?.name ?? '' }
  })
  const [files, setFiles] = useState<File[]>([])
  const [percent, setPercent] = useState<number | null>(null)
  const [step, setStep] = useState('')
  const [failure, setFailure] = useState<string | null>(null)
  const previews = useMemo(() => files.map((f) => (f.type.startsWith('image/') ? URL.createObjectURL(f) : null)), [files])
  useEffect(() => () => previews.forEach((u) => u && URL.revokeObjectURL(u)), [previews])

  const req = data?.req
  const wanted = req?.plan ? Math.max(1, req.plan.files ?? 1) : 1
  const scheduling = !!req?.plan
  const busy = percent !== null

  async function go() {
    if (!req) return
    // Already uploaded but the schedule failed (e.g. a time that has passed): retry the schedule without uploading again.
    const reuse = !files.length && req.media_id ? (req.media_ids?.length ? req.media_ids : [req.media_id]) : null
    if (!files.length && !reuse) return
    setFailure(null)
    try {
      const ids: string[] = reuse ?? []
      for (const [i, file] of (reuse ? [] : files).entries()) {
        setStep(files.length > 1 ? `Uploading ${i + 1} of ${files.length}…` : 'Uploading…')
        setPercent(0)
        const title = files.length > 1 ? `${req.title} (${i + 1})` : req.title
        const media = await uploadMedia({ file, orgId: req.organization_id, module: req.module, folderId: null, siteId: null, title, onProgress: setPercent })
        ids.push(media.id)
      }
      if (!reuse) must(await supabase.from('mcp_upload_requests').update({ media_id: ids[0], media_ids: ids }).eq('id', req.id))
      if (req.plan) {
        setPercent(0)
        setStep('Scheduling…')
        const { files: _files, ...plan } = req.plan
        const res = await callTool('schedule_signage', { ...plan, items: ids.map((media_id) => ({ media_id })), confirm: true })
        must(await supabase.from('mcp_upload_requests').update({ result: res.ok ? res.text : `FAILED: ${res.text}` }).eq('id', req.id))
        if (!res.ok) throw new Error(`Uploaded, but it couldn't be scheduled: ${res.text}`)
      }
      setPercent(null)
      reload()
    } catch (err) {
      setFailure((err as Error).message)
      setPercent(null)
    }
  }

  const finished = req && req.media_id && (!scheduling || (req.result && !req.result.startsWith('FAILED')))

  return (
    <div className="center-screen primary">
      <div className="card narrow stack-sm">
        <span className="wordmark">Church TV OS</span>
        <h2>{scheduling ? 'Upload & schedule' : 'Upload for your assistant'}</h2>
        {error && <p className="error">{error}</p>}
        {data === null && <p className="error">This link isn't valid for your account. Ask the assistant for a new one.</p>}
        {finished ? (
          <>
            <p className="notice">{scheduling ? 'Uploaded and scheduled.' : `Uploaded "${req.title}".`} You can close this page.</p>
            {scheduling && <p className="muted">Screens pick it up within a minute or two. Your assistant can undo it if you change your mind.</p>}
          </>
        ) : req ? (
          <>
            <p>
              {wanted > 1 ? `Choose ${wanted} files` : 'Choose the file'} for <b>{req.title}</b> ({req.module} library, <b>{data?.orgName}</b>).
              {wanted > 1 && ' They show in the order you pick them.'}
            </p>
            {req.summary && (
              <div className="card" style={{ whiteSpace: 'pre-wrap', fontSize: '0.92em' }}>
                {req.summary}
              </div>
            )}
            <input
              type="file"
              accept={req.module === 'signage' ? 'image/*,video/*' : 'image/*,video/*,audio/*'}
              multiple={wanted > 1}
              disabled={busy}
              onChange={(e) => setFiles(Array.from(e.target.files ?? []))}
            />
            {previews.some(Boolean) && (
              <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
                {previews.map((u, i) => (u ? <img key={i} src={u} alt="" style={{ maxHeight: 120, maxWidth: 160, borderRadius: 6 }} /> : null))}
              </div>
            )}
            <button className="btn primary wide" disabled={busy || (!files.length && !req.media_id)} onClick={go}>
              {!files.length && req.media_id ? 'Try scheduling again' : scheduling ? 'Upload & schedule' : 'Upload'}
            </button>
            {busy && <p className="muted">{step} {step.startsWith('Uploading') ? `${percent}%` : ''}</p>}
            {req.result?.startsWith('FAILED') && !busy && <p className="error">{req.result.slice(8)}</p>}
            {failure && <p className="error">{failure}</p>}
            {scheduling && <p className="muted">Pressing the button is your OK for the schedule above. Nothing changes until then.</p>}
          </>
        ) : null}
      </div>
    </div>
  )
}
