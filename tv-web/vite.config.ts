// The web player: the Vega app's screens and logic (../vega-app/src) running on react-native-web, with a web platform
// layer (src/platform) in place of the Vega one. Used in a browser, and packaged for LG webOS and Samsung Tizen TVs.
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import legacy from '@vitejs/plugin-legacy'
import path from 'node:path'

const here = __dirname
/** TV packages load from local files, where module scripts can be blocked, so they get the classic-script build only. */
const tvBuild = process.env.TV_BUILD === '1'
const shared = path.resolve(here, '../vega-app/src')
const webPlatform = path.resolve(here, 'src/platform/index.tsx')
const mod = (name: string) => path.resolve(here, 'node_modules', name)

/** The shared code imports '../platform' or './platform'; in this build that is the web platform layer. */
function webPlatformSwap(): Plugin {
  return {
    name: 'church-tv-os-web-platform',
    enforce: 'pre',
    resolveId(source, importer) {
      if (!importer || !importer.startsWith(shared)) return null
      if (source === '../platform' || source === './platform') return webPlatform
      return null
    },
  }
}

export default defineConfig({
  // Relative paths so the same build works from a web server and from a packaged TV app (file://).
  base: './',
  plugins: [
    webPlatformSwap(),
    react(),
    // LG webOS 5 (2020) runs Chromium 68 and Samsung Tizen 5.5 (2020) Chromium 69.
    legacy({ targets: ['chrome >= 68'], renderLegacyChunks: true, renderModernChunks: !tvBuild, modernPolyfills: !tvBuild }),
  ],
  resolve: {
    alias: [
      { find: /^react-native$/, replacement: mod('react-native-web') },
      // One copy of each library, even for files that live in ../vega-app.
      { find: /^react$/, replacement: mod('react') },
      { find: /^react\/jsx-runtime$/, replacement: mod('react/jsx-runtime.js') },
      { find: /^react\/jsx-dev-runtime$/, replacement: mod('react/jsx-dev-runtime.js') },
      { find: /^react-dom$/, replacement: mod('react-dom') },
      { find: /^react-dom\/client$/, replacement: mod('react-dom/client.js') },
      { find: /^qrcode\/lib\/core\/qrcode$/, replacement: mod('qrcode/lib/core/qrcode.js') },
    ],
    extensions: ['.web.tsx', '.web.ts', '.tsx', '.ts', '.mjs', '.js', '.json'],
  },
  optimizeDeps: {
    include: ['react-native-web', 'qrcode/lib/core/qrcode.js', 'hls.js'],
    esbuildOptions: { resolveExtensions: ['.web.js', '.js', '.ts', '.tsx'] },
  },
  define: { __DEV__: 'false', 'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV ?? 'production') },
  server: { port: 5175, fs: { allow: [path.resolve(here, '..')] } },
  build: { outDir: tvBuild ? 'dist-tv' : 'dist', assetsInlineLimit: 0, sourcemap: false },
})
