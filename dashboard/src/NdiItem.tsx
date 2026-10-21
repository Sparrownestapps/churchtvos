import { NDI_DEFAULTS, cleanNdi, newNdiItem, ndiProblem, validNdiAddress } from './ndiLogic'
import type { NdiConfig, NdiItem } from './types'

export { NDI_DEFAULTS, cleanNdi, newNdiItem, ndiProblem, validNdiAddress }

// EXPERIMENTAL. Shared by the Kids playlist editor (item type 'ndi') and the Slides deck editor (slide kind 'ndi').
// Only offered when the platform admin has switched NDI on for the church (organization.ndi_enabled). See NDI-CONTRACT.md.

export const NDI_LABEL = 'NDI source (experimental)'
export const NDI_NEEDS_NOTE =
  'Experimental. Only works on TVs running the special Church TV OS "NDI" build (version ends in -ndi). The normal store app skips this item.'

/** Placeholder where a live preview would go: the dashboard cannot receive NDI. */
export function NdiPreviewPlaceholder({ source, fit }: { source: string; fit: NdiConfig['fit'] }) {
  return (
    <div className="ndi-preview" role="img" aria-label="NDI preview placeholder">
      <span className="ndi-badge">NDI</span>
      <b>{source.trim() || 'No source chosen'}</b>
      <span className="muted">No preview in the browser. The picture appears on the TV ({fit === 'fill' ? 'cropped to fill the screen' : 'whole picture, with bars if the shapes differ'}).</span>
    </div>
  )
}

type FieldsProps<T extends NdiConfig & { title?: string }> = { value: T; onPatch: (patch: Partial<T>) => void }

/** The form for one NDI source. Used by both editors. */
export function NdiFields<T extends NdiConfig & { title?: string }>({ value, onPatch }: FieldsProps<T>) {
  const problem = ndiProblem(value)
  const patch = onPatch as (p: Partial<NdiConfig> & { title?: string }) => void
  return (
    <div className="stack-sm">
      <div className="note warn">
        <b>Experimental.</b> {NDI_NEEDS_NOTE}
      </div>
      <label className="field">
        <span>Title</span>
        <input value={value.title ?? ''} onChange={(e) => patch({ title: e.target.value })} placeholder="e.g. Main camera" />
      </label>
      <div className="row wrap">
        <label className="field grow">
          <span>NDI source name</span>
          <input value={value.source} onChange={(e) => patch({ source: e.target.value })} placeholder="STUDIO-PC (Camera 1)" spellCheck={false} />
        </label>
        <label className="field grow">
          <span>Address (optional)</span>
          <input
            value={value.address ?? ''}
            onChange={(e) => patch({ address: e.target.value })}
            placeholder="192.168.1.50:5961"
            inputMode="url"
            spellCheck={false}
            aria-invalid={!validNdiAddress(value.address ?? '')}
          />
        </label>
      </div>
      <div className="row wrap">
        <label className="field">
          <span>Picture</span>
          <select value={value.fit} onChange={(e) => patch({ fit: e.target.value as NdiConfig['fit'] })}>
            <option value="fit">Fit (show the whole picture)</option>
            <option value="fill">Fill (crop to fill the screen)</option>
          </select>
        </label>
        <label className="field">
          <span>Show for (seconds)</span>
          <input
            type="number"
            min={1}
            style={{ width: 130 }}
            placeholder="Until next"
            value={value.seconds ?? ''}
            onChange={(e) => patch({ seconds: e.target.value ? Math.max(1, Math.round(Number(e.target.value))) : null })}
          />
        </label>
        <label className="field">
          <span>Wait for the source (seconds)</span>
          <input
            type="number"
            min={3}
            max={120}
            style={{ width: 130 }}
            value={value.max_wait_seconds}
            onChange={(e) => patch({ max_wait_seconds: Math.round(Number(e.target.value)) })}
          />
        </label>
        <label className="check align-end">
          <input type="checkbox" checked={value.audio} onChange={(e) => patch({ audio: e.target.checked })} />
          Play sound
        </label>
      </div>
      <div className="row wrap">
        <label className="field">
          <span>If the source isn't available</span>
          <select value={value.fallback} onChange={(e) => patch({ fallback: e.target.value as NdiConfig['fallback'] })}>
            <option value="skip">Skip it</option>
            <option value="message">Show a message</option>
          </select>
        </label>
        {value.fallback === 'message' && (
          <label className="field grow">
            <span>Message</span>
            <input value={value.fallback_text ?? ''} onChange={(e) => patch({ fallback_text: e.target.value })} maxLength={200} placeholder="Waiting for the camera…" />
          </label>
        )}
      </div>
      {problem && <p className="test-result hint">Needs attention: {problem}</p>}
      <NdiPreviewPlaceholder source={value.source} fit={value.fit} />
      <p className="help">
        The TV and the NDI source must be on the <b>same network</b>. NDI finds sources by broadcasting on the local network, and that
        <b> doesn't cross VLANs or subnets</b>. If the TV is on a different network from the camera or computer, type the source's address too.
        A TV on Wi-Fi should receive <b>NDI|HX</b> (NDI High Efficiency), not full-bandwidth NDI, which needs a wired TV. Sound is off unless you turn it on.
        If the source drops, the TV waits the number of seconds above, then follows "If the source isn't available".
      </p>
    </div>
  )
}

/** Editor for a Kids playlist item. */
export function NdiItemEditor({ item, onChange }: { item: NdiItem; onChange: (next: NdiItem) => void }) {
  return <NdiFields value={item} onPatch={(p) => onChange({ ...item, ...p })} />
}
