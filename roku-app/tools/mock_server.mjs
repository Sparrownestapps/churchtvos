// A tiny stand-in for the Supabase REST API (only the device functions), used by the headless smoke test.
// It never talks to the real project. `handle(name, params, state)` returns the JSON answer for an RPC; /media/* serves `media`.
import http from 'node:http'

export function startMock({ handle, media } = {}) {
  const state = { requests: [], stateCalls: 0, commands: [] }
  const server = http.createServer((req, res) => {
    if (req.url.startsWith('/media/') && media) {
      res.writeHead(200, { 'Content-Type': 'image/png' })
      res.end(media)
      return
    }
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => {
      const name = req.url.split('/rpc/')[1]
      let params = {}
      try { params = JSON.parse(body || '{}') } catch { /* ignore */ }
      state.requests.push({ name, params, apikey: req.headers['apikey'] })
      if (name === 'device_state') state.stateCalls++
      if (state.fail && name) {
        res.writeHead(503, { 'Content-Type': 'application/json' })
        res.end('{"message":"mock outage"}')
        return
      }
      let out = null
      if (name === 'device_poll_commands') out = state.commands.splice(0)
      else if (handle) out = handle(name, params, state)
      res.writeHead(name ? 200 : 404, { 'Content-Type': 'application/json' })
      res.end(out === null || out === undefined ? '' : JSON.stringify(out))
    })
  })
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, state, port: server.address().port })))
}
