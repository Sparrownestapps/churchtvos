// Off-device tests for the platform-neutral core. Run: npm test
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'

import { normalizeState } from '../src/core/types'
import { currentKids, moduleNow, nextKids, signagePlaylistNow } from '../src/core/modules'
import { deckMediaUrls, playableDeckSlides, signageSlides, slideLabel, toSlides } from '../src/core/model'
import { countdownEnd, fadeFactor, formatCountdown, untilMillis } from '../src/core/countdown'
import { parseCommand, Remote } from '../src/core/remote'
import { brandFor, logoOn, pairingQrPayload, parseHexColor, textColorOn } from '../src/core/brand'
import { cacheName } from '../src/core/cacheName'
import { formatWhen, zonedParts } from '../src/core/time'
import { toStyle } from '../src/core/slideStyle'
import { neededMediaUrls, TvSync, uuidFrom, type Platform } from '../src/core/sync'
import type { Api } from '../src/core/api'

const TZ = 'America/Toronto'
// Sunday 2026-11-08, 9:30am Toronto (EST, UTC-5)
const SUN_930 = Date.parse('2026-11-08T14:30:00Z')
// Tuesday 2026-11-10, 9:30am Toronto
const TUE_930 = Date.parse('2026-11-10T14:30:00Z')

const pl = (id: string, items: unknown[] = []) => ({ id, name: `Playlist ${id}`, items }) as any

test('normalizeState fills in defaults', () => {
  const d = normalizeState({ paired: true })
  assert.equal(d.timezone, TZ)
  assert.equal(d.default_module, 'kids')
  assert.equal(d.screen.orientation, 'landscape')
  assert.deepEqual(d.kids.schedules, [])
  assert.equal(normalizeState(null).paired, false)
})

test('zonedParts and formatWhen use the site time zone', () => {
  const p = zonedParts(SUN_930, TZ)
  assert.deepEqual([p.weekday, p.hour, p.minute], [0, 9, 30])
  assert.equal(formatWhen(SUN_930, TZ), 'Sun Nov 8 · 9:30 AM')
  assert.equal(zonedParts(SUN_930, 'Australia/Sydney').weekday, 1)
})

test('moduleNow: matching rule, priority, later rule wins ties, default otherwise', () => {
  const d = normalizeState({
    paired: true,
    default_module: 'signage',
    module_rules: [
      { module: 'kids', days: [0], start: '08:00', end: '13:00', priority: 0 },
      { module: 'slides', days: [0], start: '09:00', end: '10:00', priority: 0 },
      { module: 'off', days: [2], start: '09:00', end: '09:30', priority: 5 },
    ],
  })
  assert.equal(moduleNow(d, SUN_930), 'slides')
  assert.equal(moduleNow(d, SUN_930 + 3600_000), 'kids')
  assert.equal(moduleNow(d, TUE_930 - 60_000), 'off')
  assert.equal(moduleNow(d, TUE_930), 'signage') // end is exclusive
})

test('signage: matching slot, else the default playlist, else black', () => {
  const d = normalizeState({
    signage: {
      slots: [{ id: 's1', days: [0], start: '09:00', end: '12:00', playlist: pl('slot') }],
      default_playlist: pl('default'),
    },
  })
  assert.equal(signagePlaylistNow(d, SUN_930)?.id, 'slot')
  assert.equal(signagePlaylistNow(d, TUE_930)?.id, 'default')
  assert.equal(signagePlaylistNow(normalizeState({}), TUE_930), null)
})

test('kids schedules: latest started is current; earliest future is next', () => {
  const d = normalizeState({
    kids: {
      schedules: [
        { id: 'a', starts_at: '2026-11-08T08:00:00-05:00', ends_at: '2026-11-08T12:00:00-05:00', playlist: pl('a') },
        { id: 'b', starts_at: '2026-11-08T09:00:00-05:00', ends_at: null, playlist: pl('b') },
        { id: 'c', starts_at: '2026-11-15T09:00:00-05:00', playlist: pl('c') },
        { id: 'd', starts_at: '2026-11-12T09:00:00-05:00', playlist: pl('d') },
      ],
    },
  })
  assert.equal(currentKids(d, SUN_930)?.id, 'b')
  assert.equal(nextKids(d, SUN_930)?.id, 'd')
})

