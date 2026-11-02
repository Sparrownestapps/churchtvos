// Shared screen context: the church's look, the layout scale, portrait rotation, the site time zone and the NDI flag.
// Layouts are written in the Android app's dp, on a 960 x 540 canvas (a 1080p TV at density 2); dp() scales to the real screen.
import React, { createContext, useContext } from 'react'
import { DEFAULT_BRAND, type Brand } from '../core/brand'

export interface Screen {
  /** Canvas size in dp after rotation: 960 x 540 landscape, 540 x 960 portrait. */
  width: number
  height: number
  rotated: boolean
  /** Pixels per dp. */
  scale: number
}

export const BrandContext = createContext<Brand>(DEFAULT_BRAND)
export const ScreenContext = createContext<Screen>({ width: 960, height: 540, rotated: false, scale: 2 })
export const TimeZoneContext = createContext<string>('America/Toronto')
export const NdiContext = createContext<boolean>(false)

export const useBrand = () => useContext(BrandContext)
export const useScreen = () => useContext(ScreenContext)
export const useTimeZone = () => useContext(TimeZoneContext)
export const useNdiFlag = () => useContext(NdiContext)

/** dp → pixels for the current screen. */
export function useDp(): (dp: number) => number {
  const { scale } = useScreen()
  return (dp: number) => dp * scale
}

export function BrandProvider({ brand, children }: { brand: Brand; children: React.ReactNode }) {
  return <BrandContext.Provider value={brand}>{children}</BrandContext.Provider>
}

export const FONT = {
  regular: 'Lato-Regular',
  bold: 'Lato-Bold',
  black: 'Lato-Black',
  julius: 'JuliusSansOne-Regular',
} as const

export const GREYSCALE = '#58595B'
export const PAPER = '#F4F5F7'
