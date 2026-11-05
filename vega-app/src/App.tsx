// Church TV OS for Vega OS (Fire TV). Decides what the TV shows: pairing, a module (Kids, Signage, Slides), a play-now
// request from a remote, demo mode or Settings. Mirrors App() in tv-app MainActivity.kt.
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { Text, View } from 'react-native'
import { brandFor, parseHexColor, textColorOn } from './core/brand'
import { APP_VERSION, DASHBOARD_HOST } from './core/config'
import { demoSlides } from './core/demo'
import { deckHomeLabel, deckMediaUrls, itemKindLabel, isSupportedItem, playableDeckSlides, playlistMediaUrls, signageSlides, toSlides } from './core/model'
import { currentDeck, currentKids, moduleNow, Module, nextDeck, nextKids, signagePlaylistNow } from './core/modules'
import { Remote, type ActiveMessage } from './core/remote'
import { TvSync, type MediaStore, type TvUiState } from './core/sync'
import { formatWhen, isoMillis } from './core/time'
import type { Deck, DeviceState, OverrideInfo, Playlist } from './core/types'
import { fitFontSize } from './core/textFit'
import { createPlatform, useAppFonts, useKeepAwake, useRemoteKeys } from './platform'
import { Black, MessageScreen, SplashScreen } from './ui/common'
import { BrandProvider, FONT, NdiContext, TimeZoneContext, useDp, useScreen } from './ui/context'
import { HomeScreen } from './ui/HomeScreens'
import { Oriented } from './ui/Oriented'
import { PairingScreen } from './ui/PairingScreen'
import { PlayerScreen } from './ui/Player'
import { ConfirmUnpair, DemoMenu, SettingsScreen } from './ui/SettingsScreens'
import { SlidesPlayer } from './ui/SlidesPlayer'

function useStore<T>(store: { value: T; subscribe(l: (v: T) => void): () => void }): T {
  const [v, setV] = useState(store.value)
  useEffect(() => { setV(store.value); return store.subscribe(setV) }, [store])
  return v
}

/** Re-renders every [ms] so schedules and module rules switch on time. */
function useNow(ms: number): number {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms)
    return () => clearInterval(t)
  }, [ms])
  return now
}

const KIDS_HINT = 'OK or Play to start  ·  Left / Right to move between slides  ·  Back to stop'
const DECK_HINT = 'OK or Play to start  ·  Right / Left for next / back  ·  OK for the slide list  ·  Play/Pause for a black screen  ·  Back to stop'

function downloadStatus(state: TvUiState, ready: boolean, nothing: string | null): string {
  const base = nothing ?? (ready ? '✓ Ready to play'
    : state.downloading ? `Downloading media… ${state.downloading.done + 1} of ${state.downloading.total}`
      : state.failedDownloads > 0 ? "⚠ Some media couldn't download. Retrying…"
        : 'Preparing media…')
  return base + (state.offline ? '  ·  Offline, using saved schedule' : '')
}

/** The Kids curriculum player: shows what's scheduled and starts when someone presses Play (or by itself with autoplay). */
function KidsModule({ device, state, now, media }: { device: DeviceState; state: TvUiState; now: number; media: MediaStore }) {
  // Snapshot of the playlist when Play was pressed, so a sync mid-service can't change it.
  const [playing, setPlaying] = useState<Playlist | null>(null)
  const autoStartedFor = useRef<string | null>(null)
  const current = currentKids(device, now)
  const schedule = current ?? nextKids(device, now)
  const playlist = schedule?.playlist ?? null
  const ready = !!playlist && playlistMediaUrls(playlist).every((u) => media.has(u))
  const ndi = device.experimental.ndi === true

  useEffect(() => {
    if (device.screen.autoplay && current && ready && autoStartedFor.current !== current.id) {
      autoStartedFor.current = current.id
      setPlaying(current.playlist)
    }
  }, [current?.id, ready, device.screen.autoplay])

  if (playing) {
    return <PlayerScreen slides={toSlides(playing, ndi)} onExit={() => setPlaying(null)} report={{ module: 'kids', title: playing.name, refKind: 'playlist', refId: playing.id }} />
  }
  const rows = (playlist?.items ?? []).filter((i) => i.type !== 'unknown').map((i) => ({
    kind: itemKindLabel(i),
    label: (i.title ?? '') + (isSupportedItem(i, ndi) ? '' : '  (not on this TV)'),
  }))
  return (
    <HomeScreen
      site={device.site ?? ''}
      location={device.location ?? ''}
      heading={current ? 'NOW SHOWING' : schedule ? `UP NEXT · ${formatWhen(isoMillis(schedule.starts_at), device.timezone).toUpperCase()}` : 'NOTHING SCHEDULED'}
      title={playlist?.name ?? null}
      rows={rows}
      total={rows.length}
      status={downloadStatus(state, ready, playlist ? null : 'Schedule a playlist for this location in the dashboard.')}
      hint={KIDS_HINT}
      canPlay={ready}
      onPlay={() => playlist && setPlaying(playlist)}
    />
  )
}

