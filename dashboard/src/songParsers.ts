/**
 * Song import parsers (plain text, CCLI SongSelect .usr, ChordPro) and the client-side slide preview.
 *
 * Everything here is pure (no DOM, no Supabase) so it can be run in Node: see selfCheck() at the bottom.
 * The database function song_expand() is the truth for what the TV shows; expandSong() only mirrors it for the preview.
 */

export type SongSection = { id: string; label: string; text: string }

/** What an importer found, ready to review and save as a `songs` row. */
export type ParsedSong = {
  title: string
  authors: string
  ccli_number: string
  copyright: string
  sections: SongSection[]
}

export type SongSource = 'manual' | 'paste' | 'file'

// ───────── Section labels ─────────

const LABEL_WORDS = 'verse|chorus|pre[\\s-]?chorus|bridge|tag|intro|outro|interlude|refrain|ending|instrumental|turnaround|vamp'
/** A line that is only a section label: "Verse", "Verse 1", "[Chorus]", "(Bridge 2)", "PRE-CHORUS:" ... */
const LABEL_LINE = new RegExp(`^\\s*[\\[(]?\\s*((?:${LABEL_WORDS})(?:\\s*\\d+)?)\\s*[\\])]?\\s*:?\\s*$`, 'i')

/** "verse 1" -> "Verse 1", "pre chorus" -> "Pre-Chorus"; null when the line is not a label. */
export function labelFromLine(line: string): string | null {
  const m = LABEL_LINE.exec(line)
  if (!m) return null
  return m[1]
    .toLowerCase()
    .replace(/pre[\s-]?chorus/, 'pre-chorus')
    .replace(/([a-z])\s*(\d)/, '$1 $2')
    .replace(/(^|[\s-])([a-z])/g, (_s, p: string, c: string) => p + c.toUpperCase())
}

// ───────── Helpers ─────────

const normalise = (text: string) =>
  text
    .replace(/^﻿/, '')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map((l) => l.replace(/[ \t ]+$/, ''))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')

function withIds(parts: { label: string; text: string }[]): SongSection[] {
  return parts
    .map((p) => ({ label: p.label.trim(), text: p.text.replace(/^\n+|\n+$/g, '') }))
    .filter((p) => p.text.trim() !== '')
    .map((p, i) => ({ id: `s${i + 1}`, label: p.label, text: p.text }))
}

const emptySong = (): ParsedSong => ({ title: '', authors: '', ccli_number: '', copyright: '', sections: [] })

