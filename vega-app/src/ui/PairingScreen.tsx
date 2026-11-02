import React, { useMemo } from 'react'
import { Text, View } from 'react-native'
// The core encoder only (no canvas or file renderers), so it runs on the TV.
// @ts-ignore no types for the deep import
import QRCodeCore from 'qrcode/lib/core/qrcode'
import { DASHBOARD_HOST } from '../core/config'
import { pairingQrPayload } from '../core/brand'
import { Body, BrandedScreen, Gap, Title, TvButton } from './common'
import { FONT, useBrand, useDp, useScreen } from './context'

/** Rows of dark runs [start, length] for [text]. Medium error correction keeps it sparse enough to scan from across a room. */
function qrRuns(text: string): { size: number; rows: [number, number][][] } {
  const m = QRCodeCore.create(text, { errorCorrectionLevel: 'M' }).modules
  const rows: [number, number][][] = []
  for (let y = 0; y < m.size; y++) {
    const runs: [number, number][] = []
    let x = 0
    while (x < m.size) {
      if (m.get(y, x)) {
        const start = x
        while (x < m.size && m.get(y, x)) x++
        runs.push([start, x - start])
      } else x++
    }
    rows.push(runs)
  }
  return { size: m.size, rows }
}

/** Black modules on a white tile with a 4-module quiet zone, as the QR spec requires. */
function PairingQr({ payload, size }: { payload: string; size: number }) {
  const dp = useDp()
  const { size: n, rows } = useMemo(() => qrRuns(payload), [payload])
  const cell = dp(size) / (n + 8)
  return (
    <View style={{ width: dp(size), height: dp(size), backgroundColor: '#FFFFFF', borderRadius: dp(4) }}>
      {rows.map((runs, y) =>
        runs.map(([x, len]) => (
          <View
            key={`${y}-${x}`}
            style={{
              position: 'absolute', backgroundColor: '#000000',
              left: (x + 4) * cell, top: (y + 4) * cell,
              // slight overlap avoids hairline gaps between modules
              width: len * cell + 0.5, height: cell + 0.5,
            }}
          />
        )),
      )}
    </View>
  )
}

export function PairingScreen({ code, offline, onSettings }: { code: string; offline: boolean; onSettings: () => void }) {
  const dp = useDp()
  const brand = useBrand()
  const { rotated } = useScreen()
  const payload = pairingQrPayload(code)
  const spaced = code.length === 6 ? `${code.slice(0, 3)}  ${code.slice(3)}` : code

  const codeBox = (
    <View style={{ backgroundColor: brand.primary, borderRadius: dp(16), paddingHorizontal: dp(40), paddingVertical: dp(8) }}>
      <Text style={{ fontFamily: FONT.black, fontSize: dp(72), letterSpacing: dp(8), color: '#FFFFFF' }}>{spaced}</Text>
    </View>
  )
  const qrCaption = <Body bold>{`Scan with the Church TV OS app,\nor enter the code at ${DASHBOARD_HOST}`}</Body>

  return (
    <BrandedScreen>
      <Title>Pair this TV</Title>
      <Gap />
      {!payload ? (
        <>
          {codeBox}
          <Gap h={16} />
          <Body>{`In the Church TV OS dashboard (${DASHBOARD_HOST}),\ngo to Screens → Pair a TV, enter this code and choose the location.`}</Body>
        </>
      ) : rotated ? (
        <>
          {codeBox}
          <Gap h={16} />
          <PairingQr payload={payload} size={260} />
          <Gap h={8} />
          {qrCaption}
        </>
      ) : (
        <View style={{ flexDirection: 'row', alignItems: 'center' }}>
          <View style={{ alignItems: 'center', marginRight: dp(48) }}>
            {codeBox}
            <Gap h={16} />
            {qrCaption}
          </View>
          <PairingQr payload={payload} size={200} />
        </View>
      )}
      <Gap h={16} />
      <TvButton text="Settings and demo mode" onPress={onSettings} focus />
      {offline ? (
        <>
          <Gap h={16} />
          <Text style={{ fontFamily: FONT.bold, fontSize: dp(14), color: brand.accent }}>⚠ Can't reach the internet. Check this TV's Wi-Fi.</Text>
        </>
      ) : null}
    </BrandedScreen>
  )
}