/** Signage: loops whatever playlist is scheduled right now; black when nothing is. */
function SignageModule({ device, now, media }: { device: DeviceState; now: number; media: MediaStore }) {
  const playlist = signagePlaylistNow(device, now)
  const [loop, setLoop] = useState(0)
  // Only items whose files have finished downloading, so the loop never stalls on a missing file.
  const ready = playlist && {
    ...playlist,
    items: playlist.items.filter((i) => !((i.type === 'video' || i.type === 'image') && !media.has((i as { url: string }).url))),
  }
  const slides = useMemo(() => (ready ? signageSlides(ready, device.experimental.ndi === true) : []), [JSON.stringify(ready)])
  if (!ready || slides.length === 0) return <Black />
  // A new loop (or changed content) starts the playlist from the top.
  return <PlayerScreen key={`${ready.id}-${loop}-${slides.length}`} slides={slides} onExit={() => setLoop((n) => n + 1)} report={{ module: 'signage', title: ready.name }} />
}

/** The Slides module: shows the scheduled deck and plays it when Play is pressed. */
function SlidesModule({ device, state, now, media }: { device: DeviceState; state: TvUiState; now: number; media: MediaStore }) {
  const [playing, setPlaying] = useState<Deck | null>(null)
  const autoStartedFor = useRef<string | null>(null)
  const current = currentDeck(device, now)
  const schedule = current ?? nextDeck(device, now)
  const deck = schedule?.deck ?? null
  const ndi = device.experimental.ndi === true
  const playable = deck ? playableDeckSlides(deck, ndi) : []
  const ready = !!deck && deckMediaUrls(deck).every((u) => media.has(u)) && playable.length > 0

  useEffect(() => {
    if (device.screen.autoplay && current && ready && autoStartedFor.current !== current.id) {
      autoStartedFor.current = current.id
      setPlaying(current.deck)
    }
  }, [current?.id, ready, device.screen.autoplay])

  if (playing) return <SlidesPlayer deck={playing} onExit={() => setPlaying(null)} />
  const rows = playable.map((s) => {
    const [kind, label] = deckHomeLabel(s)
    return { kind, label }
  })
  return (
    <HomeScreen
      site={device.site ?? ''}
      location={device.location ?? ''}
      heading={current ? 'NOW SHOWING' : schedule ? `UP NEXT · ${formatWhen(isoMillis(schedule.starts_at), device.timezone).toUpperCase()}` : 'NOTHING SCHEDULED'}
      title={deck?.name ?? null}
      rows={rows}
      total={rows.length}
      status={downloadStatus(state, ready, !deck ? 'Schedule a deck for this location in the dashboard.' : playable.length === 0 ? 'This deck has no slides yet.' : null)}
      hint={DECK_HINT}
      canPlay={ready}
      onPlay={() => deck && setPlaying(deck)}
    />
  )
}

