// The publishable key is safe to ship in the app; database rules control what it can do.
export const SUPABASE_URL = 'https://gqkefjngblgomuovaivj.supabase.co'
export const SUPABASE_KEY = 'sb_publishable_NdKbJRGxQykmJuV9OTLdXg_qkKSwlQy'
export const DASHBOARD_HOST = 'app.churchtvos.com'

/** Shown in Settings. */
export const APP_VERSION = '1.0.0'

/**
 * Sent to the server as register_device's p_app_version. The server gates features on the leading number
 * (Slides needs 1.4.0+, new-style lyrics 1.3.0+), so this is the Android protocol level this app implements,
 * with a platform suffix the dashboard shows. Bump it when Android gains protocol features this app supports.
 */
export const REPORTED_APP_VERSION = '1.7.0-vega'
