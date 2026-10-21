import type JSZip from 'jszip'

// PowerPoint (.pptx) reader. Runs in the browser (jszip is loaded lazily by loadPptx) and in the vitest tests.
// What it extracts, and the rules, are written down in PPTX-IMPORT-CONTRACT.md at the repository root. Keep the two in step.

export type PptxPicture = {
  /** Path inside the zip, e.g. ppt/media/image3.png */
  path: string
  ext: string
  /** png, jpg, jpeg, gif, webp: shown on the TV. Others (emf, wmf, tiff, svg...) cannot be imported. */
  supported: boolean
  /** Drawn size in EMU (width x height), used to pick the main picture of a picture-only slide. 0 when unknown. */
  area: number
}

export type PptxMedia = {
  /** Path inside the zip (empty for an online video link) */
  path: string
  kind: 'video' | 'audio'
  ext: string
  /** Bytes, or null when not known without reading the file */
  size: number | null
  /** mp4, m4v, mov, webm (video) / mp3, m4a, aac, wav, ogg (audio) */
  supported: boolean
  /** A link to an online video (YouTube etc.): cannot be embedded, only listed. */
  external?: string
}

export type PptxSlide = {
  /** 1-based position in the presentation's slide order (the order PowerPoint shows). */
  number: number
  /** Path inside the zip, e.g. ppt/slides/slide7.xml */
  path: string
  hidden: boolean
  title: string
  body: string
  /** Speaker notes ('' when none) */
  notes: string
  pictures: PptxPicture[]
  /** Picture used as the slide background, when it has one */
  bgPicture: PptxPicture | null
  media: PptxMedia[]
  /** 'text' = has words; 'picture' = no words but a picture/background; 'empty' = neither */
  kind: 'text' | 'picture' | 'empty'
}

export type Pptx = {
  zip: JSZip
  slides: PptxSlide[]
  /** Slide width / height (16/9 = 1.777...) */
  aspect: number
}

const R_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

const PICTURE_EXT = ['png', 'jpg', 'jpeg', 'gif', 'webp']
const VIDEO_EXT = ['mp4', 'm4v', 'mov', 'webm']
const AUDIO_EXT = ['mp3', 'm4a', 'aac', 'wav', 'ogg']

export const MIME: Record<string, string> = {
  png: 'image/png',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  gif: 'image/gif',
  webp: 'image/webp',
  mp4: 'video/mp4',
  m4v: 'video/mp4',
  mov: 'video/quicktime',
  webm: 'video/webm',
  mp3: 'audio/mpeg',
  m4a: 'audio/mp4',
  aac: 'audio/aac',
  wav: 'audio/wav',
  ogg: 'audio/ogg',
}

// ───────── XML helpers ─────────

function parseXml(xml: string): Document {
  return new DOMParser().parseFromString(xml, 'application/xml')
}
const kids = (el: Element, name: string) => Array.from(el.children).filter((c) => c.localName === name)
const first = (el: Element | Document, name: string) => el.getElementsByTagNameNS('*', name)[0] as Element | undefined
const all = (el: Element | Document, name: string) => Array.from(el.getElementsByTagNameNS('*', name))
const rAttr = (el: Element, name: string) => el.getAttributeNS(R_NS, name) ?? el.getAttribute(`r:${name}`) ?? ''
const extOf = (path: string) => (path.split('.').pop() ?? '').toLowerCase()

type Rel = { type: string; target: string; external: boolean }

/** Relationship id -> where it points (Target resolved against the folder of the file the rels belong to). */
export function parseRels(xml: string, baseDir: string): Map<string, Rel> {
  const out = new Map<string, Rel>()
  for (const r of all(parseXml(xml), 'Relationship')) {
    const id = r.getAttribute('Id')
    const target = r.getAttribute('Target') ?? ''
    const external = r.getAttribute('TargetMode') === 'External'
    if (id) out.set(id, { type: r.getAttribute('Type') ?? '', target: external ? target : resolvePath(baseDir, target), external })
  }
  return out
}

/** 'ppt/slides' + '../media/a.png' -> 'ppt/media/a.png'. A target starting with '/' is from the zip root. */
export function resolvePath(baseDir: string, target: string): string {
  const parts = target.startsWith('/') ? [] : baseDir.split('/').filter(Boolean)
  for (const seg of target.split('/')) {
    if (seg === '..') parts.pop()
    else if (seg && seg !== '.') parts.push(seg)
  }
  return parts.join('/')
}

// ───────── Text ─────────

