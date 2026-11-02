// Plays a deck from the TV remote: Right = next, Left = back, OK = slide list (jump anywhere), Play/Pause = black screen,
// Back = stop. Mirrors tv-app SlidesPlayer.kt and SlideViews.kt.
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { FlatList, Image, Text, View } from 'react-native'
import { isLight, logoOn, parseHexColor, withAlpha } from '../core/brand'
import { countdownSpec, deckSlideLabel, playableDeckSlides, resolveBackground } from '../core/model'
import { Remote } from '../core/remote'
import { toStyle, type SlideStyle } from '../core/slideStyle'
import type { Deck, DeckSlide, SlideBackground } from '../core/types'
import { useBack, useKeepAwake, useRemoteKeys, VideoView, localUri } from '../platform'
import { FitText } from './FitText'
import { TvButton } from './common'
import { FONT, useBrand, useDp, useNdiFlag, useScreen } from './context'
import { CountdownRunner, NoticeView, Picture, shadowStyle, SongTitleView } from './slides'

const DEFAULT_BG = '#1B2A4A'
const FILL = { position: 'absolute', left: 0, top: 0, right: 0, bottom: 0 } as const

/** Mixes two "#RRGGBB" colours. */
function mix(a: string, b: string, t: number): string {
  const p = (h: string, i: number) => parseInt(h.slice(i, i + 2), 16)
  const c = (i: number) => Math.round(p(a, i) + (p(b, i) - p(a, i)) * t).toString(16).padStart(2, '0')
  return `#${c(1)}${c(3)}${c(5)}`
}

/** A CSS-style linear gradient (0 = to top, 90 = to right, 180 = to bottom) from bands, turned and oversized to cover. */
function Gradient({ from, to, angle }: { from: string; to: string; angle: number }) {
  const { width, height } = useScreen()
  const dp = useDp()
  const bands = 48
  const side = Math.hypot(width, height)
  const a = from.startsWith('#') && from.length === 7 ? from : DEFAULT_BG
  const b = to.startsWith('#') && to.length === 7 ? to : '#000000'
  return (
    <View style={[FILL, { overflow: 'hidden' }]}>
      <View
        style={{
          position: 'absolute', width: dp(side), height: dp(side),
          left: dp((width - side) / 2), top: dp((height - side) / 2),
          transform: [{ rotate: `${angle - 180}deg` }],
        }}
      >
        {Array.from({ length: bands }, (_, i) => (
          <View key={i} style={{ flex: 1, backgroundColor: mix(a, b, i / (bands - 1)) }} />
        ))}
      </View>
    </View>
  )
}

/** The background layers: colour or gradient, a picture, or a looping video, plus the dimming overlay. */
function BackgroundLayer({ bg }: { bg: SlideBackground | null }) {
  const brand = useBrand()
  const b = bg as (SlideBackground & Record<string, any>) | null
  let layer: React.ReactNode
  if (!b) layer = <View style={[FILL, { backgroundColor: brand.primary }]} />
  else if (b.type === 'color') layer = <View style={[FILL, { backgroundColor: parseHexColor(b.color) ?? DEFAULT_BG }]} />
  else if (b.type === 'gradient') layer = <Gradient from={parseHexColor(b.color) ?? DEFAULT_BG} to={parseHexColor(b.color2) ?? '#000000'} angle={b.angle ?? 180} />
  else if (b.type === 'image') {
    layer = (
      <>
        <View style={[FILL, { backgroundColor: parseHexColor(b.color) ?? '#000000' }]} />
        <Picture url={b.url} fit={b.fit === 'contain' ? 'contain' : 'cover'} />
      </>
    )
  } else {
    layer = (
      <>
        <View style={[FILL, { backgroundColor: parseHexColor(b.color) ?? '#000000' }]} />
        <VideoView uri={localUri(b.url)} loop volume={0} fit={b.fit === 'contain' ? 'contain' : 'cover'} />
      </>
    )
  }
  const dim = Math.min(0.8, Math.max(0, b?.dim ?? 0))
  return (
    <>
      {layer}
      {dim > 0 ? <View style={[FILL, { backgroundColor: `rgba(0,0,0,${dim})` }]} /> : null}
    </>
  )
}

const justify = (position: string) => (position === 'top' ? 'flex-start' : position === 'lower' ? 'flex-end' : 'center')

