// Sideloads dist/church-tv-os-roku-1.0.0.zip to a Roku in developer mode through its dev installer (http://<ip>/plugin_install,
// digest auth, user "rokudev"). Reads ROKU_IP and ROKU_DEV_PASSWORD from the environment ONLY. The password is never written
// to disk or printed. Usage:  ROKU_IP=192.168.1.50 ROKU_DEV_PASSWORD=... npm run deploy   (run `npm run package` first)
import { rokuDeploy } from 'roku-deploy'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..')
const host = process.env.ROKU_IP
const password = process.env.ROKU_DEV_PASSWORD
if (!host || !password) {
  console.error('Set ROKU_IP and ROKU_DEV_PASSWORD in the environment (the password is the one you chose when enabling developer mode).')
  process.exit(2)
}
const zip = path.join(root, 'dist', 'church-tv-os-roku-1.0.0.zip')
if (!fs.existsSync(zip)) {
  console.error('dist/church-tv-os-roku-1.0.0.zip not found. Run `npm run package` first.')
  process.exit(2)
}
try {
  await rokuDeploy.publish({ host, password, outDir: path.join(root, 'dist'), outFile: 'church-tv-os-roku-1.0.0.zip', username: 'rokudev' })
  console.log(`Installed on ${host}. Logs: telnet ${host} 8085`)
} catch (e) {
  console.error('Deploy failed:', String(e.message || e).replaceAll(password, '***'))
  process.exit(1)
}
