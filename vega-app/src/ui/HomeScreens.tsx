// The "what's scheduled here" screens for Kids and Slides, with a Play button. Mirrors tv-app HomeScreen.kt and DeckHomeScreen.
import React from 'react'
import { Text, View } from 'react-native'
import { OrgLogo, TvButton } from './common'
import { FONT, GREYSCALE, PAPER, useBrand, useDp, useScreen } from './context'

export interface HomeRow { kind: string; label: string }

export function HomeScreen(props: {
  site: string
  location: string
  heading: string
  title: string | null
  rows: HomeRow[]
  total: number
  status: string
  hint: string
  canPlay: boolean
  onPlay: () => void
}) {
  const dp = useDp()
  const brand = useBrand()
  const { rotated } = useScreen()
  const limit = rotated ? 14 : 8

  const identity = (
    <View>
      <Text style={{ fontFamily: FONT.bold, fontSize: dp(rotated ? 18 : 14), letterSpacing: dp(2), color: brand.accent }}>{props.site.toUpperCase()}</Text>
      <Text style={{ fontFamily: FONT.julius, fontSize: dp(rotated ? 56 : 44), color: brand.primary }}>{props.location}</Text>
    </View>
  )
  const hint = <Text style={{ fontFamily: FONT.regular, fontSize: dp(rotated ? 14 : 12), color: GREYSCALE }}>{props.hint}</Text>

  const card = (
    <View style={{ flex: 1, backgroundColor: PAPER, borderRadius: dp(16), padding: dp(28) }}>
      <Text style={{ fontFamily: FONT.bold, fontSize: dp(12), letterSpacing: dp(2), color: brand.accent }}>{props.heading}</Text>
      <Text numberOfLines={2} style={{ fontFamily: FONT.black, fontSize: dp(28), color: brand.primary }}>{props.title ?? '—'}</Text>
      <View style={{ height: dp(16) }} />
      {props.rows.slice(0, limit).map((r, i) => (
        <View key={i} style={{ flexDirection: 'row', alignItems: 'center', paddingVertical: dp(4) }}>
          <Text style={{ width: dp(96), fontFamily: FONT.bold, fontSize: dp(11), letterSpacing: dp(1), color: brand.accent }}>{r.kind}</Text>
          <Text numberOfLines={1} style={{ flex: 1, fontFamily: FONT.regular, fontSize: dp(16), color: GREYSCALE }}>{r.label}</Text>
        </View>
      ))}
      {props.total > limit ? (
        <Text style={{ fontFamily: FONT.regular, fontSize: dp(13), color: GREYSCALE }}>{`+ ${props.total - limit} more`}</Text>
      ) : null}
      <View style={{ flex: 1 }} />
      <Text style={{ fontFamily: FONT.regular, fontSize: dp(13), color: GREYSCALE }}>{props.status}</Text>
      <View style={{ height: dp(12) }} />
      <View style={{ alignSelf: 'flex-start' }}>
        <TvButton text="Play" onPress={props.onPlay} disabled={!props.canPlay} focus={props.canPlay} />
      </View>
    </View>
  )

  if (rotated) {
    return (
      <View style={{ flex: 1, backgroundColor: '#FFFFFF', paddingHorizontal: dp(40), paddingVertical: dp(48) }}>
        <OrgLogo />
        <View style={{ height: dp(28) }} />
        {identity}
        <View style={{ height: dp(28) }} />
        {card}
        <View style={{ height: dp(28) }} />
        {hint}
      </View>
    )
  }
  return (
    <View style={{ flex: 1, flexDirection: 'row', backgroundColor: '#FFFFFF', paddingHorizontal: dp(48), paddingVertical: dp(27) }}>
      <View style={{ flex: 1, justifyContent: 'space-between', marginRight: dp(40) }}>
        <OrgLogo />
        {identity}
        {hint}
      </View>
      <View style={{ flex: 1 }}>{card}</View>
    </View>
  )
}
