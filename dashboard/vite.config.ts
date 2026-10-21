/// <reference types="vitest/config" />
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { handleYouTubeApi } from './api/youtube'

/** Serves /api/youtube locally, the same as the Netlify function does in production. */
const youtubeApi: Plugin = {
  name: 'youtube-api',
  configureServer(server) {
    server.middlewares.use(async (req, res, next) => {
      const url = new URL(req.originalUrl ?? '', 'http://localhost')
      // Exact match only: the browser also requests the source file /api/youtube.ts in dev.
      if (url.pathname !== '/api/youtube') return next()
      const response = await handleYouTubeApi(url)
      res.statusCode = response.status
      res.setHeader('Content-Type', 'application/json')
      res.end(await response.text())
    })
  },
}

export default defineConfig({
  plugins: [react(), youtubeApi],
  server: { port: 5173 },
  test: { include: ['src/**/*.test.ts'] },
})
