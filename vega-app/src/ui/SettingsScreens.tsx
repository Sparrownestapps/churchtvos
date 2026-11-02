// Settings and the demo-mode picker. Opened with the remote's Menu button, by holding OK, or from the pairing screen.
// Vega apps can't open themselves when the TV turns on, so there is no auto-launch switch (unlike the Fire OS app).
import React from 'react'
import { Text, View } from 'react-native'
import { useBack } from '../platform'
import { Body, Gap, Title, TvButton } from './common'
import { FONT, GREYSCALE, useDp } from './context'

function Frame({ title, children }: { title: string; children: React.ReactNode }) {
  const dp = useDp()
  return (
    <View style={{ flex: 1, backgroundColor: '#FFFFFF', paddingHorizontal: dp(48), paddingVertical: dp(27), alignItems: 'center', justifyContent: 'center' }}>
      <Title>{title}</Title>
      <Gap h={24} />
      {children}
    </View>
  )
}

export function SettingsScreen(props: { paired: boolean; detail: string; onDemo: () => void; onUnpair: () => void; onClose: () => void }) {
  const dp = useDp()
  useBack(() => { props.onClose(); return true })
  return (
    <Frame title="Settings">
      {props.paired ? (
        <>
          <Body>Start Church TV OS from the Fire TV home screen when the TV is switched on. Tip: keep it in your favourite apps row.</Body>
          <Gap h={16} />
        </>
      ) : null}
      <TvButton text="Demo mode" onPress={props.onDemo} focus />
      <Gap />
      {props.paired ? (
        <>
          <TvButton text="Unpair this TV" onPress={props.onUnpair} />
          <Gap />
        </>
      ) : null}
      <TvButton text="Close" onPress={props.onClose} />
      <Gap h={20} />
      <Text style={{ fontFamily: FONT.regular, fontSize: dp(13), color: GREYSCALE, textAlign: 'center' }}>{props.detail}</Text>
    </Frame>
  )
}

export function DemoMenu({ onPick, onClose }: { onPick: (which: 'kids' | 'signage') => void; onClose: () => void }) {
  useBack(() => { onClose(); return true })
  return (
    <Frame title="Demo mode">
      <Body>Sample content, no account needed. Press Back to leave a demo.</Body>
      <Gap h={20} />
      <TvButton text="Kids demo (countdown, lyrics)" onPress={() => onPick('kids')} focus />
      <Gap />
      <TvButton text="Signage demo (looping slides)" onPress={() => onPick('signage')} />
      <Gap />
      <TvButton text="Back" onPress={onClose} />
    </Frame>
  )
}

/** Asked before unpairing, since it needs someone at the dashboard to pair the TV again. */
export function ConfirmUnpair({ onYes, onNo }: { onYes: () => void; onNo: () => void }) {
  useBack(() => { onNo(); return true })
  return (
    <Frame title="Unpair this TV?">
      <Body>It will show a new pairing code. Delete the old screen in the dashboard, then pair it again.</Body>
      <Gap h={20} />
      <TvButton text="Keep it paired" onPress={onNo} focus />
      <Gap />
      <TvButton text="Unpair" onPress={onYes} />
    </Frame>
  )
}
