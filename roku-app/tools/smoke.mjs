// Headless smoke test of the whole app: SceneGraph components, tasks, views, remote control, against a mock of the device API.
// Runs the compiled app in the brs-node engine (an interpreter, NOT a Roku: timing, fonts and video differ), drives it with
// ECP key presses and writes screenshots to .tmp/shots/<scenario>/. It never contacts the real Supabase project.
//   node tools/smoke.mjs [scenario ...]      scenarios: pairing kids deck signage settings portrait
import { startMock } from './mock_server.mjs'
import { spawn, spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const iso = (ms) => new Date(ms).toISOString().replace('.000Z', '+00:00')

function pkgDir(port) {
  const smoke = path.join(root, '.tmp', 'smoke')
  fs.rmSync(smoke, { recursive: true, force: true })
  fs.mkdirSync(smoke, { recursive: true })
  for (const d of ['source', 'components', 'fonts', 'images', 'manifest', 'bsconfig.json', 'bslint.json']) fs.cpSync(path.join(root, d), path.join(smoke, d), { recursive: true })
  const cfgPath = path.join(smoke, 'source/lib/Config.bs')
  fs.writeFileSync(cfgPath, fs.readFileSync(cfgPath, 'utf8').replace('https://gqkefjngblgomuovaivj.supabase.co', `http://127.0.0.1:${port}`))
  const c = spawnSync(path.join(root, 'node_modules/.bin/bsc'), ['--project', 'bsconfig.json', '--cwd', smoke, '--createPackage=false', '--stagingDir', path.join(smoke, 'out')], { cwd: smoke, encoding: 'utf8' })
  if (c.status !== 0) throw new Error('smoke build failed\n' + c.stdout + c.stderr)
  return path.join(smoke, 'out')
}

function sampleState({ module = 'kids', orientation = 'landscape', port }) {
  const now = Date.now()
  const media = `http://127.0.0.1:${port}/media`
  const bgDeck = { type: 'gradient', color: '#1B2A4A', color2: '#7A1F5C', angle: 135 }
  const deck = {
    id: 'deck-1', name: 'Sunday service', loop: true,
    theme: { font: 'julius', text_color: '#FFFFFF', align: 'center', position: 'center', shadow: true, margin: 8, show_labels: true, logo: { show: false, position: 'bottom_left' } },
    background: bgDeck,
    slides: [
      { kind: 'text', id: 't1', title: 'Welcome to Forward Church', body: 'We are glad you are here.\nPlease silence your phones.', layout: 'title_body' },
      { kind: 'song_title', title: 'Amazing Grace', authors: 'John Newton', ccli: '22025', copyright: 'Public Domain' },
      { kind: 'lyric', song: 'Amazing Grace', text: 'Amazing grace, how sweet the sound\nThat saved a wretch like me', label: 'Verse 1', number: 1, count: 2 },
      { kind: 'text', id: 't2', title: 'Announcements', layout: 'lower_third', body: 'Kids camp registration closes Friday', background: { type: 'image', url: `${media}/bg.png`, dim: 0.35 } },
      { kind: 'media', id: 'm1', url: `${media}/pic.png`, media_kind: 'image', fit: 'contain', seconds: 5 },
      { kind: 'countdown', id: 'c1', title: 'Service starts in', mode: 'duration', seconds: 125, at_zero: 'hold' },
      { kind: 'blank', id: 'b1' },
    ],
  }
  const playlist = {
    id: 'pl-1', name: 'Week 3: Noah and the Ark',
    items: [
      { type: 'countdown', title: 'Service starts in', seconds: 90, mode: 'duration', at_zero: 'hold' },
      { type: 'lyrics', title: 'Sample song', slides: ['Verse one\nlines of words', 'Chorus\nsing along'], show_title: true, authors: 'A. Writer' },
      { type: 'image', title: 'Picture', url: `${media}/pic.png`, seconds: 6 },
      { type: 'sign', title: 'Parents: pickup is at the front door', subtext: 'Show your tag', background: '#FFD700', seconds: 8 },
      { type: 'youtube', title: 'A YouTube clip', video_id: 'abc' },
    ],
  }
  const signage = { id: 'sg-1', name: 'Lobby loop', items: [{ type: 'image', title: 'Welcome', url: `${media}/pic.png`, seconds: 6 }, { type: 'sign', title: 'Coffee is in the foyer', subtext: 'Everyone welcome', background: '#1B2A4A', seconds: 6 }] }
  return {
    paired: true,
    organization: { name: 'Forward Church', status: 'active', branding: { primary_color: '#1B2A4A', accent_color: '#F2A33A' } },
    experimental: { ndi: false }, site: 'Cambridge', location: 'Room 201', timezone: 'UTC',
    screen: { name: 'Kids TV', orientation, autoplay: false },
    enabled_modules: ['kids', 'signage', 'slides'], default_module: module, module_rules: [],
    kids: { schedules: [{ id: 'k1', starts_at: iso(now - 3600e3), ends_at: iso(now + 3600e3), playlist }] },
    signage: { slots: [], default_playlist: signage },
    slides: { schedules: [{ id: 'd1', starts_at: iso(now - 3600e3), ends_at: null, deck }] },
    override: null,
  }
}

const scenarios = {
  pairing: { module: 'kids', unpaired: true, steps: [['wait', 5], ['shot', '01-pairing.png']] },
  kids: { module: 'kids', steps: [['wait', 6], ['shot', '01-home.png'], ['key', 'Select'], ['wait', 2], ['shot', '02-countdown.png'], ['key', 'Right'], ['wait', 1.5], ['shot', '03-songtitle.png'], ['key', 'Right'], ['wait', 1.5], ['shot', '04-lyric.png'], ['key', 'Right'], ['key', 'Right'], ['wait', 1.5], ['shot', '05-sign.png']] },
  deck: { module: 'slides', steps: [['wait', 6], ['shot', '01-home.png'], ['key', 'Select'], ['wait', 2], ['shot', '02-text.png'], ['key', 'Right'], ['wait', 1.5], ['shot', '03-songtitle.png'], ['key', 'Right'], ['wait', 1.5], ['shot', '04-lyric.png'], ['key', 'Right'], ['wait', 2], ['shot', '05-lowerthird.png'], ['key', 'Select'], ['wait', 1], ['shot', '06-slidelist.png']] },
  signage: { module: 'signage', steps: [['wait', 6], ['shot', '01-signage.png'], ['wait', 7], ['shot', '02-signage.png']] },
  settings: { module: 'kids', steps: [['wait', 6], ['key', 'Info'], ['wait', 1.5], ['shot', '01-settings.png']] },
  portrait: { module: 'kids', orientation: 'portrait', steps: [['wait', 6], ['shot', '01-home.png'], ['key', 'Select'], ['wait', 2], ['shot', '02-countdown.png']] },
  // remote control: commands from the (mock) server drive the player, and the status the TV reports is checked afterwards
  remote: {
    module: 'kids',
    steps: [['wait', 6], ['key', 'Select'], ['wait', 3], ['cmd', { id: 1, command: 'next' }], ['wait', 4], ['shot', '01-after-next.png'],
      ['cmd', { id: 2, command: 'blank', payload: { on: true } }], ['wait', 4], ['shot', '02-blank.png'],
      ['cmd', { id: 3, command: 'blank', payload: { on: false } }], ['cmd', { id: 4, command: 'jump', payload: { index: 4 } }], ['wait', 4], ['shot', '03-jumped.png'],
      ['cmd', { id: 5, command: 'message', payload: { text: 'Parents: please come to the front', seconds: 30, background: '#B00020' } }], ['wait', 4], ['shot', '04-message.png'],
      ['cmd', { id: 6, command: 'clear_message' }], ['wait', 4], ['cmd', { id: 7, command: 'bogus' }], ['cmd', { id: 8, command: 'stop' }], ['wait', 5], ['shot', '05-stopped.png']],
    check: (reports) => {
      const seq = reports.map((r) => `${r.p_state}:${r.p_slide_index}`)
      const must = ['playing:0', 'playing:1', 'blank:1', 'playing:4', 'message:4', 'idle:0']
      const missing = must.filter((m) => !seq.includes(m))
      return { ok: missing.length === 0, detail: `reports ${seq.join(' ')}; missing ${missing.join(',') || 'none'}` }
    },
  },
  // a remote asks for a deck to play now (override), then stops it
  override: {
    module: 'kids',
    steps: [['wait', 6], ['patch', 'override'], ['cmd', { id: 1, command: 'start' }], ['wait', 8], ['shot', '01-override.png'], ['cmd', { id: 2, command: 'stop' }], ['wait', 5], ['shot', '02-after-stop.png']],
    check: (reports) => {
      const seq = reports.map((r) => `${r.p_module}:${r.p_state}:${r.p_ref_kind || ''}`)
      return { ok: seq.includes('slides:playing:deck'), detail: seq.join(' ') }
    },
  },
  // the server disappears: the TV keeps its saved schedule and says so
  offline: { module: 'kids', steps: [['wait', 6], ['fail', true], ['wait', 36], ['shot', '01-offline-home.png']] },
  // first run, pairing screen to Settings to the bundled demo, then out again
  demo: { module: 'kids', unpaired: true, steps: [['wait', 6], ['key', 'Select'], ['wait', 2], ['shot', '01-settings.png'], ['key', 'Down'], ['key', 'Select'], ['wait', 2], ['shot', '02-demomenu.png'], ['key', 'Select'], ['wait', 3], ['shot', '03-demo.png'], ['key', 'Back'], ['wait', 2], ['shot', '04-after-demo.png']] },
}

async function ecp(key) {
  try { await fetch(`http://127.0.0.1:8060/keypress/${key}`, { method: 'POST' }) } catch (e) { console.log('ecp failed', key, e.message) }
}

const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(scenarios)
let failures = 0
for (const name of names) {
  const sc = scenarios[name]
  const media = fs.readFileSync(path.join(root, 'images', 'demo_welcome.png'))
  let port = 0
  const mock = await startMock({
    media,
    handle: (rpc, params, st) => {
      if (rpc === 'device_state') {
        if (st.fail) return undefined
        if (sc.unpaired) return { paired: false, pairing_code: 'ABC234' }
        return Object.assign(sampleState({ module: sc.module, orientation: sc.orientation || 'landscape', port }), st.patch || {})
      }
      return null
    },
  })
  port = mock.port
  const stage = pkgDir(mock.port)
  const outDir = path.join(root, '.tmp', 'shots', name)
  fs.rmSync(outDir, { recursive: true, force: true })
  const waiters = []
  const ready = new Promise((resolve) => waiters.push(resolve))
  const driver = spawn('python3', [path.join(root, 'tools', 'pty_driver.py'), stage, outDir], { stdio: ['pipe', 'pipe', 'inherit'] })
  let buf = ''
  driver.stdout.on('data', (d) => { buf += d; while (buf.includes('\n')) { const i = buf.indexOf('\n'); const line = buf.slice(0, i); buf = buf.slice(i + 1); const w = waiters.shift(); if (w) w(line) } })
  const cmd = (line) => new Promise((resolve) => { waiters.push(resolve); driver.stdin.write(line + '\n') })
  await ready
  for (const [kind, arg] of sc.steps) {
    if (kind === 'wait') await sleep(arg * 1000)
    else if (kind === 'cmd') mock.state.commands.push(arg)
    else if (kind === 'fail') mock.state.fail = arg
    else if (kind === 'patch') {
      const now = Date.now()
      mock.state.patch = { override: { kind: 'deck', until: iso(now + 600e3), deck: { id: 'od', name: 'Announcement deck', loop: false, theme: {}, slides: [{ kind: 'text', id: 'o1', title: 'Heads up', body: 'This was sent from a phone', layout: 'title_body' }] } } }
      }
    else if (kind === 'key') await ecp(arg)
    else if (kind === 'shot') console.log(name, await cmd('shot ' + arg))
  }
  driver.stdin.write('quit\n')
  await sleep(500)
  driver.kill()
  spawnSync('pkill', ['-f', 'brs-cli'])
  const names2 = mock.state.requests.map((r) => r.name)
  const count = (n) => names2.filter((x) => x === n).length
  console.log(`${name}: requests register=${count('register_device')} state=${count('device_state')} poll=${count('device_poll_commands')} report=${count('device_report_status')}`)
  const bad = mock.state.requests.filter((r) => r.apikey !== 'sb_publishable_NdKbJRGxQykmJuV9OTLdXg_qkKSwlQy')
  if (bad.length) { console.log('requests without the publishable key:', bad.length); failures++ }
  if (sc.check) {
    const reports = mock.state.requests.filter((r) => r.name === 'device_report_status').map((r) => r.params)
    const res = sc.check(reports)
    console.log(`${name} check: ${res.ok ? 'OK' : 'FAILED'} - ${res.detail}`)
    if (!res.ok) failures++
  }
  const reg = mock.state.requests.find((r) => r.name === 'register_device')
  if (reg) console.log('register_device params:', JSON.stringify({ ...reg.params, p_secret: '<hidden>' }))
  mock.server.close()
  await sleep(500)
}
process.exit(failures ? 1 : 0)