test('toSlides expands lyrics, skips YouTube and unknown types, NDI only as a message for flagged churches', () => {
  const p = pl('x', [
    { type: 'countdown', title: 'Starts in', seconds: 300 },
    { type: 'lyrics', title: 'Song', slides: ['one', 'two'], show_title: true, ccli: '123' },
    { type: 'youtube', title: 'yt', video_id: 'abc' },
    { type: 'hologram', title: 'future' },
    { type: 'ndi', title: 'Cam', fallback: 'message', fallback_text: 'Back soon' },
    { type: 'ndi', title: 'Cam2', fallback: 'skip' },
    { type: 'image', title: 'pic', url: 'https://x/p.png' },
  ])
  const off = toSlides(p, false)
  assert.deepEqual(off.map((s) => s.kind), ['countdown', 'song_title', 'lyric', 'lyric', 'image'])
  assert.equal(slideLabel(off[2]), 'Song · Part 1 of 2')
  const on = toSlides(p, true)
  assert.deepEqual(on.map((s) => s.kind), ['countdown', 'song_title', 'lyric', 'lyric', 'notice', 'image'])
  const sig = signageSlides(p, true)
  assert.equal((sig.find((s) => s.kind === 'image') as any).seconds, 10)
  assert.equal((sig.find((s) => s.kind === 'notice') as any).seconds, 30)
})

test('deck media and playable slides', () => {
  const deck = {
    id: 'd', name: 'Deck',
    background: { type: 'image', url: 'https://x/bg.jpg' },
    theme: { background: { type: 'video', url: 'https://x/loop.mp4' } },
    slides: [
      { kind: 'media', url: 'https://x/bg.jpg' },
      { kind: 'countdown', audio: { url: 'https://x/music.mp3' } },
      { kind: 'text', title: 'Hi', background: { type: 'color', color: '#000' } },
      { kind: 'ndi', fallback: 'skip' },
      { kind: 'sparkles' },
    ],
  } as any
  assert.deepEqual(deckMediaUrls(deck), ['https://x/bg.jpg', 'https://x/loop.mp4', 'https://x/music.mp3'])
  assert.deepEqual(playableDeckSlides(deck, true).map((s) => s.kind), ['media', 'countdown', 'text'])
})

test('countdowns: until in the site zone across the DST change, formatting, fade', () => {
  // 2026-11-01 is the day clocks go back in Toronto.
  const noonSat = Date.parse('2026-10-31T16:00:00Z') // EDT
  const noonSun = Date.parse('2026-11-01T17:00:00Z') // EST
  assert.equal(new Date(untilMillis('13:00', noonSat, TZ)!).toISOString(), '2026-10-31T17:00:00.000Z')
  assert.equal(new Date(untilMillis('13:00', noonSun, TZ)!).toISOString(), '2026-11-01T18:00:00.000Z')
  assert.equal(untilMillis('nope', noonSun, TZ), null)
  assert.equal(countdownEnd({ mode: 'duration', seconds: 90, until: null, audio: null, atZero: 'next', ifPassed: 'zero' }, 1000, TZ), 91_000)
  assert.equal(formatCountdown(300_000), '5:00')
  assert.equal(formatCountdown(6_001), '0:07')
  assert.equal(formatCountdown(3_900_000), '1:05:00')
  assert.equal(formatCountdown(-5), '0:00')
  assert.equal(fadeFactor(1500, 3), 0.5)
  assert.equal(fadeFactor(10_000, 3), 1)
})

test('remote commands: known ones parse, bad or unknown ones are ignored', () => {
  assert.deepEqual(parseCommand({ command: 'jump', payload: { index: 3 } }), { type: 'jump', index: 3 })
  assert.equal(parseCommand({ command: 'jump', payload: {} }), null)
  assert.deepEqual(parseCommand({ command: 'blank', payload: {} }), { type: 'blank', on: null })
  assert.deepEqual(parseCommand({ command: 'message', payload: { text: 'Hi', seconds: 999 } }), {
    type: 'message', text: 'Hi', seconds: 300, background: '#1B2A4A',
  })
  assert.equal(parseCommand({ command: 'message', payload: { text: '  ' } }), null)
  assert.equal(parseCommand({ command: 'self_destruct' }), null)
})

