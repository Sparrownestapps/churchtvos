/**
 * Links and constants shared by the Get started checklist, the empty states and the header Help link.
 * Fill in the two store URLs when the apps are live; until then the dashboard says "coming soon".
 */
export const AMAZON_APPSTORE_URL = '' // e.g. https://www.amazon.com/dp/...
export const GOOGLE_PLAY_URL = '' // e.g. https://play.google.com/store/apps/details?id=com.churchtvos.tv
export const SIDELOAD_URL = '/install.html'
export const SUPPORT_EMAIL = 'keith@sparrownest.com'

/** Static help pages in public/help/. Keys are used by `helpUrl`. */
export const HELP_PAGES = {
  index: '',
  quickstart: 'quick-start.html',
  ideas: 'key-ideas.html',
  install: 'install-app.html',
  screens: 'screens.html',
  media: 'media.html',
  songs: 'songs.html',
  kids: 'kids.html',
  signage: 'signage.html',
  slides: 'slides.html',
  calendar: 'calendar.html',
  control: 'control.html',
  branding: 'branding.html',
  people: 'people.html',
  portrait: 'portrait.html',
  troubleshooting: 'troubleshooting.html',
  billing: 'billing.html',
} as const

export type HelpTopic = keyof typeof HELP_PAGES

export const helpUrl = (topic: HelpTopic = 'index') => `/help/${HELP_PAGES[topic]}`
