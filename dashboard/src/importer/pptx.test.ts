// @vitest-environment jsdom
import JSZip from 'jszip'
import { describe, expect, it } from 'vitest'
import { joinParagraphs, mainPicture, parsePptx, resolvePath } from './pptx'
import { deckSlidesFrom, folderNameForImages, naturalCompare, pageFileName, playlistItemsFrom } from './importLogic'
import { uniqueName } from './uploadMedia'

const NS = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
const REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

const para = (text: string, lvl = 0) => `<a:p>${lvl ? `<a:pPr lvl="${lvl}"/>` : ''}<a:r><a:t>${text}</a:t></a:r></a:p>`
const sp = (name: string, ph: string | null, paras: string, cxcy = '') =>
  `<p:sp><p:nvSpPr><p:cNvPr id="1" name="${name}"/><p:cNvSpPr/><p:nvPr>${ph ? `<p:ph ${ph}/>` : ''}</p:nvPr></p:nvSpPr><p:spPr>${cxcy}</p:spPr><p:txBody><a:bodyPr/>${paras}</p:txBody></p:sp>`
const slide = (shapes: string, attrs = '', bg = '') => `<?xml version="1.0"?><p:sld ${NS} ${attrs}><p:cSld>${bg}<p:spTree><p:nvGrpSpPr/><p:grpSpPr/>${shapes}</p:spTree></p:cSld></p:sld>`
const pic = (rid: string, cx: number, cy: number, extra = '') =>
  `<p:pic><p:nvPicPr><p:cNvPr id="2" name="Pic"/><p:cNvPicPr/><p:nvPr>${extra}</p:nvPr></p:nvPicPr><p:blipFill><a:blip r:embed="${rid}"/></p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm></p:spPr></p:pic>`
const rels = (items: [string, string, string, boolean?][]) =>
  `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${items
    .map(([id, type, target, ext]) => `<Relationship Id="${id}" Type="${REL}/${type}" Target="${target}"${ext ? ' TargetMode="External"' : ''}/>`)
    .join('')}</Relationships>`

