import React from 'react'
import { View, useWindowDimensions } from 'react-native'
import { ScreenContext } from './context'

/**
 * The TV always outputs landscape, so for a TV mounted upright the content is laid out sideways (width and height
 * swapped) and turned a quarter turn. "portrait" turns clockwise (TV's left edge at the bottom); "portrait_flipped"
 * the other way. Same rule as the Android app's Oriented().
 */
export function Oriented({ orientation, children }: { orientation: string; children: React.ReactNode }) {
  const { width, height } = useWindowDimensions()
  const portrait = orientation === 'portrait' || orientation === 'portrait_flipped'
  const scale = width / 960
  if (!portrait) {
    return (
      <ScreenContext.Provider value={{ width: 960, height: 540, rotated: false, scale }}>
        <View style={{ width, height, overflow: 'hidden', backgroundColor: '#000' }}>{children}</View>
      </ScreenContext.Provider>
    )
  }
  const angle = orientation === 'portrait' ? '90deg' : '-90deg'
  return (
    <ScreenContext.Provider value={{ width: 540, height: 960, rotated: true, scale }}>
      <View style={{ width, height, overflow: 'hidden', backgroundColor: '#000' }}>
        <View
          style={{
            position: 'absolute',
            width: height,
            height: width,
            left: (width - height) / 2,
            top: (height - width) / 2,
            transform: [{ rotate: angle }],
          }}
        >
          {children}
        </View>
      </View>
    </ScreenContext.Provider>
  )
}
