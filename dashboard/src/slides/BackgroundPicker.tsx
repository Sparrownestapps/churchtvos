import { useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import type { SlideBackground } from '../slidesTypes'
import type { Media } from '../types'
import type { SlidesLibrary } from '../slidesPages.types'
import { isHex } from '../lib'
import { DEFAULT_NAVY } from './render'
import MediaPickerDialog, { VideoPoster, oversize } from './MediaPickerDialog'

type Mode = 'inherit' | SlideBackground['type']

const PRESETS = ['#1f3a5f', '#000000', '#ffffff', '#111827', '#f3efe6', '#b3261e', '#d9480f', '#2e7d5b', '#1d4ed8', '#7c3aed']

/** Colour swatches (church colours first) plus the native colour input. */
export function ColorField({ value, onChange, label, disabled }: { value: string; onChange: (hex: string) => void; label: string; disabled?: boolean }) {
  const { org } = useApp()
  const b = org.branding
  const swatches = [
    ...(isHex(b.primary_color) ? [b.primary_color.toLowerCase()] : []),
    ...(isHex(b.accent_color) ? [b.accent_color.toLowerCase()] : []),
    ...PRESETS,
  ].filter((v, i, a) => a.indexOf(v) === i)
  const hex = isHex(value) ? value : '#000000'
  return (
    <div className="field">
      <span>{label}</span>
      <div className="swatches">
        <input type="color" className="color" aria-label={label} value={hex} disabled={disabled} onChange={(e) => onChange(e.target.value)} />
        {swatches.map((s) => (
          <button
            key={s}
            type="button"
            className={`swatch ${s === hex.toLowerCase() ? 'on' : ''}`}
            style={{ background: s }}
            aria-label={`${label} ${s}`}
            aria-pressed={s === hex.toLowerCase()}
            disabled={disabled}
            onClick={() => onChange(s)}
          />
        ))}
      </div>
    </div>
  )
}

/**
 * Background chooser shared by slides, decks and themes: colour, gradient, image or video from the Slides library,
 * fit, and the dim overlay. `null` means "no override": the level above (deck/theme/default) shows through.
 */
export default function BackgroundPicker({
  value,
  onChange,
  lib,
  inheritLabel,
  readOnly,
}: {
  value: SlideBackground | null | undefined
  onChange: (next: SlideBackground | null) => void
  lib: SlidesLibrary | undefined
  /** Text of the "no override" choice, e.g. "Use theme background". */
  inheritLabel: string
  readOnly?: boolean
}) {
  const [picking, setPicking] = useState(false)
  const mode: Mode = value ? value.type : 'inherit'
  const dim = value?.dim ?? 0

  function switchTo(next: Mode) {
    if (next === mode) return
    if (next === 'inherit') return onChange(null)
    const d = value?.dim || undefined
    const prev = value && 'color' in value && value.color ? value.color : undefined
    if (next === 'color') return onChange({ type: 'color', color: prev ?? DEFAULT_NAVY, dim: d })
    if (next === 'gradient')
      return onChange({ type: 'gradient', color: prev ?? DEFAULT_NAVY, color2: value?.type === 'gradient' ? value.color2 : '#000000', angle: 135, dim: d })
    onChange({ type: next, media_id: '', url: '', fit: 'cover', color: '#000000', dim: d })
  }

  const patch = (p: Partial<SlideBackground>) => value && onChange({ ...value, ...p } as SlideBackground)
  const media: Media | undefined = value && (value.type === 'image' || value.type === 'video') ? lib?.media.find((m) => m.id === value.media_id) : undefined

  function pickFile(m: Media) {
    if (!value || (value.type !== 'image' && value.type !== 'video')) return
    onChange({ ...value, media_id: m.id, url: m.url })
    setPicking(false)
  }

  const modes: { id: Mode; label: string }[] = [
    { id: 'inherit', label: inheritLabel },
    { id: 'color', label: 'Colour' },
    { id: 'gradient', label: 'Gradient' },
    { id: 'image', label: 'Image' },
    { id: 'video', label: 'Video' },
  ]

  return (
    <div className="stack-sm sl-bgpicker">
      <div className="sl-seg" role="group" aria-label="Background type">
        {modes.map((m) => (
          <button key={m.id} type="button" className={mode === m.id ? 'on' : ''} aria-pressed={mode === m.id} disabled={readOnly} onClick={() => switchTo(m.id)}>
            {m.label}
          </button>
        ))}
      </div>

      {value?.type === 'color' && <ColorField label="Colour" value={value.color} disabled={readOnly} onChange={(color) => patch({ color })} />}

      {value?.type === 'gradient' && (
        <div className="row wrap">
          <ColorField label="From" value={value.color} disabled={readOnly} onChange={(color) => patch({ color })} />
          <ColorField label="To" value={value.color2} disabled={readOnly} onChange={(color2) => patch({ color2 })} />
          <label className="field">
            <span>Angle: {value.angle ?? 135}°</span>
            <input type="range" min={0} max={360} step={5} value={value.angle ?? 135} disabled={readOnly} onChange={(e) => patch({ angle: Number(e.target.value) })} />
          </label>
        </div>
      )}

      {(value?.type === 'image' || value?.type === 'video') && (
        <div className="stack-sm">
          <div className="row wrap">
            <div className="sl-chosen">
              {value.url ? (
                value.type === 'image' ? (
                  <img src={value.url} alt="" />
                ) : (
                  <VideoPoster url={value.url} />
                )
              ) : (
                <div className="sl-none">None</div>
              )}
            </div>
            <div className="stack-sm">
              <b>{value.url ? media?.title ?? '(file from the library)' : `No ${value.type} chosen yet`}</b>
              {!readOnly && (
                <button type="button" className="btn" onClick={() => setPicking(true)} disabled={!lib}>
                  {!lib ? 'Loading library…' : value.url ? `Change ${value.type}…` : `Choose ${value.type} from the library…`}
                </button>
              )}
            </div>
          </div>
          <div className="row wrap">
            <label className="field">
              <span>Fit</span>
              <select value={value.fit ?? 'cover'} disabled={readOnly} onChange={(e) => patch({ fit: e.target.value as 'cover' | 'contain' })}>
                <option value="cover">Fill the screen (crops the edges)</option>
                <option value="contain">Show it all (fill colour around it)</option>
              </select>
            </label>
            {value.fit === 'contain' && <ColorField label="Fill colour" value={value.color ?? '#000000'} disabled={readOnly} onChange={(color) => patch({ color })} />}
          </div>
          {media && oversize(media) && (
            <p className="note warn">This video is over 200 MB. Fire TV sticks have little storage, so a smaller file (1080p, 10 to 60 seconds) is safer.</p>
          )}
          {value.type === 'video' && (
            <p className="help">
              Video backgrounds play muted and loop. Use 1080p H.264, with loops of 10 to 60 seconds, and keep the file modest: Fire TV sticks have little storage.
              Portrait screens crop a landscape video unless the fit is set to show it all.
            </p>
          )}
          {value.type === 'image' && <p className="help">Use 1920 x 1080 for landscape screens. Portrait screens crop a landscape picture unless the fit shows it all.</p>}
        </div>
      )}

      {value && (
        <label className="field">
          <span>Dim: {Math.round(dim * 100)}%</span>
          <input
            type="range"
            min={0}
            max={80}
            step={5}
            value={Math.round(dim * 100)}
            disabled={readOnly}
            onChange={(e) => patch({ dim: Number(e.target.value) / 100 || undefined })}
            aria-describedby="sl-dim-help"
          />
          <span id="sl-dim-help" className="help sl-nocaps">A black layer over the background so the words stay readable.</span>
        </label>
      )}

      {picking && lib && value && (value.type === 'image' || value.type === 'video') && (
        <MediaPickerDialog lib={lib} kinds={[value.type]} value={value.media_id} title={`Choose a ${value.type}`} onPick={pickFile} onClose={() => setPicking(false)} />
      )}
    </div>
  )
}
