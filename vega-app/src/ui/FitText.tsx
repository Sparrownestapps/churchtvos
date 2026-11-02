import React from 'react'
import { Text, View, type TextStyle } from 'react-native'
import { fitFontSize, type FitWeight } from '../core/textFit'
import { FONT, useDp } from './context'

const FAMILY: Record<FitWeight, string> = { regular: FONT.regular, bold: FONT.bold, black: FONT.black, julius: FONT.julius }

/** Text sized to fill a [width] x [height] dp box (sizes in sp ≈ dp), like Compose's TextAutoSize. */
export function FitText(props: {
  text: string
  width: number
  height: number
  min: number
  max: number
  maxLines: number
  weight: FitWeight
  color: string
  align?: 'left' | 'center'
  /** Where the text sits in the box: top, center or bottom. */
  vertical?: 'top' | 'center' | 'bottom'
  lineHeight?: number
  style?: TextStyle
}) {
  const dp = useDp()
  const lh = props.lineHeight ?? 1.15
  const size = fitFontSize(props.text, {
    width: props.width, height: props.height, min: props.min, max: props.max, maxLines: props.maxLines, weight: props.weight, lineHeight: lh,
  })
  const justify = props.vertical === 'top' ? 'flex-start' : props.vertical === 'bottom' ? 'flex-end' : 'center'
  return (
    <View style={{ width: dp(props.width), height: dp(props.height), justifyContent: justify }}>
      <Text
        numberOfLines={props.maxLines}
        style={[
          {
            fontFamily: FAMILY[props.weight],
            fontSize: dp(size),
            lineHeight: dp(size * lh),
            color: props.color,
            textAlign: props.align ?? 'center',
          },
          props.style,
        ]}
      >
        {props.text}
      </Text>
    </View>
  )
}
