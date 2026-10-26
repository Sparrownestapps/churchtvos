import { useEffect, useState } from 'react'
import { supabase } from '../supabase'

/**
 * Where an AI assistant (Claude, ChatGPT, ...) asks to act as you through the Church TV OS MCP server.
 * Supabase sends the browser here with ?authorization_id=...; we show who is asking and let the person allow or deny.
 */
export const isConsentPath = (pathname: string) => pathname.replace(/\/+$/, '') === '/oauth/consent'

type Details = { authorization_id: string; client: { name: string; uri: string }; user: { email: string }; scope: string }

export default function OAuthConsentPage() {
  const authorizationId = new URLSearchParams(location.search).get('authorization_id')
  const [details, setDetails] = useState<Details | null>(null)
  const [error, setError] = useState<string | null>(authorizationId ? null : 'This page is opened by an AI assistant asking for access. There is nothing to approve here.')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!authorizationId) return
    supabase.auth.oauth.getAuthorizationDetails(authorizationId).then(({ data, error }) => {
      if (error || !data) setError(error?.message ?? 'That request is no longer valid. Go back to the assistant and try again.')
      else if ('redirect_url' in data) location.href = data.redirect_url // already approved earlier
      else setDetails(data as Details)
    })
  }, [authorizationId])

  async function decide(approve: boolean) {
    if (!authorizationId) return
    setBusy(true)
    const { data, error } = approve
      ? await supabase.auth.oauth.approveAuthorization(authorizationId)
      : await supabase.auth.oauth.denyAuthorization(authorizationId)
    if (error || !data) {
      setError(error?.message ?? 'Something went wrong. Go back to the assistant and try again.')
      setBusy(false)
    } else location.href = data.redirect_url
  }

  return (
    <div className="center-screen primary">
      <div className="card narrow">
        <span className="wordmark">Church TV OS</span>
        <h2>Let {details?.client.name ?? 'this assistant'} use your account?</h2>
        {error && <p className="error">{error}</p>}
        {details && (
          <>
            <p>
              <strong>{details.client.name}</strong> wants to act as <strong>{details.user.email}</strong>.
            </p>
            <p className="muted">
              It will be able to see your churches, rooms and screens, add graphics to the media library, and schedule or cancel signage graphics.
              It can only do what your own account is allowed to do, and it is asked to check with you before it changes a schedule.
              You can stop it any time by removing the connection in the assistant.
            </p>
            <button className="btn primary wide" disabled={busy} onClick={() => decide(true)}>
              Allow
            </button>
            <button type="button" className="link" disabled={busy} onClick={() => decide(false)}>
              Cancel
            </button>
          </>
        )}
      </div>
    </div>
  )
}
