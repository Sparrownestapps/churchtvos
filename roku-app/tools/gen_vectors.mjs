// Generates tests/fixtures/vectors.json: reference answers from independent implementations
// (the `qrcode` npm package for QR modules, Node's Intl time zone data for offsets and wall-clock times).
// The BrightScript tests (tests/main.bs) run the same inputs through the Roku code and compare.
import QRCode from 'qrcode'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const out = path.join(here, '..', 'tests', 'fixtures', 'vectors.json')

// ---- QR ----
const payloads = [
  'https://app.churchtvos.com/pair?code=ABC123',
  'https://app.churchtvos.com/pair?code=ZZ9X7K',
  'https://app.churchtvos.com/pair?code=234567',
  'https://app.churchtvos.com/pair?code=QWERTY',
  'HELLO',
  'a',
  'Church TV OS',
  'https://example.com/a/much/longer/path/that/needs/a/higher/version?x=1234567890&y=abcdefghijklmnop',
  'https://churchtvos.com',
  '0123456789012345678901234567890123456789',
]
const qr = payloads.map((text) => {
  const q = QRCode.create([{ data: text, mode: 'byte' }], { errorCorrectionLevel: 'M' })
  const size = q.modules.size
  const rows = []
  for (let r = 0; r < size; r++) {
    let line = ''
    for (let c = 0; c < size; c++) line += q.modules.data[r * size + c] ? '1' : '0'
    rows.push(line)
  }
  return { text, version: q.version, mask: q.maskPattern, size, rows }
})

// ---- time zones ----
const zones = ['America/Toronto', 'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles', 'America/Vancouver',
  'America/Halifax', 'America/St_Johns', 'America/Phoenix', 'America/Regina', 'America/Edmonton', 'America/Winnipeg', 'America/Anchorage',
  'Pacific/Honolulu', 'Europe/London', 'Europe/Paris', 'Europe/Berlin', 'Europe/Athens', 'Europe/Lisbon', 'Australia/Sydney',
  'Australia/Adelaide', 'Australia/Brisbane', 'Pacific/Auckland', 'Asia/Kolkata', 'Asia/Tokyo', 'UTC']

const fmtCache = new Map()
function fmt(kind, zone, opts, locale) {
  const k = kind + zone
  if (!fmtCache.has(k)) fmtCache.set(k, new Intl.DateTimeFormat(locale, { timeZone: zone, ...opts }))
  return fmtCache.get(k)
}

function offsetMinutes(zone, ms) {
  const f = fmt('o', zone, { hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric', second: 'numeric' }, 'en-US')
  const p = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]))
  const asUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second)
  return Math.round((asUtc - Math.floor(ms / 1000) * 1000) / 60000)
}

const tz = []
const start = Date.UTC(2025, 0, 1)
const end = Date.UTC(2031, 0, 1)
for (const zone of zones) {
  // every 2 days at an odd hour, plus +-1h around every offset change found by scanning hourly
  let prev = offsetMinutes(zone, start)
  for (let t = start; t < end; t += 3600 * 1000) {
    const o = offsetMinutes(zone, t)
    if (o !== prev) {
      for (const d of [-3600, -1, 0, 1, 3600]) tz.push([zone, Math.floor(t / 1000) + d, offsetMinutes(zone, t + d * 1000)])
      prev = o
    }
  }
  for (let t = start + 7 * 3600 * 1000; t < end; t += 2 * 86400 * 1000 + 3600 * 1000) tz.push([zone, Math.floor(t / 1000), offsetMinutes(zone, t)])
}

// ---- wall-clock "until HH:MM today" ----
function localDate(zone, ms) {
  const f = fmt('d', zone, { year: 'numeric', month: '2-digit', day: '2-digit' }, 'en-CA')
  return f.format(new Date(ms))
}
function localHM(zone, ms) {
  const f = fmt('h', zone, { hourCycle: 'h23', hour: '2-digit', minute: '2-digit' }, 'en-GB')
  return f.format(new Date(ms))
}
const until = []
const nows = [
  Date.UTC(2026, 0, 14, 15, 0, 0), Date.UTC(2026, 2, 8, 4, 0, 0), Date.UTC(2026, 2, 8, 15, 30, 0), Date.UTC(2026, 2, 29, 12, 0, 0),
  Date.UTC(2026, 10, 1, 4, 30, 0), Date.UTC(2026, 10, 1, 13, 0, 0), Date.UTC(2026, 9, 22, 21, 0, 0), Date.UTC(2026, 9, 25, 12, 0, 0),
  Date.UTC(2026, 3, 5, 12, 0, 0), Date.UTC(2026, 6, 1, 0, 30, 0),
]
for (const zone of ['America/Toronto', 'America/Los_Angeles', 'Europe/London', 'Australia/Sydney', 'America/Phoenix', 'Asia/Kolkata']) {
  for (const now of nows) {
    for (const hm of ['09:00', '10:30', '00:15', '23:45', '02:30', '01:30', '12:00']) {
      const day = localDate(zone, now)
      // brute force: earliest minute within +-36h of now whose local date and HH:MM match
      let found = null
      for (let t = now - 36 * 3600 * 1000; t <= now + 36 * 3600 * 1000; t += 60 * 1000) {
        if (localDate(zone, t) === day && localHM(zone, t) === hm) { found = t; break }
      }
      if (found !== null) until.push([zone, Math.floor(now / 1000), hm, Math.floor(found / 1000)])
    }
  }
}

// ---- ISO parsing ----
const iso = [
  '2026-10-22T14:00:00+00:00', '2026-10-22T14:00:00Z', '2026-10-22T10:00:00-04:00', '2026-10-22T14:00:00.123456+00:00',
  '2026-03-08T07:30:15.5Z', '2026-01-01T00:00:00+05:30', '2024-02-29T23:59:59-0800', '2026-10-22 14:00:00+00',
  '1999-12-31T23:59:59Z', '2030-06-15T12:00:00.000-07:00',
].map((s) => [s, Math.floor(Date.parse(s.replace(' ', 'T').replace(/([+-]\d\d)$/, '$1:00').replace(/([+-]\d\d)(\d\d)$/, '$1:$2')) / 1000)])

fs.writeFileSync(out, JSON.stringify({ qr, tz, until, iso }))
console.log(`wrote ${out}: ${qr.length} qr, ${tz.length} tz, ${until.length} until, ${iso.length} iso`)
