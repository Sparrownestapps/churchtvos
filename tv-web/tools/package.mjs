// Packages the TV build (dist-tv, from `npm run build:tv`) for LG webOS (.ipk) and Samsung Tizen (.wgt).
// LG uses ares-package from @webos-tools/cli (a dev dependency). Samsung needs Tizen Studio's `tizen` CLI and a Samsung
// certificate profile (TIZEN_PROFILE, default "churchtvos"); without them the Tizen folder is prepared and the command printed.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import path from 'node:path'

const root = path.resolve(import.meta.dirname, '..')
const dist = path.join(root, 'dist-tv')
const pkg = path.join(root, '.pkg')
const out = path.join(root, 'out')
if (!existsSync(dist)) throw new Error('Run npm run build:tv first')
rmSync(pkg, { recursive: true, force: true })
mkdirSync(out, { recursive: true })

function stage(name, extra, editHtml) {
  const dir = path.join(pkg, name)
  cpSync(dist, dir, { recursive: true })
  cpSync(path.join(root, extra), dir, { recursive: true })
  const index = path.join(dir, 'index.html')
  // crossorigin makes Chromium refuse scripts loaded from local files (the TV loads the app from file://).
  writeFileSync(index, editHtml(readFileSync(index, 'utf8').replace(/ crossorigin/g, '')))
  return dir
}

// LG webOS
const webos = stage('webos', 'webos', (h) => h)
const ares = path.join(root, 'node_modules', '.bin', 'ares-package')
if (existsSync(ares)) {
  execFileSync(ares, ['--no-minify', '-o', out, webos], { stdio: 'inherit' })
} else {
  console.log(`LG: install @webos-tools/cli, then: ares-package -o ${out} ${webos}`)
}

// Samsung Tizen: webapis.js gives the app Samsung's TV features (screensaver control, model name).
const tizen = stage('tizen', 'tizen', (h) =>
  h.replace('<head>', '<head>\n    <script type="text/javascript" src="$WEBAPIS/webapis/webapis.js"></script>'))
const profile = process.env.TIZEN_PROFILE ?? 'churchtvos'
try {
  execFileSync('tizen', ['package', '-t', 'wgt', '-s', profile, '-o', out, '--', tizen], { stdio: 'inherit' })
} catch {
  console.log(`Samsung: install Tizen Studio and create the "${profile}" certificate profile, then:\n  tizen package -t wgt -s ${profile} -o ${out} -- ${tizen}`)
}