/** Waits (up to 30 s) for what a remote just sent to finish downloading, then plays it. */
function OverrideScreen({ override, state, media, onDone }: { override: OverrideInfo; state: TvUiState; media: MediaStore; onDone: () => void }) {
  const [waited, setWaited] = useState(0)
  const urls = override.deck ? deckMediaUrls(override.deck) : override.playlist ? playlistMediaUrls(override.playlist) : []
  const ready = urls.every((u) => media.has(u))
  useEffect(() => {
    if (ready || waited >= 30) return
    const t = setTimeout(() => setWaited((w) => w + 1), 1000)
    return () => clearTimeout(t)
  }, [ready, waited])
  if (!ready && waited < 30) return <MessageScreen title="Getting ready…" detail="Downloading what was just sent to this screen." />
  if (override.kind === 'deck' && override.deck) return <SlidesPlayer deck={override.deck} onExit={onDone} onFinished={onDone} />
  if (override.kind === 'playlist' && override.playlist) {
    const p = override.playlist
    return <PlayerScreen slides={toSlides(p, state.device?.experimental.ndi === true)} onExit={onDone} report={{ module: 'kids', title: p.name, refKind: 'playlist', refId: p.id }} />
  }
  return <MessageScreen title="Nothing to play" detail={state.error} />
}

/** A message sign covering everything for a while (sent from a remote). Clears itself. */
function MessageOverlay({ message }: { message: ActiveMessage }) {
  const dp = useDp()
  const { width, height } = useScreen()
  useEffect(() => {
    const t = setTimeout(() => { if (Remote.message.value === message) Remote.message.value = null }, Math.max(0, message.untilMs - Date.now()))
    return () => clearTimeout(t)
  }, [message])
  const bg = parseHexColor(message.background) ?? '#1B2A4A'
  const size = fitFontSize(message.text, { width: width - 128, height: height - 96, min: 24, max: 160, maxLines: 6, weight: 'black' })
  return (
    <View style={{ position: 'absolute', left: 0, top: 0, right: 0, bottom: 0, backgroundColor: bg, paddingHorizontal: dp(64), paddingVertical: dp(48), alignItems: 'center', justifyContent: 'center' }}>
      <Text numberOfLines={6} style={{ fontFamily: FONT.black, fontSize: dp(size), lineHeight: dp(size * 1.15), color: textColorOn(bg), textAlign: 'center' }}>
        {message.text}
      </Text>
    </View>
  )
}

/** The module screen with its own look and its splash when the TV starts or switches into it. */
function ModuleScreen({ device, state, now, media }: { device: DeviceState; state: TvUiState; now: number; media: MediaStore }) {
  const module = moduleNow(device, now)
  const brand = brandFor(device, module)
  const [splashFor, setSplashFor] = useState<string | null>(brand.splashSeconds !== null && module !== Module.OFF ? module : null)
  useEffect(() => {
    if (brand.splashSeconds === null || module === Module.OFF) { setSplashFor(null); return }
    setSplashFor(module)
    const t = setTimeout(() => setSplashFor(null), brand.splashSeconds * 1000)
    return () => clearTimeout(t)
  }, [module])
  let screen: React.ReactNode
  if (splashFor === module) screen = <SplashScreen />
  else if (module === Module.OFF) screen = <Black />
  else if (!device.enabled_modules.includes(module)) {
    screen = (
      <MessageScreen
        title={`This screen is set to ${module.charAt(0).toUpperCase()}${module.slice(1)}`}
        detail={`That module isn't switched on for ${device.organization?.name ?? 'this church'}. Ask your church's admin.`}
      />
    )
  } else if (module === Module.SIGNAGE) screen = <SignageModule device={device} now={now} media={media} />
  else if (module === Module.SLIDES) screen = <SlidesModule device={device} state={state} now={now} media={media} />
  else screen = <KidsModule device={device} state={state} now={now} media={media} />
  return <BrandProvider brand={brand}>{screen}</BrandProvider>
}

