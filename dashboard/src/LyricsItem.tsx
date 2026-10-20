import { useMemo, useRef, useState } from 'react'
import type { LyricsItem, Song } from './types'
import { expandSong } from './songParsers'

/** The parts of a library song the playlist editor needs. */
export type SongLite = Pick<Song, 'id' | 'title' | 'sections' | 'arrangement' | 'lines_per_slide'>

export const newLyricsItem = (): LyricsItem => ({ type: 'lyrics', title: '', slides: [], show_title: false })

export const isLibraryLyrics = (item: LyricsItem): item is Extract<LyricsItem, { song_id: string }> => 'song_id' in item

/** A lyrics playlist item: words from the shared song library, or typed by hand (the original editor). */
export function LyricsItemEditor({ item, songs, onChange }: { item: LyricsItem; songs: SongLite[]; onChange: (next: LyricsItem) => void }) {
  const fromLibrary = isLibraryLyrics(item)
  const [search, setSearch] = useState('')
  // Switching source back and forth keeps what was there.
  const stash = useRef<{ slides: string[]; title: string; songId: string; songTitle: string }>({
    slides: 'slides' in item ? item.slides : [],
    title: 'slides' in item ? item.title : '',
    songId: 'song_id' in item ? item.song_id : '',
    songTitle: 'song_id' in item ? item.title : '',
  })
  const showTitle = item.show_title ?? false

  function setSource(lib: boolean) {
    if (lib === fromLibrary) return
    if (isLibraryLyrics(item)) {
      stash.current.songId = item.song_id
      stash.current.songTitle = item.title
      onChange({ type: 'lyrics', title: stash.current.title, slides: stash.current.slides, show_title: item.show_title })
    } else {
      stash.current.slides = item.slides
      stash.current.title = item.title
      onChange({ type: 'lyrics', title: stash.current.songTitle, song_id: stash.current.songId, show_title: item.show_title })
    }
  }

  const song = isLibraryLyrics(item) ? songs.find((s) => s.id === item.song_id) : undefined
  const slideCount = useMemo(() => (song ? expandSong(song).length : 0), [song])
  const q = search.trim().toLowerCase()
  const options = songs.filter((s) => !q || s.title.toLowerCase().includes(q) || s.id === (isLibraryLyrics(item) ? item.song_id : ''))

  return (
    <div className="stack-sm">
      <div className="segmented" role="group" aria-label="Where the words come from">
        <button type="button" className={fromLibrary ? 'on' : ''} onClick={() => setSource(true)}>
          From song library
        </button>
        <button type="button" className={!fromLibrary ? 'on' : ''} onClick={() => setSource(false)}>
          Typed lyrics
        </button>
      </div>

      {isLibraryLyrics(item) ? (
        <>
          <div className="row wrap">
            <label className="field grow">
              <span>Search songs</span>
              <input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Start typing a song title" />
            </label>
            <label className="field grow">
              <span>Song</span>
              <select
                value={item.song_id}
                onChange={(e) => {
                  const s = songs.find((x) => x.id === e.target.value)
                  onChange({ ...item, song_id: e.target.value, title: s?.title ?? '' })
                }}
              >
                <option value="">Choose a song…</option>
                {item.song_id && !song && <option value={item.song_id}>(song no longer in the library)</option>}
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
            <span className="muted">
              {slideCount} {slideCount === 1 ? 'slide' : 'slides'} ·{' '}
              <a href="/#songs" target="_blank" rel="noreferrer">
                Edit this song
              </a>{' '}
              (opens in a new tab; the playlist uses the latest version)
            </span>
          )}
          {item.song_id && !song && <p className="note warn">This song isn't in the library any more, so the TV will skip this item. Choose another song.</p>}
        </>
      ) : (
        <>
          <label className="field">
            <span>Song title</span>
            <input value={item.title} onChange={(e) => onChange({ ...item, title: e.target.value })} />
          </label>
          <label className="field">
            <span>Lyrics · leave a blank line between slides</span>
            <textarea rows={8} value={item.slides.join('\n\n')} onChange={(e) => onChange({ ...item, slides: e.target.value.split(/\n[ \t]*\n/) })} />
          </label>
          <span className="muted">{item.slides.filter((s) => s.trim()).length} slides</span>
        </>
      )}

      <label className="check">
        <input type="checkbox" checked={showTitle} onChange={(e) => onChange({ ...item, show_title: e.target.checked })} />
        Show song title first
      </label>
      <p className="help">Shows the song name as its own slide before the words. It stays up until you press Next.</p>
      <p className="note">Styled title slide needs app version 1.3.0 or newer; older TVs show a plain first slide.</p>
    </div>
  )
}
