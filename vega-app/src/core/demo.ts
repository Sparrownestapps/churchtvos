// Built-in sample content for app-store reviewers and first-time visitors. Needs no account and no network.
import type { Slide } from './model'

export function demoSlides(which: 'kids' | 'signage'): Slide[] {
  if (which === 'signage') {
    return [
      { kind: 'bundled', asset: 'welcome', seconds: 6 },
      { kind: 'bundled', asset: 'events', seconds: 6 },
      { kind: 'bundled', asset: 'info', seconds: 6 },
    ]
  }
  const spec = { mode: 'duration', seconds: 10, until: null, audio: null, atZero: 'next', ifPassed: 'zero' }
  return [
    { kind: 'countdown', title: 'Service starts in', spec },
    { kind: 'lyric', song: 'Sample song', text: 'Verse 1\nSample lyrics appear\nlarge and centred', number: 1, count: 2 },
    { kind: 'lyric', song: 'Sample song', text: 'Chorus\nOne slide per section,\nadvance with Right', number: 2, count: 2 },
    { kind: 'bundled', asset: 'welcome', seconds: 6 },
  ]
}