/** One paragraph's text: runs, line breaks and fields (slide number and date fields are left out). */
function paragraphText(p: Element): string {
  let s = ''
  for (const c of Array.from(p.children)) {
    if (c.localName === 'r') s += first(c, 't')?.textContent ?? ''
    else if (c.localName === 'br') s += '\n'
    else if (c.localName === 'fld') {
      const type = (c.getAttribute('type') ?? '').toLowerCase()
      if (!type.startsWith('slidenum') && !type.startsWith('datetime')) s += first(c, 't')?.textContent ?? ''
    }
  }
  s = s.replace(/ /g, ' ').replace(/[ \t]+\n/g, '\n').trimEnd()
  const lvl = Number(first(p, 'pPr')?.getAttribute('lvl') ?? 0)
  return lvl >= 1 && s.trim() ? `– ${s.trimStart()}` : s
}

/** Joins paragraph strings: one per line, blank paragraphs collapse to a single blank line, no blank lines at the ends. */
export function joinParagraphs(paras: string[]): string {
  const lines: string[] = []
  for (const p of paras) {
    const t = p.trim() === '' ? '' : p
    if (t === '' && (lines.length === 0 || lines[lines.length - 1] === '')) continue
    lines.push(t)
  }
  while (lines.length && lines[lines.length - 1] === '') lines.pop()
  return lines.join('\n')
}

function txBodyParagraphs(sp: Element): string[] {
  const body = kids(sp, 'txBody')[0]
  return body ? kids(body, 'p').map(paragraphText) : []
}

type Collected = { title: string[]; body: string[]; blocks: { paras: string[]; isTextBox: boolean }[]; pictures: PptxPicture[]; mediaRids: string[] }

const SKIP_PH = new Set(['sldNum', 'dt', 'ftr', 'hdr', 'sldImg'])

function xfrmArea(el: Element): number {
  const ext = first(el, 'ext')
  const cx = Number(ext?.getAttribute('cx') ?? 0)
  const cy = Number(ext?.getAttribute('cy') ?? 0)
  return cx > 0 && cy > 0 ? cx * cy : 0
}

/** Walks a shape tree in document order (PowerPoint's stacking order, which is normally creation order). */
function walk(tree: Element, rels: Map<string, Rel>, out: Collected) {
  for (const node of Array.from(tree.children)) {
    switch (node.localName) {
      case 'sp': {
        const ph = first(node, 'ph')
        const phType = ph?.getAttribute('type') ?? (ph ? 'body' : '')
        if (SKIP_PH.has(phType)) break
        const spPr = kids(node, 'spPr')[0]
        const fill = spPr ? first(spPr, 'blip') : undefined
        if (fill) addPicture(out, rels, rAttr(fill, 'embed'), xfrmArea(spPr))
        const paras = txBodyParagraphs(node)
        if (!paras.some((t) => t.trim())) break
        if (phType === 'title' || phType === 'ctrTitle') out.title.push(...paras)
        else if (ph) out.body.push(...paras) // body, subTitle, obj, other placeholders
        else out.blocks.push({ paras, isTextBox: true })
        break
      }
      case 'grpSp':
        walk(node, rels, out)
        break
      case 'pic': {
        const nvPr = first(node, 'nvPr')
        const isMedia = !!nvPr && (first(nvPr, 'videoFile') || first(nvPr, 'audioFile') || first(nvPr, 'media'))
        if (isMedia) {
          for (const e of [first(nvPr!, 'videoFile'), first(nvPr!, 'audioFile'), first(nvPr!, 'media')]) {
            if (!e) continue
            const rid = rAttr(e, 'link') || rAttr(e, 'embed')
            if (rid) out.mediaRids.push(rid)
          }
          break // its picture is only the poster frame
        }
        const blip = first(node, 'blip')
        const spPr = kids(node, 'spPr')[0]
        if (blip) addPicture(out, rels, rAttr(blip, 'embed'), spPr ? xfrmArea(spPr) : 0)
        break
      }
      case 'graphicFrame': {
        const rows = all(node, 'tr').map((tr) =>
          kids(tr, 'tc')
            .map((tc) => joinParagraphs(kids(first(tc, 'txBody') ?? tc, 'p').map(paragraphText)).replace(/\n+/g, ' '))
            .filter(Boolean)
            .join(' | '),
        )
        if (rows.some(Boolean)) out.blocks.push({ paras: rows, isTextBox: false })
        break
      }
      case 'AlternateContent': {
        const choice = kids(node, 'Choice')[0] ?? kids(node, 'Fallback')[0]
        if (choice) walk(choice, rels, out)
        break
      }
    }
  }
}

