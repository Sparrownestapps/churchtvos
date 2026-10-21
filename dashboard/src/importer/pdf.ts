import type { PDFDocumentProxy } from 'pdfjs-dist'

// PDF page renderer. pdf.js (pinned in package.json) is a lazy chunk: it only downloads when someone opens the PDF importer.
// Pages are drawn on a canvas in the browser and saved as JPEG. Contract: PPTX-IMPORT-CONTRACT.md.

/** Long edge of a rendered page in pixels: 16:9 pages come out 1920 x 1080, portrait pages 1080 x 1920. */
export const RENDER_LONG_EDGE = 1920
export const JPEG_QUALITY = 0.9

export type PdfInfo = { numPages: number; doc: PDFDocumentProxy }

async function lib() {
  const pdfjs = await import('pdfjs-dist')
  if (!pdfjs.GlobalWorkerOptions.workerSrc) {
    const worker = await import('pdfjs-dist/build/pdf.worker.min.mjs?url')
    pdfjs.GlobalWorkerOptions.workerSrc = worker.default
  }
  return pdfjs
}

/** Opens a PDF. Throws a readable message for a damaged or password-protected file. */
export async function openPdf(data: ArrayBuffer): Promise<PdfInfo> {
  const pdfjs = await lib()
  try {
    const doc = await pdfjs.getDocument({
      data: new Uint8Array(data),
      cMapUrl: '/pdfjs/cmaps/',
      cMapPacked: true,
      standardFontDataUrl: '/pdfjs/standard_fonts/',
      iccUrl: '/pdfjs/iccs/',
    }).promise
    return { numPages: doc.numPages, doc }
  } catch (e) {
    const name = (e as { name?: string }).name
    if (name === 'PasswordException') throw new Error('This PDF is password protected. Remove the password and try again.')
    throw new Error("Couldn't read this PDF. It may be damaged.")
  }
}

/** Pixel size for a page so its long edge is `longEdge` (never below 16 px). */
export function pageSize(width: number, height: number, longEdge: number): { w: number; h: number } {
  const k = longEdge / Math.max(width, height)
  return { w: Math.max(16, Math.round(width * k)), h: Math.max(16, Math.round(height * k)) }
}

async function drawPage(info: PdfInfo, n: number, longEdge: number): Promise<HTMLCanvasElement> {
  const page = await info.doc.getPage(n)
  const base = page.getViewport({ scale: 1 })
  const { w, h } = pageSize(base.width, base.height, longEdge)
  const viewport = page.getViewport({ scale: w / base.width })
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('This browser cannot draw the page.')
  ctx.fillStyle = '#ffffff' // PDF pages are transparent; JPEG has no transparency
  ctx.fillRect(0, 0, w, h)
  await page.render({ canvas, canvasContext: ctx, viewport }).promise
  page.cleanup()
  return canvas
}

function toBlob(canvas: HTMLCanvasElement, type: string, quality?: number): Promise<Blob> {
  return new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Could not save the page as a picture.'))), type, quality))
}

/** A small preview (a data URL is avoided: an object URL the caller revokes). */
export async function renderThumb(info: PdfInfo, n: number): Promise<string> {
  const canvas = await drawPage(info, n, 360)
  const blob = await toBlob(canvas, 'image/jpeg', 0.7)
  canvas.width = canvas.height = 0
  return URL.createObjectURL(blob)
}

/** The full-size page as a JPEG file named `name`. */
export async function renderPageFile(info: PdfInfo, n: number, name: string): Promise<File> {
  const canvas = await drawPage(info, n, RENDER_LONG_EDGE)
  const blob = await toBlob(canvas, 'image/jpeg', JPEG_QUALITY)
  canvas.width = canvas.height = 0
  return new File([blob], name, { type: 'image/jpeg' })
}

/**
 * A text slide drawn as a picture (used for Kids playlists, which have no text slide): title and body on a solid colour,
 * white text, centred. Size follows the presentation's shape (long edge 1920).
 */
export async function renderTextSlideFile(opts: { title: string; body: string; background: string; aspect: number; name: string }): Promise<File> {
  const { title, body, background, aspect, name } = opts
  const w = aspect >= 1 ? RENDER_LONG_EDGE : Math.round(RENDER_LONG_EDGE * aspect)
  const h = aspect >= 1 ? Math.round(RENDER_LONG_EDGE / aspect) : RENDER_LONG_EDGE
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')!
  ctx.fillStyle = background
  ctx.fillRect(0, 0, w, h)
  const lines = layoutText(ctx, title, body, w, h)
  ctx.fillStyle = '#ffffff'
  ctx.textAlign = 'center'
  ctx.textBaseline = 'top'
  ctx.shadowColor = 'rgba(0,0,0,0.45)'
  ctx.shadowBlur = h * 0.01
  let y = (h - lines.height) / 2
  for (const l of lines.items) {
    ctx.font = `${l.weight} ${l.size}px Lato, "Helvetica Neue", Arial, sans-serif`
    ctx.fillText(l.text, w / 2, y)
    y += l.size * 1.2
    if (l.gap) y += l.gap
  }
  const blob = await toBlob(canvas, 'image/jpeg', JPEG_QUALITY)
  return new File([blob], name, { type: 'image/jpeg' })
}

type Line = { text: string; size: number; weight: number; gap?: number }

/** Wraps title and body, shrinking the text in 5% steps until it fits inside the margins. */
function layoutText(ctx: CanvasRenderingContext2D, title: string, body: string, w: number, h: number) {
  const maxW = w * 0.84
  const maxH = h * 0.84
  const wrap = (text: string, size: number, weight: number): string[] => {
    ctx.font = `${weight} ${size}px Lato, "Helvetica Neue", Arial, sans-serif`
    const out: string[] = []
    for (const para of text.split('\n')) {
      let line = ''
      for (const word of para.split(/\s+/).filter(Boolean)) {
        const next = line ? `${line} ${word}` : word
        if (ctx.measureText(next).width <= maxW || !line) line = next
        else (out.push(line), (line = word))
      }
      out.push(line)
    }
    return out
  }
  let k = 1
  for (;;) {
    const items: Line[] = []
    const ts = h * 0.09 * k
    const bs = h * 0.055 * k
    if (title.trim()) for (const t of wrap(title.trim(), ts, 800)) items.push({ text: t, size: ts, weight: 800 })
    if (title.trim() && body.trim()) items[items.length - 1].gap = ts * 0.4
    if (body.trim()) for (const t of wrap(body.trim(), bs, 500)) items.push({ text: t, size: bs, weight: 500 })
    const height = items.reduce((s, l) => s + l.size * 1.2 + (l.gap ?? 0), 0)
    if (height <= maxH || k < 0.35) return { items, height }
    k *= 0.95
  }
}
