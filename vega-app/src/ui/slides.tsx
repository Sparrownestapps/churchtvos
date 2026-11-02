// Slide views shared by the Kids/Signage player and the Slides player. Mirrors tv-app SignSlide.kt, SongTitleSlide.kt,
// SlideViews.kt and the countdown/lyric views in PlayerScreen.kt.
import React, { useEffect, useRef, useState } from 'react'
import { Image, Text, View, type TextStyle } from 'react-native'
import { logoOn, parseHexColor, textColorOn, withAlpha } from '../core/brand'
import { countdownEnd, fadeFactor, formatCountdown } from '../core/countdown'
import type { CountdownSpec } from '../core/model'
import type { SlideStyle } from '../core/slideStyle'
import { FitText } from './FitText'
import { FONT, useBrand, useDp, useScreen, useTimeZone } from './context'
import { localUri, VideoView } from '../platform'

export function shadowStyle(style: SlideStyle | null, dp: (n: number) => number): TextStyle {
  if (!style || style.shadow === 'none') return {}
  if (style.shadow === 'outline') return { textShadowColor: '#000000', textShadowOffset: { width: 0, height: 0 }, textShadowRadius: dp(7) }
  return { textShadowColor: 'rgba(0,0,0,0.6)', textShadowOffset: { width: 0, height: dp(1.5) }, textShadowRadius: dp(5) }
}

/**
 * Runs a countdown: ticks the clock, plays the optional music (started late and cut to finish at zero when "align end"
 * is on, faded out at the end), then moves on or holds at 0:00. [render] draws the time text. While [paused] the music pauses.
 */
export function CountdownRunner(props: {
  spec: CountdownSpec
  paused: boolean
  onFinished: () => void
  render: (time: string) => React.ReactNode
}) {
  const zone = useTimeZone()
  const startedAt = useRef(Date.now()).current
  const endAt = useRef(countdownEnd(props.spec, startedAt, zone)).current
  const alreadyPassed = props.spec.mode === 'until' && endAt <= startedAt
  const [remaining, setRemaining] = useState(Math.max(0, endAt - startedAt))
  const finished = useRef(props.onFinished)
  finished.current = props.onFinished

  useEffect(() => {
    if (alreadyPassed && props.spec.ifPassed === 'skip') {
      finished.current()
      return
    }
    let done = false
    const timers: ReturnType<typeof setTimeout>[] = []
    const tick = setInterval(() => {
      const left = Math.max(0, endAt - Date.now())
      setRemaining(left)
      if (left <= 0 && !done) {
        done = true
        clearInterval(tick)
        // At zero: move on, or hold on 0:00 until the leader presses Next. (A time already passed shows 0:00 for a moment first.)
        if (props.spec.atZero !== 'hold') timers.push(setTimeout(() => finished.current(), alreadyPassed ? 2000 : 0))
      }
    }, 250)
    return () => { clearInterval(tick); timers.forEach(clearTimeout) }
  }, [])

  const audio = props.spec.audio
  // Music: starts now, or (align end) waits so the track ends exactly at zero. Seeking into a track is handled by the player.
  const [musicStartIn, setMusicStartIn] = useState<number | null>(null)
  const [duration, setDuration] = useState(0)
  const audioUri = audio ? localUri(audio.url) : null
  useEffect(() => {
    if (!audio || alreadyPassed || !duration) return
    if (audio.align_end) {
      const untilZero = endAt - Date.now()
      setMusicStartIn(untilZero > duration ? untilZero - duration : 0)
    } else setMusicStartIn(0)
  }, [duration])
  const [musicOn, setMusicOn] = useState(false)
  useEffect(() => {
    if (musicStartIn === null) return
    const t = setTimeout(() => setMusicOn(true), musicStartIn)
    return () => clearTimeout(t)
  }, [musicStartIn])
  const seekTo = audio?.align_end && duration ? Math.max(0, duration - (endAt - Date.now())) : 0

  return (
    <>
      {props.render(formatCountdown(remaining))}
      {audio && audioUri && !alreadyPassed ? (
        <VideoView
          uri={audioUri}
          audioOnly
          paused={!musicOn || props.paused || remaining <= 0}
          loop={(audio.loop ?? true) && !audio.align_end}
          volume={Math.min(1, Math.max(0, audio.volume ?? 0.8)) * fadeFactor(remaining, audio.fade_seconds ?? 3)}
          startAtMs={musicOn ? seekTo : 0}
          onDuration={setDuration}
        />
      ) : null}
    </>
  )
}

/** Kids countdown: title and time on the church's primary colour. */
export function KidsCountdown({ title, spec, paused, onDone }: { title: string; spec: CountdownSpec; paused: boolean; onDone: () => void }) {
  const dp = useDp()
  const brand = useBrand()
  return (
    <CountdownRunner
      spec={spec}
      paused={paused}
      onFinished={onDone}
      render={(time) => (
        <View style={{ flex: 1, backgroundColor: brand.primary, alignItems: 'center', justifyContent: 'center' }}>
          {title.trim() ? (
            <Text style={{ fontFamily: FONT.bold, fontSize: dp(22), letterSpacing: dp(4), color: brand.accent }}>{title.toUpperCase()}</Text>
          ) : null}
          <Text style={{ fontFamily: FONT.julius, fontSize: dp(160), color: '#FFFFFF' }}>{time}</Text>
        </View>
      )}
    />
  )
}