/** Slides are stored under shuffled file names; presentation.xml says the real order: slide9 (1st), slide5 (2nd), slide2 (3rd), slide7 (4th). */
async function fixture(): Promise<Uint8Array> {
  const z = new JSZip()
  z.file(
    'ppt/presentation.xml',
    `<?xml version="1.0"?><p:presentation ${NS}><p:sldIdLst><p:sldId id="256" r:id="rId10"/><p:sldId id="257" r:id="rId11"/><p:sldId id="258" r:id="rId12"/><p:sldId id="259" r:id="rId13"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>`,
  )
  z.file(
    'ppt/_rels/presentation.xml.rels',
    rels([
      ['rId10', 'slide', 'slides/slide9.xml'],
      ['rId11', 'slide', 'slides/slide5.xml'],
      ['rId12', 'slide', 'slides/slide2.xml'],
      ['rId13', 'slide', 'slides/slide7.xml'],
    ]),
  )
  // 1st: title + body placeholders, a footer and slide number that must be ignored, speaker notes
  z.file(
    'ppt/slides/slide9.xml',
    slide(
      sp('Title', 'type="title"', para('Welcome &amp; Announcements')) +
        sp('Body', 'idx="1"', para('Coffee after service') + para('Kids check-in opens at 9', 1) + '<a:p><a:r><a:t>Line one</a:t></a:r><a:br/><a:r><a:t>line two</a:t></a:r></a:p>' + para('') + para('')) +
        sp('Footer', 'type="ftr" idx="11"', para('Forward Church')) +
        sp('Num', 'type="sldNum" idx="12"', '<a:p><a:fld type="slidenum"><a:t>1</a:t></a:fld></a:p>'),
    ),
  )
  z.file('ppt/slides/_rels/slide9.xml.rels', rels([['rId1', 'notesSlide', '../notesSlides/notesSlide1.xml']]))
  z.file(
    'ppt/notesSlides/notesSlide1.xml',
    `<?xml version="1.0"?><p:notes ${NS}><p:cSld><p:spTree>${sp('Image', 'type="sldImg"', para('IGNORED IMAGE'))}${sp('Notes', 'type="body" idx="1"', para('Say hello.') + para('Mention the picnic.'))}${sp('Num', 'type="sldNum"', para('1'))}</p:spTree></p:cSld></p:notes>`,
  )
  // 2nd: picture only: a small logo and a big photo; the big one wins. An emf picture is unsupported.
  z.file('ppt/slides/slide5.xml', slide(pic('rId2', 100000, 100000) + pic('rId3', 9000000, 5000000) + pic('rId4', 12000000, 7000000)))
  z.file('ppt/slides/_rels/slide5.xml.rels', rels([['rId2', 'image', '../media/logo.png'], ['rId3', 'image', '../media/photo.jpg'], ['rId4', 'image', '../media/huge.emf']]))
  z.file('ppt/media/logo.png', new Uint8Array([1]))
  z.file('ppt/media/photo.jpg', new Uint8Array([2, 2]))
  z.file('ppt/media/huge.emf', new Uint8Array([3]))
  // 3rd: no placeholders: a short heading text box, a body text box, a table, and a group; hidden; has an mp4 and a YouTube link
  z.file(
    'ppt/slides/slide2.xml',
    slide(
      sp('Heading', null, para('Sermon Series')) +
        sp('Text', null, para('Week 1: Begin')) +
        `<p:grpSp><p:nvGrpSpPr/><p:grpSpPr/>${sp('Inner', null, para('Inside a group'))}</p:grpSp>` +
        `<p:graphicFrame><a:graphic><a:graphicData><a:tbl><a:tr><a:tc><a:txBody>${para('Time')}</a:txBody></a:tc><a:tc><a:txBody>${para('Room')}</a:txBody></a:tc></a:tr><a:tr><a:tc><a:txBody>${para('9:00')}</a:txBody></a:tc><a:tc><a:txBody>${para('Gym')}</a:txBody></a:tc></a:tr></a:tbl></a:graphicData></a:graphic></p:graphicFrame>` +
        pic('rId9', 5000000, 3000000, '<a:videoFile r:link="rId5"/>'),
      'show="0"',
    ),
  )
  z.file(
    'ppt/slides/_rels/slide2.xml.rels',
    rels([['rId5', 'video', '../media/clip.mp4'], ['rId6', 'media', '../media/clip.mp4'], ['rId7', 'video', 'https://www.youtube.com/embed/abc', true], ['rId8', 'audio', '../media/song.wma'], ['rId9', 'image', '../media/poster.png']]),
  )
  z.file('ppt/media/clip.mp4', new Uint8Array(1234))
  z.file('ppt/media/song.wma', new Uint8Array(10))
  z.file('ppt/media/poster.png', new Uint8Array([9]))
  // 4th: nothing at all
  z.file('ppt/slides/slide7.xml', slide(''))
  return z.generateAsync({ type: 'uint8array' })
}