function addPicture(out: Collected, rels: Map<string, Rel>, rid: string, area: number) {
  const rel = rid ? rels.get(rid) : undefined
  if (!rel || rel.external) return
  const ext = extOf(rel.target)
  if (!out.pictures.some((p) => p.path === rel.target)) out.pictures.push({ path: rel.target, ext, supported: PICTURE_EXT.includes(ext), area })
}

export type ParsedSlideXml = {
  title: string
  body: string
  pictures: PptxPicture[]
  bgPicture: PptxPicture | null
  mediaRids: string[]
  hidden: boolean
}

/** Text and pictures of one slide's XML. `rels` are the slide's relationships (see parseRels). Pure: no zip access. */
export function parseSlideXml(xml: string, rels: Map<string, Rel>): ParsedSlideXml {
  const doc = parseXml(xml)
  const sld = doc.documentElement
  const hidden = sld?.getAttribute('show') === '0'
  const out: Collected = { title: [], body: [], blocks: [], pictures: [], mediaRids: [] }
  const tree = first(doc, 'spTree')
  if (tree) walk(tree, rels, out)

  let bgPicture: PptxPicture | null = null
  const bg = first(doc, 'bg')
  const bgBlip = bg ? first(bg, 'blip') : undefined
  if (bgBlip) {
    const tmp: Collected = { title: [], body: [], blocks: [], pictures: [], mediaRids: [] }
    addPicture(tmp, rels, rAttr(bgBlip, 'embed'), 0)
    bgPicture = tmp.pictures[0] ?? null
  }

  // Text boxes (not placeholders): the first one becomes the title when there is no title placeholder, it is a single
  // short line, and other text exists. Everything else goes to the body in tree order.
  const blocks = out.blocks.map((b) => b.paras)
  let titleParas = out.title
  if (titleParas.length === 0 && blocks.length + (out.body.length ? 1 : 0) > 1) {
    const firstBlock = blocks[0]
    const lines = firstBlock.filter((t) => t.trim())
    if (lines.length === 1 && lines[0].length <= 80 && !lines[0].includes('\n') && out.blocks[0].isTextBox) {
      titleParas = lines
      blocks.shift()
    }
  }
  const bodyParas: string[] = []
  const addBlock = (paras: string[]) => {
    if (bodyParas.length && bodyParas[bodyParas.length - 1] !== '') bodyParas.push('')
    bodyParas.push(...paras)
  }
  if (out.body.length) addBlock(out.body)
  for (const b of blocks) addBlock(b)

  return {
    title: joinParagraphs(titleParas.map((t) => t.replace(/\n/g, ' '))),
    body: joinParagraphs(bodyParas),
    pictures: out.pictures,
    bgPicture,
    mediaRids: out.mediaRids,
    hidden,
  }
}

/** Speaker notes: the text of the notes page's body placeholder (not the slide image, slide number or footer). */
export function parseNotesXml(xml: string): string {
  const doc = parseXml(xml)
  const paras: string[] = []
  for (const sp of all(doc, 'sp')) {
    const ph = first(sp, 'ph')
    if (!ph || (ph.getAttribute('type') ?? 'body') !== 'body') continue
    paras.push(...txBodyParagraphs(sp))
  }
  return joinParagraphs(paras)
}

// ───────── The whole file ─────────

async function readText(zip: JSZip, path: string): Promise<string | null> {
  const f = zip.file(path)
  return f ? f.async('string') : null
}

/** Uncompressed size of a zip entry without unpacking it (null when this jszip build does not say). */
export function entrySize(zip: JSZip, path: string): number | null {
  const n = (zip.file(path) as unknown as { _data?: { uncompressedSize?: number } } | null)?._data?.uncompressedSize
  return typeof n === 'number' ? n : null
}

