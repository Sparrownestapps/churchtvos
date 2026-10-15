import { useApp } from './context'
import { isHex } from './lib'
import { luminance, signTextColor } from './theme'
import type { SignSlide } from './types'
import { NEEDS_APP_NOTE } from './StreamItem'

const PRESETS = ['#ffffff', '#f3efe6', '#111827', '#000000', '#b3261e', '#d9480f', '#f59e0b', '#2e7d5b', '#1d4ed8', '#7c3aed']

export const newSignItem = (background: string): SignSlide => ({
  type: 'sign',
  title: '',
  subtext: '',
  background: isHex(background) ? background.toLowerCase() : '#1f3a5f',
  seconds: 10,
  align: 'center',
  logo: false,
})

/** Title size (percent of the mock-up's width) so longer text shrinks to fit. */
function titleSize(len: number, portrait: boolean) {
  const base = len <= 12 ? 12 : len <= 24 ? 9 : len <= 48 ? 6.5 : 4.8
  return portrait ? base * 0.78 : base
}

function Mock({ item, logo, portrait }: { item: SignSlide; logo?: string; portrait: boolean }) {
  const color = signTextColor(item.background)
  const title = item.title.trim() || 'Your title here'
  return (
    <div
      className={`sign-mock ${portrait ? 'port' : 'land'}`}
      style={{ background: item.background, color, textAlign: item.align }}
      aria-label={portrait ? 'Portrait preview' : 'Landscape preview'}
    >
      {item.logo && logo && <img className="sign-logo" src={logo} alt="" />}
      <div className="sign-title" style={{ fontSize: `${titleSize(title.length, portrait)}cqw`, opacity: item.title.trim() ? 1 : 0.5 }}>
        {title}
      </div>
      {item.subtext.trim() && (
        <div className="sign-sub" style={{ fontSize: `${titleSize(title.length, portrait) * 0.45}cqw` }}>
          {item.subtext}
        </div>
      )}
    </div>
  )
}

/** Editor + live preview for a text sign slide (Signage). */
export function SignItemEditor({ item, onChange }: { item: SignSlide; onChange: (next: SignSlide) => void }) {
  const { org } = useApp()
  const b = org.branding
  const patch = (p: Partial<SignSlide>) => onChange({ ...item, ...p })
  const swatches = [
    ...(isHex(b.primary_color) ? [{ label: 'Church primary', hex: b.primary_color.toLowerCase() }] : []),
    ...(isHex(b.accent_color) ? [{ label: 'Church accent', hex: b.accent_color.toLowerCase() }] : []),
    ...PRESETS.map((hex) => ({ label: hex, hex })),
  ]
  // Dark logo on dark backgrounds, same threshold as the text colour.
  const logo = luminance(item.background) > 0.5 ? b.logo_url || b.logo_dark_url : b.logo_dark_url || b.logo_url

  return (
    <div className="stack-sm">
      <div className="note">{NEEDS_APP_NOTE}</div>
      <label className="field">
        <span>Title</span>
        <input value={item.title} onChange={(e) => patch({ title: e.target.value })} placeholder="e.g. Welcome! Services at 9 and 11" />
      </label>
      <label className="field">
        <span>Smaller text (optional)</span>
        <input value={item.subtext} onChange={(e) => patch({ subtext: e.target.value })} placeholder="e.g. Coffee is in the lobby" />
      </label>
      <div className="field">
        <span>Background</span>
        <div className="swatches">
          <input
            type="color"
            className="color"
            value={isHex(item.background) ? item.background : '#1f3a5f'}
            onChange={(e) => patch({ background: e.target.value })}
            aria-label="Background colour"
          />
          {swatches.map((s, k) => (
            <button
              type="button"
              key={`${s.hex}-${k}`}
              className={`swatch ${item.background.toLowerCase() === s.hex ? 'on' : ''}`}
              style={{ background: s.hex }}
              title={s.label}
              aria-label={s.label}
              onClick={() => patch({ background: s.hex })}
            />
          ))}
        </div>
      </div>
      <div className="row wrap">
        <div className="field">
          <span>Alignment</span>
          <div className="segmented">
            {(['center', 'left'] as const).map((a) => (
              <button type="button" key={a} className={item.align === a ? 'on' : ''} onClick={() => patch({ align: a })}>
                {a === 'center' ? 'Centre' : 'Left'}
              </button>
            ))}
          </div>
        </div>
        <label className="field">
          <span>Show for (seconds)</span>
          <input
            type="number"
            min={1}
            style={{ width: 120 }}
            value={item.seconds}
            onChange={(e) => patch({ seconds: Math.max(1, Number(e.target.value) || 10) })}
          />
        </label>
        <label className="check align-end">
          <input type="checkbox" checked={item.logo} onChange={(e) => patch({ logo: e.target.checked })} />
          Show church logo
        </label>
      </div>
      {item.logo && !logo && <p className="note warn">No logo has been added yet. Add one under Settings.</p>}
      <div className="sign-previews">
        <Mock item={item} logo={logo} portrait={false} />
        <Mock item={item} logo={logo} portrait />
      </div>
      <p className="help">Text turns white or black automatically so it stays readable on the colour you choose. Long titles shrink to fit.</p>
    </div>
  )
}
