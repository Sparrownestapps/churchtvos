import { useState } from 'react'

export const MESSAGE_COLOURS = [
  { hex: '#1B2A4A', name: 'Navy' },
  { hex: '#B3261E', name: 'Red' },
  { hex: '#2E7D5B', name: 'Green' },
  { hex: '#8A5A00', name: 'Amber' },
  { hex: '#6B3FA0', name: 'Purple' },
  { hex: '#111111', name: 'Black' },
]
const SECONDS = [10, 30, 60, 120]

/** Text, how long, colour. onSend resolves true on success (the text is then cleared). */
export default function MessageForm({
  onSend,
  onClear,
  disabled,
  pending,
}: {
  onSend: (payload: { text: string; seconds: number; background: string }) => Promise<boolean>
  onClear?: () => void
  disabled: boolean
  pending: boolean
}) {
  const [text, setText] = useState('')
  const [seconds, setSeconds] = useState(30)
  const [background, setBackground] = useState(MESSAGE_COLOURS[0].hex)
  const trimmed = text.trim()

  return (
    <form
      className="stack-sm"
      onSubmit={async (e) => {
        e.preventDefault()
        if (!trimmed || disabled) return
        if (await onSend({ text: trimmed, seconds, background })) setText('')
      }}
    >
      <label className="field">
        <span>Message</span>
        <textarea rows={2} maxLength={200} value={text} onChange={(e) => setText(e.target.value)} placeholder="e.g. Parents: please see the front desk" />
      </label>
      <div className="ctl-count muted">{text.length} / 200</div>
      <div className="ctl-msg-row">
        <label className="field">
          <span>Show for</span>
          <select value={seconds} onChange={(e) => setSeconds(Number(e.target.value))}>
            {SECONDS.map((s) => (
              <option key={s} value={s}>
                {s < 60 ? `${s} seconds` : `${s / 60} minute${s > 60 ? 's' : ''}`}
              </option>
            ))}
          </select>
        </label>
        <div className="field">
          <span>Colour</span>
          <div className="ctl-swatches" role="radiogroup" aria-label="Message colour">
            {MESSAGE_COLOURS.map((c) => (
              <button
                key={c.hex}
                type="button"
                role="radio"
                aria-checked={background === c.hex}
                aria-label={c.name}
                title={c.name}
                className={`ctl-swatch ${background === c.hex ? 'on' : ''}`}
                style={{ background: c.hex }}
                onClick={() => setBackground(c.hex)}
              />
            ))}
          </div>
        </div>
      </div>
      <div className="ctl-preview" style={{ background }} aria-hidden="true">
        {trimmed || 'Your message'}
      </div>
      <div className="row wrap">
        <button className="btn primary" disabled={disabled || !trimmed}>
          {pending ? 'Sending…' : 'Send message'}
        </button>
        {onClear && (
          <button type="button" className="btn" disabled={disabled} onClick={onClear}>
            Clear message
          </button>
        )}
      </div>
    </form>
  )
}