test('branding: module overrides, splash clamp, colours, logos, QR payload', () => {
  const d = normalizeState({
    organization: {
      name: 'Grace',
      branding: { primary_color: '#112233', logo_url: 'L', logo_dark_url: 'D', splash: { enabled: true, seconds: 99 }, modules: { kids: { primary_color: '#ff0000' } } },
    },
  })
  assert.equal(brandFor(d).primary, '#112233')
  assert.equal(brandFor(d, 'kids').primary, '#FF0000')
  assert.equal(brandFor(d).splashSeconds, 30)
  assert.equal(brandFor(null).primary, '#1B2A4A')
  assert.equal(textColorOn('#FFFFFF'), '#111111')
  assert.equal(textColorOn('#1B2A4A'), '#FFFFFF')
  assert.equal(logoOn(brandFor(d), '#000000'), 'D')
  assert.equal(logoOn(brandFor(d), '#FFFFFF'), 'L')
  assert.equal(parseHexColor('#80FF0000'), 'rgba(255,0,0,0.502)')
  assert.equal(parseHexColor('red'), null)
  assert.equal(pairingQrPayload('ab c12 3'), 'https://app.churchtvos.com/pair?code=ABC123')
  assert.equal(pairingQrPayload('······'), null)
})

test('slide style clamps and falls back', () => {
  const s = toStyle({ title_scale: 9, outline: true, align: 'left', margin: 50 }, null, '#000')
  assert.deepEqual([s.titleScale, s.shadow, s.center, s.marginPct, s.color], [1.5, 'outline', false, 20, '#000000'])
  assert.equal(toStyle(undefined).color, '#FFFFFF')
})

test('cache names match the Android app (SHA-1 of the URL plus extension)', () => {
  for (const url of ['https://x.supabase.co/storage/v1/object/public/media/a/b.mp4?token=1', 'https://x/é ü/file', 'https://x/a.longext']) {
    const hash = createHash('sha1').update(url, 'utf8').digest('hex')
    const name = cacheName(url)
    assert.ok(name.startsWith(hash), url)
  }
  assert.match(cacheName('https://x/v.mp4?x=1'), /^[0-9a-f]{40}\.mp4$/)
  assert.match(cacheName('https://x/a.longext'), /^[0-9a-f]{40}$/)
})

