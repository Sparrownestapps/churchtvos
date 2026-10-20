import { useLayoutEffect, useMemo, useRef, type CSSProperties } from 'react'
import '../slides.css'
import type { SlideBackground } from '../slidesTypes'
import { fitScale, minScale, planText, type Block, type Frame, type ResolvedTheme, type TextPlan } from './render'

const FONT: Record<ResolvedTheme['font'], string> = {
  lato: 'Lato, "Helvetica Neue", Arial, sans-serif',
  julius: '"Julius Sans One", "Trebuchet MS", Optima, sans-serif',
}

/** Short text description of a frame, for screen readers (the frame itself is an image). */
export function describeFrame(f: Frame): string {
  switch (f.kind) {
    case 'text':
      return [f.title, f.body].filter(Boolean).join('. ') || 'Empty text slide'
    case 'lyric':
      return `${f.label ? f.label + ': ' : ''}${f.text.replace(/\n/g, ' ')}`
    case 'song_title':
      return `Song title: ${f.title}`
    case 'countdown':
      return `Countdown ${f.title}`
    case 'media':
      return f.media === 'video' ? 'Video' : 'Image'
    case 'stream':
      return `Live stream ${f.title}`
    case 'blank':
      return 'Blank screen'
  }
}

function Background({ bg, live }: { bg: SlideBackground; live: boolean }) {
  if (bg.type === 'color') return <div className="sl-bg" style={{ background: bg.color }} />
  if (bg.type === 'gradient')
    return <div className="sl-bg" style={{ background: `linear-gradient(${bg.angle ?? 135}deg, ${bg.color}, ${bg.color2})` }} />
  const fit = bg.fit ?? 'cover'
  return (
    <div className="sl-bg" style={{ background: bg.color || '#000000' }}>
      {bg.type === 'image' ? (
        <img src={bg.url} alt="" draggable={false} style={{ objectFit: fit }} />
      ) : live ? (
        <video src={bg.url} autoPlay muted loop playsInline preload="auto" style={{ objectFit: fit }} />
      ) : (
        <span className="sl-vbadge" aria-hidden="true">▶</span>
      )}
    </div>
  )
}

function BlockView({ b, prev, k, theme }: { b: Block; prev?: Block; k: number; theme: ResolvedTheme }) {
  const style: CSSProperties = {
    fontSize: `calc(${b.size}cqh * var(--k, ${k}))`,
    fontWeight: b.weight,
    marginTop: prev ? `calc(${prev.size * (prev.role === 'title' || prev.role === 'label' ? 0.3 : 0.15)}cqh * var(--k, ${k}))` : 0,
    letterSpacing: b.role === 'label' ? '0.14em' : theme.font === 'julius' && b.role === 'title' ? '0.03em' : undefined,
    textTransform: b.role === 'label' ? 'uppercase' : undefined,
    opacity: b.role === 'label' ? 0.75 : b.role === 'small' ? 0.85 : 1,
    fontVariantNumeric: b.role === 'time' ? 'tabular-nums' : undefined,
  }
  return (
    <div className={`sl-block sl-${b.role}`} style={style}>
      {b.text}
    </div>
  )
}

