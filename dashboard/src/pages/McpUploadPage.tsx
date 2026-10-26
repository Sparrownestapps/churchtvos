import { useState, type ChangeEvent } from 'react'
import { supabase } from '../supabase'
import { must, useLoad } from '../lib'
import { uploadMedia } from '../importer/uploadMedia'
import type { Module } from '../types'

/**
 * Opened from a link an AI assistant gave the user (/upload?request=<id>) for files too big to send in a chat, such as videos.
 * Uploads into the requested church and library, then records the new media id on the request so the assistant can find it.
 */
export const isUploadPath = (pathname: string) => pathname.replace(/\/+$/, '') === '/upload'

type Request = { id: string; organization_id: string; module: Module; title: string; media_id: string | null }

export default function McpUploadPage() {
  const requestId = new URLSearchParams(location.search).get('request') ?? ''
  const { data, error } = useLoad(async () => {
    const req = must(await supabase.from('mcp_upload_requests').select('*').eq('id', requestId).maybeSingle()) as Request | null
    if (!req) return null
    const org = must(await supabase.from('organizations').select('name').eq('id', req.organization_id).maybeSingle()) as { name: string } | null
    return { req, orgName: org?.name ?? '' }
  })
  const [percent, setPercent] = useState<number | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [done, setDone] = useState(false)

  async function pick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file || !data) return
    setFailure(null)
    setPercent(0)
    try {
      const media = await uploadMedia({ file, orgId: data.req.organization_id, module: data.req.module, folderId: null, siteId: null, title: data.req.title, onProgress: setPercent })
      must(await supabase.from('mcp_upload_requests').update({ media_id: media.id }).eq('id', data.req.id))
      setDone(true)
    } catch (err) {
      setFailure((err as Error).message)
      setPercent(null)
    }
  }

  const req = data?.req
  return (
    <div className="center-screen primary">
      <div className="card narrow stack-sm">
        <span className="wordmark">Church TV OS</span>
        <h2>Upload for your assistant</h2>
        {error && <p className="error">{error}</p>}
        {data === null && <p className="error">This upload link isn't valid for your account. Ask the assistant for a new one.</p>}
        {req && (done || req.media_id) ? (
          <p className="notice">
            Uploaded "{req.title}". Go back to the assistant and tell it you're done. You can close this page.
          </p>
        ) : req ? (
          <>
            <p>
              Choose the file for <b>{req.title}</b>. It goes into the {req.module} library of <b>{data?.orgName}</b>.
            </p>
            <input type="file" accept="video/*,image/*,audio/*" onChange={pick} disabled={percent !== null} />
            {percent !== null && <p className="muted">Uploading… {percent}%</p>}
            {failure && <p className="error">{failure}</p>}
          </>
        ) : null}
      </div>
    </div>
  )
}