test('uuidFrom makes a version 4 UUID', () => {
  assert.match(uuidFrom(new Uint8Array(16).fill(255)), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
})

test('neededMediaUrls covers kids, signage, slides and the override, without repeats', () => {
  const d = normalizeState({
    kids: { schedules: [{ id: 'k', starts_at: '2026-11-08T09:00:00-05:00', playlist: pl('k', [{ type: 'video', url: 'https://x/v.mp4' }]) }] },
    signage: { slots: [], default_playlist: pl('s', [{ type: 'image', url: 'https://x/v.mp4' }, { type: 'image', url: 'https://x/i.png' }]) },
    override: { kind: 'deck', until: '2026-11-08T12:00:00-05:00', deck: { id: 'o', name: 'o', slides: [{ kind: 'media', url: 'https://x/o.png' }] } },
  })
  assert.deepEqual(neededMediaUrls(d), ['https://x/v.mp4', 'https://x/i.png', 'https://x/o.png'])
})

function fakePlatform(): Platform & { files: Set<string>; store: Map<string, string> } {
  const store = new Map<string, string>()
  const files = new Set<string>()
  return {
    store, files,
    kv: {
      get: async (k) => store.get(k) ?? null,
      set: async (k, v) => { store.set(k, v) },
      clear: async () => { store.clear() },
    },
    media: {
      has: (u) => files.has(u),
      download: async (u) => { if (u.includes('broken')) throw new Error('404'); files.add(u) },
      prune: async (keep) => { for (const f of [...files]) if (!keep.includes(f)) files.delete(f) },
    },
    model: 'Fire TV Stick 4K Select',
    appVersion: '1.7.0-vega',
    randomBytes: (n) => new Uint8Array(n).map((_, i) => i * 7),
    sleep: () => new Promise((r) => setTimeout(r, 0)),
    now: () => Date.now(),
  }
}

test('TvSync registers, saves the state, downloads media and reports remote status', async () => {
  const calls: string[] = []
  const state = {
    paired: true,
    signage: { slots: [], default_playlist: pl('s', [{ type: 'image', url: 'https://x/ok.png' }, { type: 'image', url: 'https://x/broken.png' }]) },
  }
  const api = {
    registerDevice: async (_id: string, _s: string, model: string, version: string) => { calls.push(`register ${model} ${version}`); return '' },
    deviceState: async () => { calls.push('state'); return JSON.stringify(state) },
    pollCommands: async () => { calls.push('poll'); return JSON.stringify([{ command: 'next' }, { command: 'bogus' }]) },
    reportStatus: async (_i: string, _s: string, st: { state: string }) => { calls.push(`report ${st.state}`); return '' },
  } as unknown as Api
  const p = fakePlatform()
  const sync = new TvSync(p, api)
  await sync.init()
  assert.match(sync.id, /^[0-9a-f-]{36}$/)
  assert.equal(p.store.get('secret')?.length, 64)

  const seen: string[] = []
  const off = Remote.onCommand((c) => seen.push(c.type))
  const running = sync.run()
  const remote = sync.runRemote()
  while (!calls.includes('report idle')) await new Promise((r) => setTimeout(r, 1))
  sync.stop()
  await Promise.all([running, remote])
  off()

  assert.equal(calls[0], 'register Fire TV Stick 4K Select 1.7.0-vega')
  assert.ok(p.files.has('https://x/ok.png'))
  assert.equal(sync.state.value.failedDownloads, 1)
  assert.equal(sync.state.value.device?.paired, true)
  assert.ok(p.store.get('state'))
  assert.deepEqual(seen, ['next'])
})

test('TvSync starts over when the server no longer knows the TV', async () => {
  const p = fakePlatform()
  let first = true
  const api = {
    registerDevice: async () => '',
    deviceState: async () => {
      if (first) { first = false; throw new Error('Server error 400: Unknown device') }
      return JSON.stringify({ paired: false, pairing_code: 'ABC123' })
    },
  } as unknown as Api
  const sync = new TvSync(p, api)
  await sync.init()
  await p.kv.set('state', '{"paired":true}')
  const running = sync.run()
  while (sync.state.value.device?.pairing_code !== 'ABC123') await new Promise((r) => setTimeout(r, 1))
  sync.stop()
  await running
  assert.equal(sync.state.value.device?.paired, false)
  assert.ok(p.store.get('device_id'), 'a new identity was created')
  assert.notEqual(p.store.get('state'), '{"paired":true}', 'the old saved state was dropped')
})

import { fitFontSize, lineCount } from '../src/core/textFit'

test('text fit: wraps words, honours line limits and the box height', () => {
  assert.equal(lineCount('one two three', 10, 1000, 'regular'), 1)
  assert.equal(lineCount('aaaa bbbb', 10, 25, 'regular'), 2) // 5 chars per line
  assert.equal(lineCount('aaaaaaaaaaaa', 10, 25, 'regular'), 3) // one long word broken in three
  assert.equal(lineCount('a\nb', 10, 1000, 'regular'), 2)
  const big = fitFontSize('Welcome', { width: 1600, height: 600, min: 28, max: 160, maxLines: 3, weight: 'black' })
  assert.equal(big, 160)
  const long = 'Amazing grace how sweet the sound that saved a wretch like me I once was lost but now am found was blind but now I see'
  const s = fitFontSize(long, { width: 1600, height: 600, min: 24, max: 172, maxLines: 8, weight: 'bold' })
  assert.ok(s < 172 && s >= 24)
  assert.ok(lineCount(long, s, 1600, 'bold') * s * 1.15 <= 600)
})