/** The text box of a frame: sized by the shared estimate, then nudged smaller if the browser's wrapping still overflows. */
function TextBox({ plan, theme, portrait }: { plan: TextPlan; theme: ResolvedTheme; portrait: boolean }) {
  const boxRef = useRef<HTMLDivElement>(null)
  const textRef = useRef<HTMLDivElement>(null)
  const aspect = portrait ? 'port' : 'land'
  const k0 = useMemo(() => fitScale(plan, theme, aspect), [plan, theme, aspect])
  const key = JSON.stringify(plan) + theme.font + theme.margin + aspect

  useLayoutEffect(() => {
    const box = boxRef.current
    const text = textRef.current
    if (!box || !text) return
    const kMin = minScale(plan)
    let k = k0
    text.style.setProperty('--k', String(k))
    for (let i = 0; i < 14 && k > kMin && text.offsetHeight > box.clientHeight + 1; i++) {
      k *= 0.94
      text.style.setProperty('--k', String(k))
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])

  const shadow = theme.shadow ? '0 0.35cqh 1.1cqh rgba(0,0,0,0.75)' : undefined
  const stroke: CSSProperties = theme.outline ? { WebkitTextStroke: '0.3cqh #000', paintOrder: 'stroke fill' } : {}
  return (
    <div
      ref={boxRef}
      className="sl-box"
      style={{
        top: `${plan.top}%`,
        bottom: `${100 - plan.bottom}%`,
        left: `${theme.margin}%`,
        right: `${theme.margin}%`,
      }}
    >
      <div
        ref={textRef}
        className="sl-text"
        style={{ textAlign: plan.align, color: plan.color, fontFamily: FONT[theme.font], textShadow: shadow, ...stroke, ['--k' as string]: k0 }}
      >
        {plan.blocks.map((b, i) => (
          <BlockView key={i} b={b} prev={plan.blocks[i - 1]} k={k0} theme={theme} />
        ))}
      </div>
    </div>
  )
}

export type SlideFrameProps = {
  frame: Frame
  theme: ResolvedTheme
  /** The resolved background (slide, then deck, then theme, then the default colour). */
  background: SlideBackground
  /** Church logo URL, drawn when the theme shows it. */
  logo?: string
  portrait?: boolean
  /** Play video backgrounds (the big preview). Thumbnails leave this off. */
  live?: boolean
  className?: string
}

/** One 16:9 or 9:16 screen, drawn the way the TV draws it (all sizes are percent of the frame height). */
export default function SlideFrame({ frame, theme, background, logo, portrait = false, live = false, className = '' }: SlideFrameProps) {
  const bg: SlideBackground =
    frame.kind === 'blank' ? { type: 'color', color: frame.color } : frame.kind === 'stream' ? { type: 'color', color: '#000000' } : background
  const plan = useMemo(() => planText(frame, theme), [frame, theme])
  const dim = frame.kind === 'blank' || frame.kind === 'stream' ? 0 : Math.min(0.8, Math.max(0, bg.dim ?? 0))

  return (
    <div
      className={`sl-frame ${portrait ? 'port' : 'land'} ${className}`}
      role="img"
      aria-label={`${portrait ? 'Portrait' : 'Landscape'} preview: ${describeFrame(frame)}`}
    >
      <Background bg={bg} live={live} />
      {dim > 0 && <div className="sl-dim" style={{ background: `rgba(0,0,0,${dim})` }} />}

      {frame.kind === 'media' && frame.url && (
        <div className="sl-media">
          {frame.media === 'image' ? (
            <img src={frame.url} alt="" draggable={false} style={{ objectFit: frame.fit }} />
          ) : live ? (
            <video src={`${frame.url}#t=0.5`} preload="metadata" muted playsInline style={{ objectFit: frame.fit }} />
          ) : null}
          {frame.media === 'video' && <span className="sl-vbadge">▶ Video</span>}
        </div>
      )}
      {frame.kind === 'media' && !frame.url && <div className="sl-empty">Choose a file</div>}

      {frame.kind === 'stream' && (
        <div className="sl-stream" style={{ fontFamily: FONT[theme.font] }}>
          <span className="sl-live">● LIVE</span>
          <span className="sl-stream-title">{frame.title || 'Live stream'}</span>
          <span className="sl-stream-note">HLS feed plays here on the TV</span>
        </div>
      )}

      {plan && <TextBox plan={plan} theme={theme} portrait={portrait} />}

      {theme.logo.show && logo && frame.kind !== 'blank' && frame.kind !== 'stream' && (
        <img className={`sl-logo ${theme.logo.position.replace('_', '-')}`} src={logo} alt="" draggable={false} />
      )}
    </div>
  )
}

