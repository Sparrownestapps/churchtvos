// Debug helper: runs the smoke package (.tmp/smoke/out) against the mock API for N seconds and prints the engine's log.
//   node tools/run_headless.mjs [seconds]   (build the smoke package first with `node tools/smoke.mjs pairing`)
import { startMock } from './mock_server.mjs'
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const out = path.join(root, '.tmp', 'smoke', 'out')
const mock = await startMock({ handle: (n) => (n === 'device_state' ? { paired: false, pairing_code: 'ABC234' } : null) })
const cfg = path.join(out, 'source/lib/Config.brs')
const text = fs.readFileSync(cfg, 'utf8')
fs.writeFileSync(cfg, text.replace(/http:\/\/127\.0\.0\.1:\d+/, `http://127.0.0.1:${mock.port}`))
const log = path.join(out, 'headless.log')
fs.rmSync(log, { force: true })
const child = spawn(path.join(root, 'node_modules/.bin/brs-cli'), ['-r', '.', '-l', 'headless.log', 'source/main.brs'], { cwd: out, stdio: 'ignore' })
await new Promise((r) => setTimeout(r, (Number(process.argv[2]) || 10) * 1000))
child.kill()
console.log(fs.existsSync(log) ? fs.readFileSync(log, 'utf8').split('\n').slice(0, 60).join('\n') : 'no log')
console.log('requests:', mock.state.requests.map((r) => r.name).join(','))
mock.server.close()