const CCLI_LINE = /^\s*CCLI\s+(?:Song\s*)?(?:#|No\.?|Number)\s*:?\s*(\d{3,9})\b/i
const CCLI_LICENCE_LINE = /^\s*CCLI\s+Licen[cs]e/i
const COPYRIGHT_LINE = /^\s*(?:©|\(c\)|copyright\b)/i

/** Splits lyric lines into sections: label lines start one, otherwise blank lines separate them. */
function splitSections(lines: string[]): { label: string; text: string }[] {
  const out: { label: string; text: string }[] = []
  let cur: { label: string | null; lines: string[] } | null = null
  const flush = () => {
    if (cur && cur.lines.some((l) => l.trim())) out.push({ label: cur.label ?? '', text: cur.lines.join('\n') })
    cur = null
  }
  for (const line of lines) {
    const label = labelFromLine(line)
    if (label) {
      flush()
      cur = { label, lines: [] }
    } else if (line.trim() === '') {
      flush()
    } else {
      if (!cur) cur = { label: null, lines: [] }
      cur.lines.push(line)
    }
  }
  flush()
  // Unlabelled sections are named by their position: Section 1, Section 2 ...
  return out.map((s, i) => ({ label: s.label || `Section ${i + 1}`, text: s.text }))
}

// ───────── Plain text ─────────

/**
 * Plain pasted lyrics. `titleHint` is the title typed by the user; when empty, a first line that is not a label and is
 * followed by a blank line becomes the title.
 */
export function parsePlainText(raw: string, titleHint = ''): ParsedSong {
  const song = emptySong()
  song.title = titleHint.trim()
  const copyright: string[] = []
  const lines: string[] = []
  for (const line of normalise(raw).split('\n')) {
    const ccli = CCLI_LINE.exec(line)
    if (ccli) {
      if (!song.ccli_number) song.ccli_number = ccli[1]
    } else if (CCLI_LICENCE_LINE.test(line)) {
      /* a church licence number, not a song number: drop it from the lyrics */
    } else if (COPYRIGHT_LINE.test(line)) {
      copyright.push(line.trim())
    } else lines.push(line)
  }
  song.copyright = copyright.join(' ')

  while (lines.length && lines[0].trim() === '') lines.shift()
  if (!song.title && lines.length > 1 && !labelFromLine(lines[0]) && lines[1].trim() === '') {
    song.title = lines[0].trim()
    lines.shift()
  }
  // Copyright/CCLI removal can leave runs of blank lines.
  const collapsed = lines.join('\n').replace(/\n{3,}/g, '\n\n').split('\n')
  song.sections = withIds(splitSections(collapsed))
  return song
}

// ───────── CCLI SongSelect .usr ─────────

/**
 * ASSUMPTION - MUST BE RE-VERIFIED WITH A REAL SONGSELECT DOWNLOAD. The format below is reconstructed from memory of the
 * classic ".usr" lyric file and has not been checked against a current download. It is INI-like:
 *
 *   [File]
 *   Type=SongSelect Import File
 *   [S A1234567]                 <- header: "S A" + the CCLI song number
 *   Title=Amazing Grace
 *   Author=John Newton | Edwin Excell      (' | ' or ',' between authors)
 *   Copyright=Public Domain
 *   CCLISongID=1234567                      (also tolerated: "CCLI Song #=...")
 *   Fields=Verse 1/Chorus                   (section names, '/' separated)
 *   Words=line one/line two/tline one/line two      ('/t' between sections, '/' between lines)
 *
 * The parser is deliberately tolerant: unknown keys are ignored, key case does not matter, real newlines inside Words are
 * accepted, and when the number of Fields does not match the number of sections found in Words the sections are named
 * "Section n". A file that does not look like an INI file at all is handed to the plain text parser.
 */
export function parseUsr(raw: string, titleHint = ''): ParsedSong {
  const text = normalise(raw)
  const looksIni = /^\s*\[S\s/im.test(text) || /^\s*(Words|Fields)\s*=/im.test(text)
  if (!looksIni) return parsePlainText(text, titleHint)

  const song = emptySong()
  const kv: Record<string, string> = {}
  for (const line of text.split('\n')) {
    const header = /^\s*\[\s*S\s+A?(\d+)\s*\]/i.exec(line)
    if (header) {
      song.ccli_number = header[1]
      continue
    }
    const m = /^\s*([^=\[\]]+?)\s*=\s*(.*)$/.exec(line)
    if (m) kv[m[1].toLowerCase().replace(/[\s_#]+/g, '')] = m[2].trim()
  }
  if (!song.ccli_number) {
    // CCLISongID=, CCLI Song #=, CCLI=, CCLISongNumber= ... (keys are lower-cased with spaces, '_' and '#' removed)
    const key = Object.keys(kv).find((k) => k.startsWith('ccli') && /\d{3,9}/.test(kv[k]))
    song.ccli_number = key ? /\d{3,9}/.exec(kv[key])![0] : ''
  }
  song.title = titleHint.trim() || kv.title || ''
  const authors = kv.author ?? kv.authors ?? kv.writer ?? ''
  song.authors = authors
    .split(/\s*\|\s*|\s*,\s*/)
    .filter(Boolean)
    .join(', ')
  song.copyright = kv.copyright ?? ''

  const words = kv.words ?? ''
  const blocks = words.includes('/t') || words.includes('/') ? words.split('/t') : words.split(/\n\s*\n/)
  const parts = blocks.map((b) =>
    b
      .split(/\/|\n/)
      .map((l) => l.trim())
      .filter((l, i, a) => l !== '' || (i > 0 && i < a.length - 1))
      .join('\n'),
  )
  const fields = (kv.fields ?? '')
    .split('/')
    .map((f) => f.trim())
    .filter(Boolean)
  const useFields = fields.length === parts.length
  song.sections = withIds(parts.map((text, i) => ({ label: useFields ? fields[i] : `Section ${i + 1}`, text })))
  return song
}

// ───────── ChordPro ─────────

const unchord = (line: string) => line.replace(/\[[^\]]*\]/g, '').replace(/[ \t]{2,}/g, ' ').trim()

/** ChordPro: directives for metadata and sections; inline chords like [G] or [Am7/C] are removed. */
export function parseChordPro(raw: string, titleHint = ''): ParsedSong {
  const song = emptySong()
  song.title = titleHint.trim()
  const authors: string[] = []
  const parts: { label: string; text: string }[] = []
  let cur: { label: string; lines: string[]; block: boolean } | null = null
  let skipping = false // inside a chord/tab block
  const flush = () => {
    if (cur && cur.lines.some((l) => l.trim())) parts.push({ label: cur.label, text: cur.lines.join('\n') })
    cur = null
  }
  const start = (label: string, block: boolean) => {
    flush()
    cur = { label, lines: [], block }
  }
  const addAuthor = (a: string) => {
    if (a && !authors.includes(a)) authors.push(a)
  }
  const BLOCKS: Record<string, string> = { verse: 'Verse', chorus: 'Chorus', bridge: 'Bridge', sov: 'Verse', soc: 'Chorus', sob: 'Bridge' }

  for (const line of normalise(raw).split('\n')) {
    if (/^\s*#/.test(line)) continue
    const d = /^\s*\{\s*([a-z_]+)\s*(?::\s*(.*?))?\s*\}\s*$/i.exec(line)
    if (d) {
      const name = d[1].toLowerCase()
      const arg = (d[2] ?? '').trim()
      if (name === 'title' || name === 't') {
        if (!song.title) song.title = arg
      } else if (['subtitle', 'st', 'artist', 'author', 'composer', 'lyricist', 'words', 'music'].includes(name)) addAuthor(arg)
      else if (name === 'ccli' || name === 'ccli_song' || name === 'ccliid') song.ccli_number = /\d{3,9}/.exec(arg)?.[0] ?? arg
      else if (name === 'copyright') song.copyright = arg
      else if (name.startsWith('start_of_') || name === 'sov' || name === 'soc' || name === 'sob') {
        const kind = name.replace('start_of_', '')
        if (kind in BLOCKS) start(arg || BLOCKS[kind], true)
        else if (kind === 'tab' || kind === 'grid') {
          flush()
          skipping = true
        } else start(arg || (kind.charAt(0).toUpperCase() + kind.slice(1)), true)
      } else if (name.startsWith('end_of_') || name === 'eov' || name === 'eoc' || name === 'eob') {
        flush()
        skipping = false
      } else if (name === 'comment' || name === 'c' || name === 'comment_italic' || name === 'ci' || name === 'comment_box' || name === 'cb') {
        const label = labelFromLine(arg)
        if (label) start(label, false)
      }
      continue
    }
    if (skipping) continue
    const label = labelFromLine(line)
    if (label) {
      start(label, false)
      continue
    }
    const text = unchord(line)
    if (text === '') {
      if (cur && !cur.block) flush()
      continue
    }
    if (!cur) cur = { label: '', lines: [], block: false }
    cur.lines.push(text)
  }
  flush()
  song.authors = authors.join(', ')
  song.sections = withIds(parts.map((p, i) => ({ label: p.label || `Section ${i + 1}`, text: p.text })))
  return song
}

// ───────── Files ─────────

/** Picks a parser from the file name (and, for .txt, a quick look inside). The title falls back to the file name. */
export function parseSongFile(fileName: string, text: string): ParsedSong {
  const ext = (/\.([a-z0-9]+)$/i.exec(fileName)?.[1] ?? '').toLowerCase()
  let song: ParsedSong
  if (ext === 'usr') song = parseUsr(text)
  else if (['cho', 'chordpro', 'pro', 'crd', 'chopro'].includes(ext) || /^\s*\{\s*(title|t|start_of_\w+|sov|soc)\b/im.test(text)) song = parseChordPro(text)
  else song = parsePlainText(text)
  if (!song.title) song.title = fileName.replace(/\.[^.]+$/, '').replace(/[_]+/g, ' ').trim()
  return song
}

export const SONG_FILE_EXTENSIONS = ['txt', 'usr', 'cho', 'chordpro', 'pro']

// ───────── Preview (mirror of song_expand in the database) ─────────

export type SongSlide = { label: string; text: string }

/** The slides a song produces, following its arrangement and lines per slide. The database is the truth; this is a preview. */
export function expandSong(song: { sections: SongSection[]; arrangement: string[] | null; lines_per_slide: number }): SongSlide[] {
  const ids = song.arrangement?.length ? song.arrangement : song.sections.map((s) => s.id)
  const slides: SongSlide[] = []
  for (const id of ids) {
    const sec = song.sections.find((s) => s.id === id)
    if (!sec) continue
    const lines = (sec.text ?? '').replace(/\r/g, '').replace(/^[\n ]+|[\n ]+$/g, '').split('\n')
    if (lines.join('').trim() === '') continue
    const n = song.lines_per_slide
    if (n > 0) for (let i = 0; i < lines.length; i += n) slides.push({ label: sec.label, text: lines.slice(i, i + n).join('\n') })
    else slides.push({ label: sec.label, text: lines.join('\n') })
  }
  return slides
}

/** Next unused section id: s1, s2 ... unique within the song. */
export function newSectionId(sections: { id: string }[]): string {
  const used = new Set(sections.map((s) => s.id))
  for (let n = sections.length + 1; ; n++) if (!used.has(`s${n}`)) return `s${n}`
}

// ───────── Self-check (run in Node; not used by the app) ─────────

/** Returns a list of failures (empty = all good). */
export function selfCheck(): string[] {
  const fails: string[] = []
  const eq = (name: string, got: unknown, want: unknown) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) fails.push(`${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`)
  }
  const summary = (s: ParsedSong) => s.sections.map((x) => `${x.id}|${x.label}|${x.text.split('\n').length}`)

  // plain, with labels
  const a = parsePlainText(
    'Amazing Grace  \r\n\r\n[Verse 1]\r\nAmazing grace how sweet the sound\r\nThat saved a wretch like me\r\n\r\nCHORUS:\r\nMy chains are gone\r\n\r\n\r\n\r\npre chorus\r\nHold on\r\nCCLI Song # 1234567\r\n(c) 1779 Public Domain\r\n',
  )
  eq('plain title', a.title, 'Amazing Grace')
  eq('plain ccli', a.ccli_number, '1234567')
  eq('plain copyright', a.copyright, '(c) 1779 Public Domain')
  eq('plain sections', summary(a), ['s1|Verse 1|2', 's2|Chorus|1', 's3|Pre-Chorus|1'])
  // plain, no labels, with hint
  const b = parsePlainText('Line one\nLine two\n\nLine three\n\n\n\nLine four\n© 2020 Someone', 'My Song')
  eq('nolabel title', b.title, 'My Song')
  eq('nolabel sections', summary(b), ['s1|Section 1|2', 's2|Section 2|1', 's3|Section 3|1'])
  eq('nolabel copyright', b.copyright, '© 2020 Someone')
  // plain, first line is title only when followed by a blank line
  eq('no title when no blank', parsePlainText('Line one\nLine two').title, '')
  eq('label is not title', parsePlainText('Verse 1\n\nA\nB').title, '')
  // usr
  const usr = parseUsr(
    '[File]\nType=SongSelect Import File\nVersion=3\n[S A7654321]\nTitle=How Great\nAuthor=Chris Tomlin | Jesse Reeves,Louie Giglio\nCopyright=2004 sixsteps Music\nFields=Verse 1/Chorus\nWords=How great is our God/Sing with me/tHow great is our God/All will see\n',
  )
  eq('usr title', usr.title, 'How Great')
  eq('usr ccli', usr.ccli_number, '7654321')
  eq('usr authors', usr.authors, 'Chris Tomlin, Jesse Reeves, Louie Giglio')
  eq('usr copyright', usr.copyright, '2004 sixsteps Music')
  eq('usr sections', usr.sections, [
    { id: 's1', label: 'Verse 1', text: 'How great is our God\nSing with me' },
    { id: 's2', label: 'Chorus', text: 'How great is our God\nAll will see' },
  ])
  const usr2 = parseUsr('[S A1]\nTitle=X\nFields=Verse 1\nWords=a/b/tc/d')
  eq('usr mismatch', summary(usr2), ['s1|Section 1|2', 's2|Section 2|2'])
  eq('usr plain fallback', parseUsr('Hello\n\nVerse\nWorld').sections.length, 1)
  eq('usr plain fallback title', parseUsr('Hello\n\nVerse\nWorld').title, 'Hello')
  // chordpro
  const cp = parseChordPro(
    '# comment\n{title: Good Good Father}\n{st: Pat Barrett}\n{author: Anthony Brown}\n{ccli: 7036612}\n{copyright: 2014 Capitol}\n{key: G}\n{start_of_verse: Verse 1}\n[G]Oh, I\'ve heard a thousand [Am7/C]stories\nOf what they think You\'re like\n{end_of_verse}\n{soc}\n[C]You\'re a good good [G]Father\n{eoc}\n{c: Bridge}\nLove so deep\n\n{sob}\nTag line\n{end_of_bridge}\n',
  )
  eq('cp title', cp.title, 'Good Good Father')
  eq('cp authors', cp.authors, 'Pat Barrett, Anthony Brown')
  eq('cp ccli', cp.ccli_number, '7036612')
  eq('cp copyright', cp.copyright, '2014 Capitol')
  eq('cp sections', cp.sections, [
    { id: 's1', label: 'Verse 1', text: "Oh, I've heard a thousand stories\nOf what they think You're like" },
    { id: 's2', label: 'Chorus', text: "You're a good good Father" },
    { id: 's3', label: 'Bridge', text: 'Love so deep' },
    { id: 's4', label: 'Bridge', text: 'Tag line' },
  ])
  eq('cp default label', parseChordPro('{sov}\nA\n{eov}').sections[0].label, 'Verse')
  // expand preview
  const song = { sections: a.sections, arrangement: ['s1', 's2', 's1', 'zz'], lines_per_slide: 1 }
  eq('expand', expandSong(song).map((s) => `${s.label}:${s.text.replace('\n', '/')}`), [
    'Verse 1:Amazing grace how sweet the sound',
    'Verse 1:That saved a wretch like me',
    'Chorus:My chains are gone',
    'Verse 1:Amazing grace how sweet the sound',
    'Verse 1:That saved a wretch like me',
  ])
  eq('expand default', expandSong({ sections: a.sections, arrangement: null, lines_per_slide: 0 }).length, 3)
  eq('new id', newSectionId([{ id: 's1' }, { id: 's3' }]), 's4')
  return fails
}
