// The device functions on the server (POST /rest/v1/rpc/<name>, publishable key only). Same calls as tv-app Api.kt.
import { SUPABASE_KEY, SUPABASE_URL } from './config'
import type { PlaybackStatus } from './remote'

export class ServerError extends Error {}

export class Api {
  constructor(private baseUrl: string = SUPABASE_URL, private key: string = SUPABASE_KEY) {}

  private async rpc(name: string, body: Record<string, unknown>): Promise<string> {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), 30_000)
    try {
      const res = await fetch(`${this.baseUrl}/rest/v1/rpc/${name}`, {
        method: 'POST',
        headers: { apikey: this.key, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      })
      const text = await res.text()
      if (!res.ok) throw new ServerError(`Server error ${res.status}: ${text}`)
      return text
    } finally {
      clearTimeout(timer)
    }
  }

  registerDevice(id: string, secret: string, model: string, appVersion: string) {
    return this.rpc('register_device', { p_device_id: id, p_secret: secret, p_model: model, p_app_version: appVersion })
  }

  /** Returns the raw JSON so it can be saved for offline use. */
  deviceState(id: string, secret: string) {
    return this.rpc('device_state', { p_device_id: id, p_secret: secret })
  }

  /** Commands waiting for this TV (the server drops stale ones). */
  pollCommands(id: string, secret: string) {
    return this.rpc('device_poll_commands', { p_device_id: id, p_secret: secret })
  }

  reportStatus(id: string, secret: string, s: PlaybackStatus, includeOutline: boolean) {
    const body: Record<string, unknown> = {
      p_device_id: id, p_secret: secret, p_module: s.module, p_state: s.state, p_title: s.title,
      p_item_label: s.label, p_slide_index: s.index, p_slide_count: s.count,
    }
    if (includeOutline) body.p_outline = s.outline
    if (s.refKind) body.p_ref_kind = s.refKind
    if (s.refId) body.p_ref_id = s.refId
    return this.rpc('device_report_status', body)
  }
}
