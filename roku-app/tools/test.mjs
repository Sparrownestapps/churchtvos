// `npm test`: lays the pure-logic sources and tests out like a tiny Roku app in .tmp/testsrc, compiles it with the BrighterScript
// compiler (same strictness and lint rules as the real build), and runs it under the brs-node BrightScript interpreter.
// Nothing here talks to a Roku device. Exit code 0 only when every test passed.
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const src = path.join(root, '.tmp', 'testsrc')
const out = path.join(root, '.tmp', 'test')
const bin = (n) => path.join(root, 'node_modules', '.bin', n)

fs.rmSync(path.join(root, '.tmp'), { recursive: true, force: true })
fs.mkdirSync(path.join(src, 'source', 'tests'), { recursive: true })
fs.cpSync(path.join(root, 'source', 'lib'), path.join(src, 'source', 'lib'), { recursive: true })
fs.cpSync(path.join(root, 'tests', 'fixtures'), path.join(src, 'tests', 'fixtures'), { recursive: true })
fs.copyFileSync(path.join(root, 'tests', 'main.bs'), path.join(src, 'source', 'main.bs'))
for (const f of fs.readdirSync(path.join(root, 'tests'))) {
  if (f.endsWith('.bs') && f !== 'main.bs') fs.copyFileSync(path.join(root, 'tests', f), path.join(src, 'source', 'tests', f))
}
fs.copyFileSync(path.join(root, 'bslint.json'), path.join(src, 'bslint.json'))
fs.writeFileSync(path.join(src, 'bsconfig.json'), JSON.stringify({
  rootDir: '.', files: ['source/**/*.*', 'tests/**/*.*'], stagingDir: path.join(root, '.tmp', 'test'),
  createPackage: false, retainStagingDir: true, sourceMap: false, diagnosticFilters: [1013], plugins: ['@rokucommunity/bslint'],
}))

const c = spawnSync(bin('bsc'), ['--project', 'bsconfig.json', '--cwd', src], { encoding: 'utf8', cwd: src })
const compileOut = (c.stdout || '') + (c.stderr || '')
const problems = compileOut.split('\n').filter((l) => / - (error|warning) /.test(l))
if (problems.length) process.stdout.write(compileOut)
if (c.status !== 0) { console.error('COMPILE FAILED'); process.exit(1) }
if (problems.length) { console.error('Compiler warnings in test build, treating them as failures'); process.exit(1) }

const files = []
const walk = (d) => {
  for (const f of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, f.name)
    if (f.isDirectory()) walk(p)
    else if (f.name.endsWith('.brs')) files.push(path.relative(out, p))
  }
}
walk(out)
const r = spawnSync(bin('brs-cli'), ['-n', '-r', '.', ...files], { encoding: 'utf8', timeout: 900000, cwd: out })
process.stdout.write(r.stdout || '')
process.stderr.write(r.stderr || '')
const qr = spawnSync('node', [path.join(root, 'tools', 'verify_qr_decode.mjs')], { encoding: 'utf8' })
process.stdout.write(qr.stdout || '')
process.exit((r.stdout || '').includes('RESULT: PASS') && qr.status === 0 ? 0 : 1)