describe('parsePptx', () => {
  it('orders slides by presentation.xml, not by file name', async () => {
    const p = await parsePptx(await fixture())
    expect(p.slides.map((s) => s.path)).toEqual(['ppt/slides/slide9.xml', 'ppt/slides/slide5.xml', 'ppt/slides/slide2.xml', 'ppt/slides/slide7.xml'])
    expect(p.slides.map((s) => s.number)).toEqual([1, 2, 3, 4])
    expect(p.aspect).toBeCloseTo(16 / 9)
  })

  it('extracts title, body in order, ignores footer and slide number, and keeps notes', async () => {
    const s = (await parsePptx(await fixture())).slides[0]
    expect(s.kind).toBe('text')
    expect(s.title).toBe('Welcome & Announcements')
    expect(s.body).toBe('Coffee after service\n– Kids check-in opens at 9\nLine one\nline two')
    expect(s.notes).toBe('Say hello.\nMention the picnic.')
    expect(s.hidden).toBe(false)
  })

  it('treats a slide with only pictures as a picture slide and picks the largest supported picture', async () => {
    const s = (await parsePptx(await fixture())).slides[1]
    expect(s.kind).toBe('picture')
    expect(s.pictures.map((p) => [p.path, p.supported])).toEqual([
      ['ppt/media/logo.png', true],
      ['ppt/media/photo.jpg', true],
      ['ppt/media/huge.emf', false],
    ])
    expect(mainPicture(s)?.path).toBe('ppt/media/photo.jpg')
  })

  it('uses a short first text box as the title when there are no placeholders; reads groups and tables; flags hidden', async () => {
    const s = (await parsePptx(await fixture())).slides[2]
    expect(s.hidden).toBe(true)
    expect(s.title).toBe('Sermon Series')
    expect(s.body).toBe('Week 1: Begin\n\nInside a group\n\nTime | Room\n9:00 | Gym')
    expect(s.pictures).toEqual([]) // the video's poster frame is not a picture
  })

  it('lists embedded media once, with support and external links', async () => {
    const m = (await parsePptx(await fixture())).slides[2].media
    expect(m.map((x) => [x.path || x.external, x.kind, x.supported, x.size])).toEqual([
      ['ppt/media/clip.mp4', 'video', true, 1234],
      ['https://www.youtube.com/embed/abc', 'video', false, null],
      ['ppt/media/song.wma', 'audio', false, 10],
    ])
  })

  it('marks a slide with nothing as empty, and rejects a non-pptx file', async () => {
    const p = await parsePptx(await fixture())
    expect(p.slides[3].kind).toBe('empty')
    await expect(parsePptx(new Uint8Array([1, 2, 3]))).rejects.toThrow(/pptx/)
  })
})

describe('helpers', () => {
  it('resolves relative targets', () => {
    expect(resolvePath('ppt/slides', '../media/a.png')).toBe('ppt/media/a.png')
    expect(resolvePath('ppt/slides', '/ppt/media/a.png')).toBe('ppt/media/a.png')
    expect(resolvePath('ppt', 'slides/slide1.xml')).toBe('ppt/slides/slide1.xml')
  })
  it('joins paragraphs without stray blank lines', () => {
    expect(joinParagraphs(['', 'a', '', '', 'b', ''])).toBe('a\n\nb')
  })
  it('names pages and folders', () => {
    expect(pageFileName('Easter', 3, 12, 'jpg')).toBe('Easter 03.jpg')
    expect(pageFileName('Easter', 3, 120, 'jpg')).toBe('Easter 003.jpg')
    expect(naturalCompare('Slide2.png', 'Slide10.png')).toBeLessThan(0)
    expect(folderNameForImages(['Slide1.PNG', 'Slide2.PNG', 'Slide10.PNG'])).toBe('Slide')
    expect(folderNameForImages(['a.png', 'b.png'], new Date('2026-10-21T12:00:00Z'))).toBe('Imported pictures 2026-10-21')
    expect(uniqueName(['Easter', 'easter (2)'], 'Easter')).toBe('Easter (3)')
  })
  it('builds deck slides', () => {
    const slides = deckSlidesFrom(
      [
        { type: 'text', title: 'T', body: 'B', notes: 'n' },
        { type: 'text', title: '', body: 'only' },
        { type: 'image', media_id: 'm1', url: 'u1', title: 'x' },
        { type: 'video', media_id: 'm2', url: 'u2', title: 'v' },
      ],
      null,
      [],
    )
    expect(slides.map((s) => s.kind)).toEqual(['text', 'text', 'media', 'media'])
    expect(slides[0]).toMatchObject({ layout: 'title_body', notes: 'n', seconds: null })
    expect(slides[1]).toMatchObject({ layout: 'body' })
    expect(slides[2]).toMatchObject({ media_kind: 'image', fit: 'contain', seconds: null, background: { type: 'color', color: '#000000' } })
    expect(slides[3]).toMatchObject({ media_kind: 'video', audio: true })
    expect(new Set(slides.map((s) => s.id)).size).toBe(4)
  })
  it('builds Kids items', () => {
    expect(playlistItemsFrom([{ type: 'image', media_id: 'm', url: 'u', title: 't' }, { type: 'video', media_id: 'v', url: 'w', title: 'q' }], 10)).toEqual([
      { type: 'image', title: 't', url: 'u', media_id: 'm', seconds: 10 },
      { type: 'video', title: 'q', url: 'w', media_id: 'v' },
    ])
  })
})
