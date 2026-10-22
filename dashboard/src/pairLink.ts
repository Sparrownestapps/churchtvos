/** QR / link pairing: https://app.churchtvos.com/pair?code=ABC123 (shared contract with the TV and iOS apps). */

/** The pairing code from a /pair URL's query string, uppercased without spaces, or null if it is not a 6-character code. */
export function pairCodeFromSearch(search: string): string | null {
  const raw = new URLSearchParams(search).get('code') ?? ''
  const code = raw.replace(/\s/g, '').toUpperCase()
  return /^[A-Z0-9]{6}$/.test(code) ? code : null
}

export const isPairPath = (pathname: string) => pathname.replace(/\/+$/, '') === '/pair'

/** Turns the database's pairing errors into plain language. */
export function friendlyPairError(message: string): string {
  if (/No TV is showing code/i.test(message))
    return "That code isn't showing on any TV. Codes change when the TV restarts or is unpaired. Check the code on the TV and try again."
  if (/allows \d+ TV/i.test(message)) return `${message} (Screens > remove a TV, or see Billing.)`
  if (/no active plan/i.test(message)) return message
  if (/access to that location/i.test(message)) return "You don't have access to that location. Ask an owner or admin of this church to pair the TV."
  return message
}
