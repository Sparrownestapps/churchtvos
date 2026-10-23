// Decodes every QR matrix in tests/fixtures/vectors.json with the jsQR decoder (a third implementation) and checks the text.
// Because the BrightScript tests prove the Roku encoder matches these matrices module for module, a pass here means the
// Roku encoder's output scans as the intended text.
import jsQR from 'jsqr'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const v = JSON.parse(fs.readFileSync(path.join(here, '..', 'tests', 'fixtures', 'vectors.json'), 'utf8'))
let bad = 0
for (const q of v.qr) {
  const scale = 8, quiet = 4
  const n = q.size + quiet * 2
  const w = n * scale
  const data = new Uint8ClampedArray(w * w * 4).fill(255)
  for (let r = 0; r < q.size; r++) for (let c = 0; c < q.size; c++) {
    if (q.rows[r][c] !== '1') continue
    for (let y = 0; y < scale; y++) for (let x = 0; x < scale; x++) {
      const i = (((r + quiet) * scale + y) * w + (c + quiet) * scale + x) * 4
      data[i] = data[i + 1] = data[i + 2] = 0
    }
  }
  const got = jsQR(data, w, w)
  const ok = got && got.data === q.text
  if (!ok) { bad++; console.log('DECODE FAIL', q.text, got && got.data) }
}
console.log(bad === 0 ? `QR decode check: ${v.qr.length}/${v.qr.length} decode to the intended text` : `QR decode check: ${bad} failures`)
process.exit(bad ? 1 : 0)
