import { useMemo, useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import { NdiFields } from '../NdiItem'
import type { BlankSlide, CountdownSlide, DeckSlide, MediaSlide, NdiSlide, SlideLayout, SongSlide, StreamSlide, TextSlide } from '../slidesTypes'
import type { Media } from '../types'
import type { SlidesLibrary, SongForSlides } from '../slidesPages.types'
import { isHex } from '../lib'
import CountdownFields from '../CountdownFields'
import BackgroundPicker, { ColorField } from './BackgroundPicker'
import MediaPickerDialog, { VideoPoster, oversize } from './MediaPickerDialog'
import { KIND_NAME, songScreenCount } from './render'

type Props<S extends DeckSlide> = { slide: S; onChange: (next: S) => void; lib: SlidesLibrary | undefined; songs: SongForSlides[] }

/** "Wait for Next" or "advance after N seconds". */
function SecondsField({ value, onChange, label = 'Advance' }: { value: number | null | undefined; onChange: (v: number | null) => void; label?: string }) {
  const auto = value != null
  return (
    <div className="row wrap">
      <label className="field">
        <span>{label}</span>
        <select value={auto ? 'auto' : 'wait'} onChange={(e) => onChange(e.target.value === 'auto' ? value ?? 10 : null)}>
          <option value="wait">Wait for Next (remote)</option>
          <option value="auto">Automatically after…</option>
        </select>
      </label>
      {auto && (
        <label className="field">
          <span>Seconds</span>
          <input type="number" min={1} max={3600} style={{ width: 110 }} value={value ?? 10} onChange={(e) => onChange(Math.max(1, Number(e.target.value) || 1))} />
        </label>
      )}
    </div>
  )
}

const LAYOUTS: { id: SlideLayout; label: string; hint: string }[] = [
  { id: 'title_body', label: 'Title and text', hint: 'Heading with words under it' },
  { id: 'title', label: 'Title only', hint: 'One big line' },
  { id: 'body', label: 'Text only', hint: 'Just the words' },
  { id: 'lower_third', label: 'Lower third', hint: 'Small caption at the bottom' },
]

function TextEditor({ slide, onChange }: Props<TextSlide>) {
  const patch = (p: Partial<TextSlide>) => onChange({ ...slide, ...p })
  const layout = slide.layout ?? 'title_body'
  return (
    <div className="stack-sm">
      {layout !== 'body' && (
        <label className="field">
          <span>Title</span>
          <textarea rows={2} value={slide.title ?? ''} onChange={(e) => patch({ title: e.target.value })} placeholder="e.g. Welcome" />
        </label>
      )}
      {layout !== 'title' && (
        <label className="field">
          <span>Text</span>
          <textarea rows={5} value={slide.body ?? ''} onChange={(e) => patch({ body: e.target.value })} placeholder="Words under the title" />
        </label>
      )}
      <div className="field">
        <span id="sl-layout-label">Layout</span>
        <div className="sl-seg" role="radiogroup" aria-labelledby="sl-layout-label">
          {LAYOUTS.map((l) => (
            <button key={l.id} type="button" role="radio" aria-checked={layout === l.id} className={layout === l.id ? 'on' : ''} title={l.hint} onClick={() => patch({ layout: l.id })}>
              {l.label}
            </button>
          ))}
        </div>
      </div>
      <div className="row wrap">
        <label className="field">
          <span>Align</span>
          <select value={slide.align ?? ''} onChange={(e) => patch({ align: (e.target.value || undefined) as TextSlide['align'] })}>
            <option value="">Use the theme</option>
            <option value="center">Centre</option>
            <option value="left">Left</option>
          </select>
        </label>
        <div className="field">
          <span>Text colour</span>
          <label className="check">
            <input type="checkbox" checked={!isHex(slide.text_color)} onChange={(e) => patch({ text_color: e.target.checked ? undefined : '#FFFFFF' })} />
            Use the theme colour
          </label>
        </div>
        {isHex(slide.text_color) && <ColorField label="Colour" value={slide.text_color} onChange={(text_color) => patch({ text_color })} />}
      </div>
      <SecondsField value={slide.seconds} onChange={(seconds) => patch({ seconds })} />
    </div>
  )
}

function MediaEditor({ slide, onChange, lib }: Props<MediaSlide>) {
  const [picking, setPicking] = useState(false)
  const patch = (p: Partial<MediaSlide>) => onChange({ ...slide, ...p })
  const media = lib?.media.find((m) => m.id === slide.media_id)
  function pick(m: Media) {
    onChange({ ...slide, media_id: m.id, url: m.url, media_kind: m.kind === 'video' ? 'video' : 'image', audio: slide.audio ?? true })
    setPicking(false)
  }
  return (
    <div className="stack-sm">
      <div className="row wrap">
        <div className="sl-chosen">
          {slide.url ? slide.media_kind === 'image' ? <img src={slide.url} alt="" /> : <VideoPoster url={slide.url} /> : <div className="sl-none">None</div>}
        </div>
        <div className="stack-sm">
          <b>{slide.url ? media?.title ?? '(file from the library)' : 'No file chosen yet'}</b>
          <button type="button" className="btn" onClick={() => setPicking(true)} disabled={!lib}>
            {!lib ? 'Loading library…' : slide.url ? 'Change file…' : 'Choose an image or video…'}
          </button>
        </div>
      </div>
      {media && oversize(media) && (
        <p className="note warn">This video is over 200 MB. Fire TV sticks have little storage; a smaller file (1080p H.264) is safer.</p>
      )}
      <div className="row wrap">
        <label className="field">
          <span>Fit</span>
          <select value={slide.fit ?? 'contain'} onChange={(e) => patch({ fit: e.target.value as 'contain' | 'cover' })}>
            <option value="contain">Show it all</option>
            <option value="cover">Fill the screen (crops the edges)</option>
          </select>
        </label>
      </div>
      {slide.media_kind === 'image' ? (
        <SecondsField value={slide.seconds} onChange={(seconds) => patch({ seconds })} />
      ) : (
        <>
          <label className="check">
            <input type="checkbox" checked={slide.audio ?? true} onChange={(e) => patch({ audio: e.target.checked })} />
            Play the video's sound
          </label>
          <p className="help">A video moves on by itself when it ends.</p>
        </>
      )}
      {picking && lib && <MediaPickerDialog lib={lib} kinds={['image', 'video']} value={slide.media_id} title="Choose an image or video" onPick={pick} onClose={() => setPicking(false)} />}
    </div>
  )
}

function SongEditor({ slide, onChange, songs }: Props<SongSlide>) {
  const [search, setSearch] = useState('')
  const song = songs.find((s) => s.id === slide.song_id)
  const count = useMemo(() => songScreenCount(slide, song), [slide, song])
  const q = search.trim().toLowerCase()
  const options = songs.filter((s) => !q || s.title.toLowerCase().includes(q) || (s.authors ?? '').toLowerCase().includes(q) || s.id === slide.song_id)
  return (
    <div className="stack-sm">
      <div className="row wrap">
        <label className="field grow">
          <span>Search songs</span>
          <input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Start typing a title or author" />
        </label>
        <label className="field grow">
          <span>Song</span>
          <select value={slide.song_id} onChange={(e) => onChange({ ...slide, song_id: e.target.value })}>
            <option value="">Choose a song…</option>
            {slide.song_id && !song && <option value={slide.song_id}>(song no longer in the library)</option>}
            {options.map((s) => (
              <option key={s.id} value={s.id}>
                {s.title}
              </option>
            ))}
          </select>
        </label>
      </div>
      {songs.length === 0 && <p className="note">There are no songs yet. Add some on the Songs page, then come back.</p>}
      {song && (
        <p className="muted">
          Makes {count} {count === 1 ? 'screen' : 'screens'} on the TV{slide.show_title ? ' (including the title slide)' : ''}.{' '}
          <a href="/#songs" target="_blank" rel="noreferrer">
            Edit this song
          </a>{' '}
          (opens in a new tab; the deck always uses the latest version)
        </p>
      )}
      {slide.song_id && !song && <p className="note warn">This song isn't in the library any more, so the TV will skip this slide. Choose another song.</p>}
      <label className="check">
        <input type="checkbox" checked={slide.show_title ?? false} onChange={(e) => onChange({ ...slide, show_title: e.target.checked })} />
        Show song title first
      </label>
      <p className="help">A styled title slide (with authors, copyright and CCLI number) before the words. It stays up until you press Next. The words use the theme's text style; the Songs page sets lines per slide.</p>
    </div>
  )
}

function CountdownEditor({ slide, onChange, lib }: Props<CountdownSlide>) {
  return <CountdownFields value={slide} onPatch={(p) => onChange({ ...slide, ...p })} media={lib?.media ?? []} folders={lib?.folders ?? []} />
}

const validUrl = (u: string) => /^https?:\/\/\S+$/i.test(u.trim())

function StreamEditor({ slide, onChange }: Props<StreamSlide>) {
  const [testing, setTesting] = useState(false)
  const [result, setResult] = useState<{ kind: 'ok' | 'hint'; text: string } | null>(null)
  const patch = (p: Partial<StreamSlide>) => onChange({ ...slide, ...p })

  async function test() {
    const url = slide.url.trim()
    if (!validUrl(url)) return setResult({ kind: 'hint', text: 'Paste a full link starting with https:// first.' })
    setTesting(true)
    setResult(null)
    const ctl = new AbortController()
    const timer = setTimeout(() => ctl.abort(), 8000)
    try {
      const res = await fetch(url, { cache: 'no-store', signal: ctl.signal })
      if (!res.ok) setResult({ kind: 'hint', text: `The server answered ${res.status}. Check the link, and that the broadcast is live.` })
      else {
        const head = (await res.text()).slice(0, 200)
        setResult(
          head.trimStart().startsWith('#EXTM3U')
            ? { kind: 'ok', text: 'The link answered and looks like an HLS stream.' }
            : { kind: 'hint', text: "The link answered, but it doesn't look like an .m3u8 stream playlist. Double-check you copied the M3U8 link." },
        )
      }
    } catch {
      setResult({ kind: 'hint', text: "Couldn't check this link from the browser. That's common (the server may block browser checks, or the stream isn't live yet) and doesn't mean it's broken. The TV may still play it." })
    } finally {
      clearTimeout(timer)
      setTesting(false)
    }
  }

  return (
    <div className="stack-sm">
      <div className="note">Needs the Church TV OS app version 1.4.0 or newer on the TV.</div>
      <label className="field">
        <span>Title</span>
        <input value={slide.title ?? ''} onChange={(e) => patch({ title: e.target.value })} placeholder="e.g. Sunday service live" />
      </label>
      <div className="row wrap">
        <label className="field grow">
          <span>Stream link (HLS, .m3u8)</span>
          <input type="url" inputMode="url" value={slide.url} onChange={(e) => (patch({ url: e.target.value }), setResult(null))} placeholder="https://…/playlist.m3u8" />
        </label>
        <button type="button" className="btn align-end" onClick={test} disabled={testing || !slide.url.trim()}>
          {testing ? 'Testing…' : 'Test link'}
        </button>
      </div>
      {result && <p className={`test-result ${result.kind}`} role="status">{result.text}</p>}
      <div className="row wrap">
        <SecondsField value={slide.seconds} onChange={(seconds) => patch({ seconds })} label="Show for" />
        <label className="field">
          <span>If the stream is down</span>
          <select value={slide.fallback ?? 'skip'} onChange={(e) => patch({ fallback: e.target.value as 'skip' | 'hold' })}>
            <option value="skip">Skip it</option>
            <option value="hold">Show "waiting for feed"</option>
          </select>
        </label>
        <label className="check align-end">
          <input type="checkbox" checked={slide.audio ?? false} onChange={(e) => patch({ audio: e.target.checked })} />
          Play sound
        </label>
      </div>
      <p className="help">Sound is off unless you turn it on. BoxCast viewers run 30 to 40 seconds behind real life, so don't use a BoxCast link for anything that has to match the room.</p>
    </div>
  )
}

function NdiEditor({ slide, onChange }: Props<NdiSlide>) {
  const { org } = useApp()
  if (!org.ndi_enabled) return <p className="note warn">NDI sources are switched off for this church, so this slide is not shown on the TV and cannot be changed. You can delete it.</p>
  return <NdiFields value={slide} onPatch={(p) => onChange({ ...slide, ...p })} />
}

function BlankEditor({ slide, onChange }: Props<BlankSlide>) {
  return <ColorField label="Screen colour" value={slide.color ?? '#000000'} onChange={(color) => onChange({ ...slide, color })} />
}

/** The editor for whichever kind of slide is selected, plus its background and private notes. */
export default function SlideEditor({ slide, onChange, lib, songs, readOnly }: Props<DeckSlide> & { readOnly: boolean }) {
  const common = { lib, songs }
  const hasBackground = slide.kind !== 'blank' && slide.kind !== 'stream' && slide.kind !== 'ndi'
  return (
    <fieldset className="sl-fieldset stack" disabled={readOnly}>
      <legend className="sr-only">{KIND_NAME[slide.kind]} slide</legend>
      <div className="stack-sm">
        <span className="tag">{KIND_NAME[slide.kind]} slide</span>
        {slide.kind === 'text' && <TextEditor slide={slide} onChange={onChange} {...common} />}
        {slide.kind === 'media' && <MediaEditor slide={slide} onChange={onChange} {...common} />}
        {slide.kind === 'song' && <SongEditor slide={slide} onChange={onChange} {...common} />}
        {slide.kind === 'countdown' && <CountdownEditor slide={slide} onChange={onChange} {...common} />}
        {slide.kind === 'stream' && <StreamEditor slide={slide} onChange={onChange} {...common} />}
        {slide.kind === 'ndi' && <NdiEditor slide={slide} onChange={onChange} {...common} />}
        {slide.kind === 'blank' && <BlankEditor slide={slide} onChange={onChange} {...common} />}
      </div>
      {hasBackground && (
        <details className="sl-details" open={!!slide.background}>
          <summary>Background for this slide</summary>
          <div className="sl-details-body">
            <BackgroundPicker value={slide.background} onChange={(background) => onChange({ ...slide, background })} lib={lib} inheritLabel="Use deck/theme background" readOnly={readOnly} />
          </div>
        </details>
      )}
      <label className="field">
        <span>Private notes (never shown on the TV)</span>
        <textarea rows={2} value={slide.notes ?? ''} onChange={(e) => onChange({ ...slide, notes: e.target.value })} placeholder="Reminders for whoever runs the slides" />
      </label>
    </fieldset>
  )
}
