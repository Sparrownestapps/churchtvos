// Plays a Kids or Signage playlist. Right/Left = next/back, OK/Play = pause a video, Back = stop. Obeys phone remotes and
// reports what is on screen. Mirrors tv-app PlayerScreen.kt.
import React, { useEffect, useMemo, useRef, useState } from 'react'
import { Image, View } from 'react-native'
import { slideLabel, type Slide } from '../core/model'
import { Remote } from '../core/remote'
import { localUri, useBack, useKeepAwake, useRemoteKeys, VideoView } from '../platform'
import { KidsCountdown, KidsLyric, NoticeView, Picture, SignView, SongTitleView } from './slides'
import { BUNDLED } from './bundled'

/** What a player tells remotes about itself. Null means "do not report" (demo mode). */
export interface PlayerReport { module: string; title: string; refKind?: string; refId?: string }

export function PlayerScreen(props: {
  slides: Slide[]
  /** Back or Stop. */
  onExit: () => void
  /** Reaching the end (Signage loops, demo restarts). Defaults to onExit. */
  onFinished?: () => void
  report?: PlayerReport | null
}) {
  const { slides } = props
  const [index, setIndex] = useState(0)
  const [blank, setBlank] = useState(false)
  const [paused, setPaused] = useState(false)
  const [streamFailed, setStreamFailed] = useState(false)
  const slide: Slide | undefined = slides[index]
  const onFinished = props.onFinished ?? props.onExit

  // Latest values for callbacks that outlive a render (timers, remote commands, player events).
  const live = useRef({ index, slides, onFinished, onExit: props.onExit })
  live.current = { index, slides, onFinished, onExit: props.onExit }
  const next = () => {
    const l = live.current
    if (l.index < l.slides.length - 1) setIndex(l.index + 1)
    else l.onFinished()
  }
  const previous = () => { if (live.current.index > 0) setIndex(live.current.index - 1) }

  // Nothing playable (everything was skipped): don't spin, wait a moment then finish.
  useEffect(() => {
    if (slides.length > 0) return
    const t = setTimeout(() => live.current.onFinished(), 5000)
    return () => clearTimeout(t)
  }, [slides])

  // Remote control: tell phones what is on screen, and obey them.
  const outline = useMemo(() => slides.map(slideLabel), [slides])
  useEffect(() => {
    const r = props.report
    if (!r) return
    Remote.status.value = {
      module: r.module, state: blank ? 'blank' : 'playing', title: r.title,
      label: slide ? slideLabel(slide) : '', index, count: slides.length, outline,
      refKind: r.refKind ?? null, refId: r.refId ?? null,
    }
  }, [index, blank, props.report, outline])
  useEffect(() => () => { if (props.report) Remote.idle() }, [])
  useEffect(() => Remote.onCommand((c) => {
    switch (c.type) {
      case 'next': next(); break
      case 'previous': previous(); break
      case 'jump': setBlank(false); setIndex(Math.min(Math.max(0, c.index), live.current.slides.length - 1)); break
      case 'blank': setBlank((b) => (c.on === null ? !b : c.on)); break
      case 'stop': live.current.onExit(); break
    }
  }), [])

  // Timed slides move on by themselves.
  useEffect(() => {
    setStreamFailed(false)
    setPaused(false)
    const seconds =
      slide?.kind === 'image' ? slide.seconds
        : slide?.kind === 'bundled' || slide?.kind === 'sign' ? slide.seconds
          : slide?.kind === 'stream' || slide?.kind === 'notice' ? slide.seconds
            : null
    if (seconds === null || seconds === undefined) return
    const t = setTimeout(next, seconds * 1000)
    return () => clearTimeout(t)
  }, [index])

  // A dead live stream never leaves a blank room: skip it, or hold a notice for 10 s then skip.
  useEffect(() => {
    if (!streamFailed) return
    const t = setTimeout(() => { setStreamFailed(false); next() }, 10_000)
    return () => clearTimeout(t)
  }, [streamFailed])

  useBack(() => { props.onExit(); return true })
  useKeepAwake()
  useRemoteKeys((key) => {
    switch (key) {
      case 'right': case 'next': case 'fastForward': next(); return true
      case 'left': case 'previous': case 'rewind': previous(); return true
      case 'select': case 'playPause':
        if (slide?.kind === 'video' || slide?.kind === 'stream') setPaused((p) => !p)
        return true
      default: return false
    }
  })

  const isVideo = slide?.kind === 'video' || slide?.kind === 'stream'
  return (
    <View style={{ flex: 1, backgroundColor: '#000000' }}>
      {isVideo && !streamFailed ? (
        <VideoView
          key={index}
          uri={slide.kind === 'video' ? localUri(slide.url) : slide.url}
          paused={paused || blank}
          volume={slide.kind === 'stream' && !slide.audio ? 0 : 1}
          fit="contain"
          onEnded={next}
          onError={() => {
            if (slide.kind === 'stream') { if (slide.fallback === 'hold') setStreamFailed(true); else next() }
            else next()
          }}
        />
      ) : null}
      <View key={`s${index}`} style={{ position: 'absolute', left: 0, top: 0, right: 0, bottom: 0 }} pointerEvents="none">
        {slide?.kind === 'image' ? <Picture url={slide.url} fit="contain" /> : null}
        {slide?.kind === 'bundled' ? (
          <Image source={BUNDLED[slide.asset]} resizeMode="contain" style={{ width: '100%', height: '100%' }} />
        ) : null}
        {slide?.kind === 'countdown' ? <KidsCountdown title={slide.title} spec={slide.spec} paused={blank} onDone={next} /> : null}
        {slide?.kind === 'lyric' ? <KidsLyric song={slide.song} text={slide.text} number={slide.number} count={slide.count} /> : null}
        {slide?.kind === 'song_title' ? <SongTitleView title={slide.title} authors={slide.authors} ccli={slide.ccli} copyright={slide.copyright} style={null} /> : null}
        {slide?.kind === 'sign' ? <SignView title={slide.title} subtext={slide.subtext} background={slide.background} align={slide.align} logo={slide.logo} /> : null}
        {slide?.kind === 'notice' ? <NoticeView text={slide.text} /> : null}
        {slide?.kind === 'stream' && streamFailed ? <NoticeView text="Waiting for the live feed…" /> : null}
      </View>
      {blank ? <View style={{ position: 'absolute', left: 0, top: 0, right: 0, bottom: 0, backgroundColor: '#000000' }} /> : null}
    </View>
  )
}