function mediaFromRels(slideRels: Map<string, Rel>, zip: JSZip, wanted: Set<string>): PptxMedia[] {
  const out: PptxMedia[] = []
  const seen = new Set<string>()
  for (const [id, rel] of slideRels) {
    const t = rel.type.split('/').pop()
    if (t !== 'video' && t !== 'audio' && t !== 'media') continue
    if (wanted.size && !wanted.has(id) && t === 'media') continue
    if (rel.external) {
      if (!seen.has(rel.target)) out.push({ path: '', kind: 'video', ext: '', size: null, supported: false, external: rel.target })
      seen.add(rel.target)
      continue
    }
    if (seen.has(rel.target)) continue
    const ext = extOf(rel.target)
    const kind: PptxMedia['kind'] | null = VIDEO_EXT.includes(ext) || ['wmv', 'avi', 'mpg', 'mpeg', 'mkv'].includes(ext) ? 'video' : AUDIO_EXT.includes(ext) || ['wma', 'mid', 'midi'].includes(ext) ? 'audio' : null
    if (!kind) continue
    seen.add(rel.target)
    out.push({ path: rel.target, kind, ext, size: entrySize(zip, rel.target), supported: (kind === 'video' ? VIDEO_EXT : AUDIO_EXT).includes(ext) })
  }
  return out
}

/** Reads a .pptx (or the bytes of one). Throws a readable message if it is not a PowerPoint file. */
export async function parsePptx(data: ArrayBuffer | Uint8Array | Blob): Promise<Pptx> {
  const { default: JSZipCtor } = await import('jszip')
  let zip: JSZip
  try {
    zip = await JSZipCtor.loadAsync(data)
  } catch {
    throw new Error("This doesn't look like a PowerPoint (.pptx) file. Old .ppt files must be saved as .pptx first (File > Save As).")
  }
  const presXml = await readText(zip, 'ppt/presentation.xml')
  if (!presXml) throw new Error("This doesn't look like a PowerPoint (.pptx) file.")
  const presRels = parseRels((await readText(zip, 'ppt/_rels/presentation.xml.rels')) ?? '<Relationships/>', 'ppt')
  const pres = parseXml(presXml)

  // Slide order = the order of sldId entries in presentation.xml (file names do not matter).
  let paths: string[] = all(pres, 'sldId')
    .map((s) => presRels.get(rAttr(s, 'id'))?.target ?? '')
    .filter((p) => p && zip.file(p))
  if (paths.length === 0) {
    paths = Object.keys(zip.files)
      .filter((p) => /^ppt\/slides\/slide\d+\.xml$/.test(p))
      .sort((a, b) => Number(a.match(/(\d+)\.xml$/)![1]) - Number(b.match(/(\d+)\.xml$/)![1]))
  }

  const sz = first(pres, 'sldSz')
  const cx = Number(sz?.getAttribute('cx') ?? 0)
  const cy = Number(sz?.getAttribute('cy') ?? 0)
  const aspect = cx > 0 && cy > 0 ? cx / cy : 16 / 9

  const slides: PptxSlide[] = []
  for (let i = 0; i < paths.length; i++) {
    const path = paths[i]
    const dir = path.slice(0, path.lastIndexOf('/'))
    const file = path.slice(path.lastIndexOf('/') + 1)
    const xml = (await readText(zip, path)) ?? ''
    const relsXml = await readText(zip, `${dir}/_rels/${file}.rels`)
    const rels = relsXml ? parseRels(relsXml, dir) : new Map<string, Rel>()
    const parsed = parseSlideXml(xml, rels)

    let notes = ''
    for (const rel of rels.values()) {
      if (rel.type.endsWith('/notesSlide')) {
        const nx = await readText(zip, rel.target)
        if (nx) notes = parseNotesXml(nx)
      }
    }
    const media = mediaFromRels(rels, zip, new Set(parsed.mediaRids))
    const hasText = !!(parsed.title || parsed.body)
    slides.push({
      number: i + 1,
      path,
      hidden: parsed.hidden,
      title: parsed.title,
      body: parsed.body,
      notes,
      pictures: parsed.pictures,
      bgPicture: parsed.bgPicture,
      media,
      kind: hasText ? 'text' : parsed.pictures.length || parsed.bgPicture ? 'picture' : 'empty',
    })
  }
  return { zip, slides, aspect }
}

/** The picture a picture-only slide becomes: the largest drawn picture that can be imported, else the background. */
export function mainPicture(s: PptxSlide): PptxPicture | null {
  const ok = s.pictures.filter((p) => p.supported)
  if (ok.length) return ok.reduce((a, b) => (b.area > a.area ? b : a))
  return s.bgPicture?.supported ? s.bgPicture : null
}

/** Reads the bytes of a picture or media file inside the pptx as a File ready to upload. */
export async function pptxFile(zip: JSZip, path: string, name: string): Promise<File> {
  const f = zip.file(path)
  if (!f) throw new Error('The file is missing from the PowerPoint.')
  const blob = await f.async('blob')
  const ext = extOf(path)
  return new File([blob], name, { type: MIME[ext] ?? 'application/octet-stream' })
}