/** Title and body text. Layouts: title_body, title, body, lower_third. */
function TextSlideView({ slide, style }: { slide: Record<string, any>; style: SlideStyle }) {
  const dp = useDp()
  const { width, height } = useScreen()
  const shadow = shadowStyle(style, dp)
  const hasTitle = !!slide.title?.trim() && slide.layout !== 'body'
  const hasBody = !!slide.body?.trim() && slide.layout !== 'title'
  const align = style.center ? 'center' : 'left'
  const titleWeight = style.titleFont === 'julius' ? 'julius' : 'black'
  if (slide.layout === 'lower_third') {
    const padH = Math.max(24, width * (style.marginPct / 100))
    const w = width - 2 * padH
    return (
      <View style={{ position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(0,0,0,0.45)', paddingHorizontal: dp(padH), paddingVertical: dp(16) }}>
        {hasTitle ? <FitText text={slide.title} width={w} height={height * 0.14} min={20} max={70 * style.titleScale} maxLines={1} weight={titleWeight} color={style.color} align={align} vertical="bottom" style={shadow} /> : null}
        {hasBody ? <FitText text={slide.body} width={w} height={height * 0.12} min={16} max={40 * style.bodyScale} maxLines={2} weight="regular" color={style.color} align={align} vertical="top" style={shadow} /> : null}
      </View>
    )
  }
  const padH = width * (style.marginPct / 100)
  const padV = height * (style.marginPct / 100)
  const shrink = Math.max(0.6, 1 - (2 * style.marginPct) / 100)
  const w = width - 2 * padH
  return (
    <View style={[FILL, { paddingHorizontal: dp(padH), paddingVertical: dp(padV), justifyContent: justify(style.position), alignItems: style.center ? 'center' : 'flex-start' }]}>
      {hasTitle ? (
        <FitText text={slide.title} width={w} height={height * (hasBody ? 0.34 : 0.6) * shrink} min={28} max={150 * style.titleScale} maxLines={3} weight={titleWeight} color={style.color} align={align} vertical="bottom" style={shadow} />
      ) : null}
      {hasTitle && hasBody ? <View style={{ height: dp(height * 0.02) }} /> : null}
      {hasBody ? (
        <FitText text={slide.body} width={w} height={height * (hasTitle ? 0.38 : 0.7) * shrink} min={20} max={72 * style.bodyScale} maxLines={12} weight="regular" color={style.color} align={align} vertical={hasTitle ? 'top' : 'center'} style={shadow} />
      ) : null}
    </View>
  )
}

/** One section of a song's words. */
function LyricSlideView({ slide, style }: { slide: Record<string, any>; style: SlideStyle }) {
  const dp = useDp()
  const { width, height } = useScreen()
  const shadow = shadowStyle(style, dp)
  const padH = width * (style.marginPct / 100)
  const padV = height * (style.marginPct / 100)
  return (
    <View style={FILL}>
      <View style={[FILL, { paddingHorizontal: dp(padH), paddingVertical: dp(padV), justifyContent: justify(style.position), alignItems: style.center ? 'center' : 'flex-start' }]}>
        {style.showLabels && slide.label?.trim() ? (
          <Text style={[{ fontFamily: FONT.bold, fontSize: dp(18), letterSpacing: dp(3), color: withAlpha(style.color, 0.7), marginBottom: dp(12), textAlign: style.center ? 'center' : 'left' }, shadow]}>
            {slide.label.toUpperCase()}
          </Text>
        ) : null}
        <FitText text={slide.text} width={width - 2 * padH} height={height * 0.62} min={24} max={86 * style.bodyScale} maxLines={8} weight="bold" color={style.color} align={style.center ? 'center' : 'left'} style={shadow} />
      </View>
      <Text style={[{ position: 'absolute', right: dp(48), bottom: dp(27), fontFamily: FONT.regular, fontSize: dp(12), color: withAlpha(style.color, 0.6) }, shadow]}>
        {`${slide.song ?? ''}  ·  ${slide.number ?? 1}/${slide.count ?? 1}`}
      </Text>
    </View>
  )
}

function DeckCountdown({ slide, style, paused, onDone }: { slide: Record<string, any>; style: SlideStyle; paused: boolean; onDone: () => void }) {
  const dp = useDp()
  const brand = useBrand()
  const shadow = shadowStyle(style, dp)
  return (
    <CountdownRunner
      spec={countdownSpec(slide)}
      paused={paused}
      onFinished={onDone}
      render={(time) => (
        <View style={[FILL, { alignItems: 'center', justifyContent: 'center' }]}>
          {slide.title?.trim() ? (
            <Text style={[{ fontFamily: FONT.bold, fontSize: dp(22), letterSpacing: dp(4), color: brand.accent }, shadow]}>{slide.title.toUpperCase()}</Text>
          ) : null}
          <Text style={[{ fontFamily: FONT.julius, fontSize: dp(160 * style.titleScale), color: style.color }, shadow]}>{time}</Text>
        </View>
      )}
    />
  )
}

/** Jump to any slide: Up/Down to choose, OK to go, Back to close. */
function SlideList({ slides, current, onPick, onClose }: { slides: DeckSlide[]; current: number; onPick: (i: number) => void; onClose: () => void }) {
  const dp = useDp()
  useBack(() => { onClose(); return true })
  return (
    <View style={[FILL, { backgroundColor: 'rgba(0,0,0,0.82)', alignItems: 'center', justifyContent: 'center' }]}>
      <View style={{ width: '80%', maxWidth: dp(640) }}>
        <Text style={{ fontFamily: FONT.bold, fontSize: dp(22), color: '#FFFFFF', marginBottom: dp(12) }}>Jump to a slide</Text>
        <FlatList
          style={{ maxHeight: dp(420), marginBottom: dp(8) }}
          data={slides}
          initialScrollIndex={Math.max(0, current - 2)}
          getItemLayout={(_, i) => ({ length: dp(52), offset: dp(52) * i, index: i })}
          keyExtractor={(_, i) => String(i)}
          renderItem={({ item, index }) => (
            <View style={{ height: dp(52), justifyContent: 'center' }}>
              <TvButton text={`${index + 1}.  ${deckSlideLabel(item)}${index === current ? '   ◀ now' : ''}`} onPress={() => onPick(index)} focus={index === current} wide />
            </View>
          )}
        />
        <Text style={{ fontFamily: FONT.regular, fontSize: dp(13), color: 'rgba(255,255,255,0.7)' }}>OK to go  ·  Back to close</Text>
      </View>
    </View>
  )
}

export function SlidesPlayer({ deck, onExit, onFinished, report = true }: { deck: Deck; onExit: () => void; onFinished?: () => void; report?: boolean }) {
  const dp = useDp()
  const brand = useBrand()
  const ndi = useNdiFlag()
  const slides = useMemo(() => playableDeckSlides(deck, ndi), [deck, ndi])
  const [index, setIndex] = useState(0)
  const [blank, setBlank] = useState(false)
  const [showList, setShowList] = useState(false)
  const [streamFailed, setStreamFailed] = useState(false)
  const slide = slides[index] as (DeckSlide & Record<string, any>) | undefined
  const finish = onFinished ?? onExit

  const live = useRef({ index, slides, finish, onExit })
  live.current = { index, slides, finish, onExit }
  const next = () => {
    const l = live.current
    setBlank(false)
    if (l.index < l.slides.length - 1) setIndex(l.index + 1)
    else if (deck.loop) setIndex(0)
    else l.finish()
  }
  const previous = () => { setBlank(false); if (live.current.index > 0) setIndex(live.current.index - 1) }

  const outline = useMemo(() => slides.map(deckSlideLabel), [slides])
  useEffect(() => {
    if (!report) return
    Remote.status.value = {
      module: 'slides', state: blank ? 'blank' : 'playing', title: deck.name, label: outline[index] ?? '',
      index, count: slides.length, outline, refKind: 'deck', refId: deck.id,
    }
  }, [index, blank, outline])
  useEffect(() => () => { if (report) Remote.idle() }, [])
  useEffect(() => Remote.onCommand((c) => {
    switch (c.type) {
      case 'next': next(); break
      case 'previous': previous(); break
      case 'jump': setBlank(false); setShowList(false); setIndex(Math.min(Math.max(0, c.index), live.current.slides.length - 1)); break
      case 'blank': setBlank((b) => (c.on === null ? !b : c.on)); break
      case 'stop': live.current.onExit(); break
    }
  }), [])

  useEffect(() => {
    setStreamFailed(false)
    const s = slide
    const seconds =
      s?.kind === 'text' || s?.kind === 'stream' || s?.kind === 'ndi' ? s.seconds
        : s?.kind === 'media' && s.media_kind !== 'video' ? s.seconds
          : null
    if (!seconds || seconds <= 0) return
    const t = setTimeout(next, seconds * 1000)
    return () => clearTimeout(t)
  }, [index])

  useEffect(() => {
    if (!streamFailed) return
    const t = setTimeout(() => { setStreamFailed(false); next() }, 10_000)
    return () => clearTimeout(t)
  }, [streamFailed])

  useBack(() => { onExit(); return true }, !showList)
  useKeepAwake()
  useRemoteKeys((key) => {
    switch (key) {
      case 'right': case 'next': case 'fastForward': next(); return true
      case 'left': case 'previous': case 'rewind': previous(); return true
      case 'select': setShowList(true); return true
      case 'playPause': setBlank((b) => !b); return true
      default: return false
    }
  }, !showList)

  if (slides.length === 0) return <NoticeView text="This deck has no slides yet." />

  const style = toStyle(deck.theme, slide?.kind === 'text' ? slide.align : null, slide?.kind === 'text' ? slide.text_color : null)
  const bg = resolveBackground(deck, slide ?? null)
  const fgVideo = slide?.kind === 'stream' || (slide?.kind === 'media' && slide.media_kind === 'video')
  const logoShown = deck.theme?.logo?.show === true
  const logo = logoShown ? logoOn(brand, isLight(style.color) ? '#000000' : '#FFFFFF') : null
  const logoPos = deck.theme?.logo?.position ?? 'bottom_left'

  return (
    <View style={{ flex: 1, backgroundColor: '#000000' }}>
      <BackgroundLayer bg={bg} />
      {fgVideo && !streamFailed && slide ? (
        <VideoView
          key={`v${index}`}
          uri={slide.kind === 'stream' ? slide.url : localUri(slide.url)}
          paused={blank || showList}
          volume={slide.audio === false || (slide.kind === 'stream' && !slide.audio) ? 0 : 1}
          fit={slide.fit === 'cover' ? 'cover' : 'contain'}
          onEnded={next}
          onError={() => { if (slide.kind === 'stream' && slide.fallback === 'hold') setStreamFailed(true); else next() }}
        />
      ) : null}
      <View key={`s${index}`} style={FILL} pointerEvents="none">
        {slide?.kind === 'text' ? <TextSlideView slide={slide} style={style} /> : null}
        {slide?.kind === 'lyric' ? <LyricSlideView slide={slide} style={style} /> : null}
        {slide?.kind === 'song_title' ? <SongTitleView title={slide.title} authors={slide.authors ?? null} ccli={slide.ccli ?? null} copyright={slide.copyright ?? null} style={style} /> : null}
        {slide?.kind === 'countdown' ? <DeckCountdown slide={slide} style={style} paused={blank} onDone={next} /> : null}
        {slide?.kind === 'media' && slide.media_kind !== 'video' ? <Picture url={slide.url} fit={slide.fit === 'cover' ? 'cover' : 'contain'} /> : null}
        {slide?.kind === 'stream' && streamFailed ? <NoticeView text="Waiting for the live feed…" /> : null}
        {slide?.kind === 'ndi' ? <NoticeView text={slide.fallback_text || 'Live feed unavailable'} /> : null}
        {slide?.kind === 'blank' ? <View style={[FILL, { backgroundColor: parseHexColor(slide.color) ?? '#000000' }]} /> : null}
      </View>
      {logo ? (
        <Image
          source={{ uri: logo }}
          resizeMode="contain"
          style={{
            position: 'absolute', width: dp(134), height: dp(60),
            [logoPos.startsWith('top') ? 'top' : 'bottom']: dp(24),
            [logoPos.endsWith('right') ? 'right' : 'left']: dp(40),
          }}
        />
      ) : null}
      {blank ? <View style={[FILL, { backgroundColor: '#000000' }]} /> : null}
      {showList ? (
        <SlideList slides={slides} current={index} onPick={(i) => { setBlank(false); setIndex(i); setShowList(false) }} onClose={() => setShowList(false)} />
      ) : null}
    </View>
  )
}
