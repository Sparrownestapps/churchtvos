// Picks a font size so text fills a box without spilling, like Compose's TextAutoSize on Android.
// React Native on the TV can't measure text before drawing it, so this estimates line breaks from an average glyph width.
// Errs on the small side: a slightly small slide is fine, a cut-off lyric is not.

/** Average glyph width as a fraction of the font size, per weight (Lato, measured on mixed-case English). */
const WIDTH = { regular: 0.5, bold: 0.53, black: 0.56, julius: 0.66 } as const
export type FitWeight = keyof typeof WIDTH

/** Lines [text] wraps to at [size] in a box [width] wide. */
export function lineCount(text: string, size: number, width: number, weight: FitWeight): number {
  const perLine = Math.max(1, Math.floor(width / (size * WIDTH[weight])))
  let lines = 0
  for (const para of text.split('\n')) {
    let used = 0
    let n = 1
    for (const word of para.split(/\s+/).filter(Boolean)) {
      const len = word.length
      if (len > perLine) {
        // a word longer than a line breaks across lines
        if (used > 0) n++
        n += Math.ceil(len / perLine) - 1
        used = len % perLine || perLine
      } else if (used === 0) used = len
      else if (used + 1 + len <= perLine) used += 1 + len
      else { n++; used = len }
    }
    lines += n
  }
  return lines
}

export interface FitOptions {
  width: number
  height: number
  min: number
  max: number
  maxLines: number
  weight: FitWeight
  lineHeight?: number
  step?: number
}

/** The largest size from [max] down to [min] (in [step]s) whose wrapped text fits the box. */
export function fitFontSize(text: string, o: FitOptions): number {
  const lh = o.lineHeight ?? 1.15
  const step = o.step ?? 2
  for (let size = o.max; size > o.min; size -= step) {
    const lines = lineCount(text, size, o.width, o.weight)
    if (lines <= o.maxLines && lines * size * lh <= o.height) return size
  }
  return o.min
}