function Root({ sync, media }: { sync: TvSync; media: MediaStore }) {
  const state = useStore(sync.state)
  const message = useStore(Remote.message)
  const now = useNow(15_000)
  const device = state.device
  const [settings, setSettings] = useState(false)
  const [demoMenu, setDemoMenu] = useState(false)
  const [demo, setDemo] = useState<'kids' | 'signage' | null>(null)
  const [demoLoop, setDemoLoop] = useState(0)
  const [confirmUnpair, setConfirmUnpair] = useState(false)
  // A play-now request ends when it times out, finishes, or someone stops it (Stop or Back).
  const [dismissedUntil, setDismissedUntil] = useState<string | null>(null)
  const overrideRef = useRef<OverrideInfo | null | undefined>(null)
  overrideRef.current = device?.override

  useEffect(() => Remote.onCommand((c) => {
    if (c.type === 'message') Remote.message.value = { text: c.text, background: c.background, untilMs: Date.now() + c.seconds * 1000 }
    else if (c.type === 'clear_message') Remote.message.value = null
    else if (c.type === 'stop') setDismissedUntil(overrideRef.current?.until ?? null)
  }), [])

  // Menu opens (and closes) Settings from anywhere; so does holding OK for a second, for remotes without Menu.
  const selectDownAt = useRef(0)
  const longPressDone = useRef(false)
  useRemoteKeys((key, repeat) => {
    if (key === 'menu' && !repeat) { setSettings((s) => !s); return true }
    if (key === 'select') {
      if (!repeat) { selectDownAt.current = Date.now(); longPressDone.current = false }
      else if (!longPressDone.current && Date.now() - selectDownAt.current >= 1000) {
        longPressDone.current = true
        setSettings((s) => !s)
        return true
      }
    }
    return false
  })

  // Every screen stays awake (pairing, home screens, black signage gaps), as the Android app's keep-screen-on does.
  useKeepAwake()

  const zone = device?.timezone ?? 'America/Toronto'
  const override = device?.override
  const overrideActive = !!override && override.until !== dismissedUntil && isoMillis(override.until) > now

  let screen: React.ReactNode
  if (demo) {
    screen = <PlayerScreen key={`${demo}-${demoLoop}`} slides={demoSlides(demo)} onExit={() => setDemo(null)} onFinished={() => setDemoLoop((n) => n + 1)} />
  } else if (demoMenu) {
    screen = <DemoMenu onPick={(w) => { setDemo(w); setDemoMenu(false); setSettings(false) }} onClose={() => setDemoMenu(false)} />
  } else if (confirmUnpair) {
    screen = <ConfirmUnpair onNo={() => setConfirmUnpair(false)} onYes={() => { setConfirmUnpair(false); setSettings(false); void sync.reset() }} />
  } else if (settings) {
    screen = (
      <SettingsScreen
        paired={device?.paired === true}
        detail={`Version ${APP_VERSION}${device?.screen.name ? `  ·  ${device.screen.name}` : ''}  ·  ${DASHBOARD_HOST}  ·  TV ${sync.id.slice(0, 8)}`}
        onDemo={() => setDemoMenu(true)}
        onUnpair={() => setConfirmUnpair(true)}
        onClose={() => setSettings(false)}
      />
    )
  } else if (!device) screen = <MessageScreen title="Connecting…" detail={state.error} />
  else if (!device.paired) screen = <PairingScreen code={device.pairing_code ?? '······'} offline={state.offline} onSettings={() => setSettings(true)} />
  else if (device.organization?.status === 'suspended') {
    screen = <MessageScreen title="This account is paused" detail="Please ask your church's administrator to contact Church TV OS support." />
  } else if (overrideActive && override) {
    screen = <OverrideScreen key={override.until} override={override} state={state} media={media} onDone={() => setDismissedUntil(override.until)} />
  } else screen = <ModuleScreen device={device} state={state} now={now} media={media} />

  return (
    <TimeZoneContext.Provider value={zone}>
      <NdiContext.Provider value={device?.experimental.ndi === true}>
        <BrandProvider brand={brandFor(device)}>
          <Oriented orientation={device?.screen.orientation ?? 'landscape'}>
            {screen}
            {message ? <MessageOverlay message={message} /> : null}
          </Oriented>
        </BrandProvider>
      </NdiContext.Provider>
    </TimeZoneContext.Provider>
  )
}

export default function App() {
  const fontsLoaded = useAppFonts()
  const [boot, setBoot] = useState<{ sync: TvSync; media: MediaStore } | null>(null)
  useEffect(() => {
    let sync: TvSync | null = null
    ;(async () => {
      const platform = await createPlatform()
      sync = new TvSync(platform)
      await sync.init()
      setBoot({ sync, media: platform.media })
      void sync.run()
      void sync.runRemote()
    })()
    return () => sync?.stop()
  }, [])
  if (!boot || !fontsLoaded) return <View style={{ flex: 1, backgroundColor: '#FFFFFF' }} />
  return <Root sync={boot.sync} media={boot.media} />
}