/** Kids lyrics: one section, centred, with the song and position in the corner. */
export function KidsLyric({ song, text, number, count }: { song: string; text: string; number: number; count: number }) {
  const dp = useDp()
  const brand = useBrand()
  const { width, height } = useScreen()
  return (
    <View style={{ flex: 1, backgroundColor: brand.primary, paddingHorizontal: dp(48), paddingVertical: dp(27), justifyContent: 'center' }}>
      <FitText text={text} width={width - 96} height={height - 54 - 30} min={20} max={40} maxLines={10} weight="bold" color="#FFFFFF" lineHeight={1.35} />
      <Text style={{ position: 'absolute', right: dp(48), bottom: dp(27), fontFamily: FONT.regular, fontSize: dp(12), color: 'rgba(255,255,255,0.6)' }}>
        {`${song}  ·  ${number}/${count}`}
      </Text>
    </View>
  )
}

/** The song name before the words. Holds until Next. [style] is set in decks (theme colours), null in Kids. */
export function SongTitleView(props: { title: string; authors: string | null; ccli: string | null; copyright: string | null; style: SlideStyle | null }) {
  const dp = useDp()
  const brand = useBrand()
  const { width, height } = useScreen()
  const color = props.style?.color ?? '#FFFFFF'
  const shadow = shadowStyle(props.style, dp)
  const footer = [props.ccli?.trim() ? `CCLI Song # ${props.ccli}` : null, props.copyright?.trim() || null].filter(Boolean).join('  ·  ')
  return (
    <View
      style={{
        flex: 1, backgroundColor: props.style ? 'transparent' : brand.primary,
        paddingHorizontal: dp(width * 0.08), paddingVertical: dp(height * 0.08), alignItems: 'center', justifyContent: 'center',
      }}
    >
      <FitText
        text={props.title} width={width * 0.84} height={height * 0.4} min={28} max={140 * (props.style?.titleScale ?? 1)} maxLines={3}
        weight={props.style?.titleFont === 'julius' ? 'julius' : 'black'} color={color} vertical="bottom" lineHeight={1.1} style={shadow}
      />
      {props.authors?.trim() ? (
        <Text numberOfLines={2} style={[{ marginTop: dp(8), fontFamily: FONT.regular, fontSize: dp(26), color: withAlpha(color, 0.85), textAlign: 'center' }, shadow]}>
          {props.authors}
        </Text>
      ) : null}
      {footer ? (
        <Text numberOfLines={2} style={[{ marginTop: dp(24), fontFamily: FONT.regular, fontSize: dp(14), color: withAlpha(color, 0.6), textAlign: 'center' }, shadow]}>
          {footer}
        </Text>
      ) : null}
    </View>
  )
}

/** A sign built in the dashboard: coloured background, title, optional subtext, optional church logo. */
export function SignView(props: { title: string; subtext: string; background: string; align: string; logo: boolean }) {
  const dp = useDp()
  const brand = useBrand()
  const { width, height } = useScreen()
  const bg = parseHexColor(props.background) ?? brand.primary
  const fg = textColorOn(bg)
  const center = props.align !== 'left'
  const logo = props.logo ? logoOn(brand, bg) : null
  const hasSub = props.subtext.trim().length > 0
  const innerW = width * 0.86
  return (
    <View style={{ flex: 1, backgroundColor: bg, paddingHorizontal: dp(width * 0.07), paddingVertical: dp(height * 0.08) }}>
      {logo ? (
        <Image source={{ uri: logo }} resizeMode="contain" style={{ width: dp(innerW), height: dp(height * 0.14), alignSelf: center ? 'center' : 'flex-start' }} />
      ) : null}
      <View style={{ flex: 1, justifyContent: 'center', alignItems: center ? 'center' : 'flex-start' }}>
        <FitText text={props.title} width={innerW} height={height * (hasSub ? 0.42 : 0.62)} min={28} max={160} maxLines={3} weight="black" color={fg} align={center ? 'center' : 'left'} lineHeight={1.1} />
        {hasSub ? (
          <FitText text={props.subtext} width={innerW} height={height * 0.24 - 12} min={18} max={72} maxLines={4} weight="regular" color={withAlpha(fg, 0.9)} align={center ? 'center' : 'left'} vertical="top" lineHeight={1.2} />
        ) : null}
      </View>
    </View>
  )
}

/** A message on a plain background: a live feed that isn't there, or an NDI item's fallback text. */
export function NoticeView({ text }: { text: string }) {
  const dp = useDp()
  return (
    <View style={{ flex: 1, backgroundColor: '#000000', alignItems: 'center', justifyContent: 'center', padding: dp(48) }}>
      <Text style={{ fontFamily: FONT.bold, fontSize: dp(28), color: '#FFFFFF', textAlign: 'center' }}>{text}</Text>
    </View>
  )
}

/** A full-screen picture from the media cache (or the web while it downloads). */
export function Picture({ url, fit }: { url: string; fit: 'contain' | 'cover' }) {
  return <Image source={{ uri: localUri(url) }} resizeMode={fit} style={{ position: 'absolute', left: 0, top: 0, right: 0, bottom: 0 }} />
}
