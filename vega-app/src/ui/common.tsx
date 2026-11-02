// Pieces several screens share: the focusable button, the church logo, branded frames, splash and message screens.
import React, { useState } from 'react'
import { Image, Pressable, Text, View } from 'react-native'
import { logoOn } from '../core/brand'
import { FONT, GREYSCALE, useBrand, useDp } from './context'

/** A remote-friendly button: primary colour, accent when focused. */
export function TvButton(props: { text: string; onPress: () => void; focus?: boolean; disabled?: boolean; wide?: boolean }) {
  const dp = useDp()
  const brand = useBrand()
  const [focused, setFocused] = useState(false)
  const bg = props.disabled ? 'rgba(27,42,74,0.2)' : focused ? brand.accent : brand.primary
  return (
    <Pressable
      hasTVPreferredFocus={props.focus}
      disabled={props.disabled}
      focusable={!props.disabled}
      onFocus={() => setFocused(true)}
      onBlur={() => setFocused(false)}
      onPress={props.onPress}
      style={{
        backgroundColor: bg,
        borderRadius: dp(24),
        paddingHorizontal: dp(20),
        paddingVertical: dp(10),
        alignSelf: props.wide ? 'stretch' : 'center',
        transform: [{ scale: focused ? 1.05 : 1 }],
      }}
    >
      <Text style={{ fontFamily: FONT.bold, fontSize: dp(18), color: '#FFFFFF', textAlign: props.wide ? 'left' : 'center' }}>{props.text}</Text>
    </Pressable>
  )
}

/** The church's logo, or its name when no logo is set. 300dp wide keeps it legible from across a room. */
export function OrgLogo({ background = '#FFFFFF' }: { background?: string }) {
  const dp = useDp()
  const brand = useBrand()
  const logo = logoOn(brand, background)
  if (logo) {
    return <Image source={{ uri: logo }} resizeMode="contain" style={{ width: dp(300), height: dp(72) }} />
  }
  return (
    <Text style={{ fontFamily: FONT.julius, fontSize: dp(22), letterSpacing: dp(3), color: brand.primary }}>
      {brand.orgName.toUpperCase()}
    </Text>
  )
}

/** White screen with the logo top-left and [children] centred. 48dp/27dp keeps everything inside the TV-safe area. */
export function BrandedScreen({ children }: { children: React.ReactNode }) {
  const dp = useDp()
  return (
    <View style={{ flex: 1, backgroundColor: '#FFFFFF', paddingHorizontal: dp(48), paddingVertical: dp(27) }}>
      <OrgLogo />
      <View style={{ position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, alignItems: 'center', justifyContent: 'center' }}>
        {children}
      </View>
    </View>
  )
}

export function Title({ children }: { children: React.ReactNode }) {
  const dp = useDp()
  const brand = useBrand()
  return <Text style={{ fontFamily: FONT.julius, fontSize: dp(40), color: brand.primary, textAlign: 'center' }}>{children}</Text>
}

export function Body({ children, size = 18, bold = false }: { children: React.ReactNode; size?: number; bold?: boolean }) {
  const dp = useDp()
  return (
    <Text style={{ fontFamily: bold ? FONT.bold : FONT.regular, fontSize: dp(size), lineHeight: dp(size * 1.55), color: GREYSCALE, textAlign: 'center' }}>
      {children}
    </Text>
  )
}

export function Gap({ h = 12 }: { h?: number }) {
  const dp = useDp()
  return <View style={{ height: dp(h) }} />
}

export function MessageScreen({ title, detail }: { title: string; detail?: string | null }) {
  return (
    <BrandedScreen>
      <Title>{title}</Title>
      {detail ? (
        <>
          <Gap />
          <Body size={14}>{detail}</Body>
        </>
      ) : null}
    </BrandedScreen>
  )
}

/** Full-screen logo on the brand's primary colour. */
export function SplashScreen() {
  const dp = useDp()
  const brand = useBrand()
  const logo = logoOn(brand, brand.primary)
  return (
    <View style={{ flex: 1, backgroundColor: brand.primary, alignItems: 'center', justifyContent: 'center' }}>
      {logo ? (
        <Image source={{ uri: logo }} resizeMode="contain" style={{ width: '55%', height: '50%' }} />
      ) : (
        <Text style={{ fontFamily: FONT.julius, fontSize: dp(56), letterSpacing: dp(6), color: '#FFFFFF', textAlign: 'center' }}>
          {brand.orgName.toUpperCase()}
        </Text>
      )}
    </View>
  )
}

export function Black() {
  return <View style={{ flex: 1, backgroundColor: '#000000' }} />
}
