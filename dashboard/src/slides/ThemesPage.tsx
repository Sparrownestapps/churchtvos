import { useMemo, useRef, useState } from 'react'
import '../slides.css'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { SlideTheme, ThemeConfig } from '../slidesTypes'
import { attempt, must } from '../lib'
import { ReadOnlyNote } from '../ui'
import BackgroundPicker, { ColorField } from './BackgroundPicker'
import { useDefaultColor, useLogoFor } from './DeckPreview'
import SlideFrame from './SlideFrame'
import { resolveBackground, resolveTheme, worstContrast, type Frame } from './render'
import { useSlidesLibrary, useThemes } from './data'
import { useUnsavedGuard, setUnsaved } from './unsaved'

type Preset = { id: string; name: string; blurb: string; config: ThemeConfig }

const PRESETS: Preset[] = [
  {
    id: 'classic',
    name: 'Classic dark blue',
    blurb: 'White text on deep blue. Safe everywhere.',
    config: { font: 'lato', title_scale: 1, body_scale: 1, text_color: '#FFFFFF', align: 'center', position: 'center', shadow: true, outline: false, margin: 8, show_labels: true, background: { type: 'color', color: '#1f3a5f' }, logo: { show: false, position: 'bottom_left' } },
  },
  {
    id: 'warm',
    name: 'Warm light',
    blurb: 'Dark text on a soft cream background.',
    config: { font: 'lato', title_scale: 1, body_scale: 1, text_color: '#2B2118', align: 'center', position: 'center', shadow: false, outline: false, margin: 8, show_labels: true, background: { type: 'color', color: '#F6EFE3' }, logo: { show: false, position: 'bottom_left' } },
  },
  {
    id: 'video',
    name: 'Video-ready',
    blurb: 'Shadow on and the background dimmed 40%, for words over a video or photo. Pick the video in the background below.',
    config: { font: 'lato', title_scale: 1, body_scale: 1, text_color: '#FFFFFF', align: 'center', position: 'center', shadow: true, outline: false, margin: 8, show_labels: true, background: { type: 'color', color: '#101820', dim: 0.4 }, logo: { show: false, position: 'bottom_left' } },
  },
]

const SAMPLES: { id: string; label: string; frame: Frame }[] = [
  { id: 'text', label: 'Text slide', frame: { kind: 'text', layout: 'title_body', title: 'Welcome to church', body: "We're glad you're here. Service starts at 10:00." } },
  { id: 'lyric', label: 'Lyrics', frame: { kind: 'lyric', label: 'Verse 1', text: 'Amazing grace, how sweet the sound\nThat saved a wretch like me', n: 1, count: 6 } },
  { id: 'lower', label: 'Lower third', frame: { kind: 'text', layout: 'lower_third', title: 'Pastor Keith', body: 'Worship Pastor' } },
]

const nameFree = (list: SlideTheme[], base: string) => {
  const taken = new Set(list.map((t) => t.name.toLowerCase()))
  if (!taken.has(base.toLowerCase())) return base
  for (let n = 2; ; n++) if (!taken.has(`${base} ${n}`.toLowerCase())) return `${base} ${n}`
}

/** A readable message for the unique-name rule. */
function themeError(e: { message: string }) {
  return /slide_themes_organization_id_name_key|duplicate key/.test(e.message) ? 'A theme with that name already exists. Choose another name.' : e.message
}

function ThemeThumb({ config }: { config: ThemeConfig }) {
  const fallback = useDefaultColor()
  const theme = useMemo(() => resolveTheme(config), [config])
  const bg = resolveBackground(undefined, null, config.background, fallback)
  const logo = useLogoFor(bg)
  return <SlideFrame frame={SAMPLES[0].frame} theme={theme} background={bg} logo={logo} />
}

export default function ThemesPage() {
  const { org, canEditContent } = useApp()
  const canEdit = canEditContent('slides', null)
  const themes = useThemes()
  const lib = useSlidesLibrary()
  const [editing, setEditing] = useState<{ theme: SlideTheme | null; name: string; config: ThemeConfig } | null>(null)

  if (editing)
    return (
      <ThemeEditor
        theme={editing.theme}
        initialName={editing.name}
        initialConfig={editing.config}
        others={(themes.data ?? []).filter((t) => t.id !== editing.theme?.id)}
        lib={lib}
        onDone={() => (setEditing(null), themes.reload())}
      />
    )

  const list = themes.data ?? []

  async function duplicate(t: SlideTheme) {
    const name = nameFree(list, `${t.name} (copy)`)
    const ok = await attempt(async () => {
      const res = await supabase.from('slide_themes').insert({ organization_id: org.id, name, config: t.config })
      if (res.error) throw new Error(themeError(res.error))
    })
    if (ok) themes.reload()
  }

  async function remove(t: SlideTheme) {
    if (!confirm(`Delete the theme "${t.name}"? Decks that use it will fall back to the default look (the church colour with white text). Their slides are not changed.`)) return
    const ok = await attempt(async () => {
      const rows = must(await supabase.from('slide_themes').delete().eq('id', t.id).eq('organization_id', org.id).select('id'))
      if (!rows?.length) throw new Error(`Couldn't delete "${t.name}". You may not have permission.`)
    })
    if (ok) themes.reload()
  }

  return (
    <div className="stack">
      {themes.error && <p className="error">Couldn't load themes: {themes.error}</p>}
      {!canEdit && <ReadOnlyNote />}
      {canEdit && (
        <div className="card stack-sm">
          <h3>New theme</h3>
          <p className="muted">A theme is a reusable look: fonts, colours, where the words sit, the background and the logo. Change a theme and every deck that uses it updates.</p>
          <div className="sl-presets">
            <button className="btn primary" onClick={() => setEditing({ theme: null, name: nameFree(list, 'New theme'), config: PRESETS[0].config })}>
              + Blank theme
            </button>
            {PRESETS.map((p) => (
              <button key={p.id} className="sl-preset" onClick={() => setEditing({ theme: null, name: nameFree(list, p.name), config: p.config })}>
                <b>Create from preset: {p.name}</b>
                <span className="muted">{p.blurb}</span>
              </button>
            ))}
          </div>
        </div>
      )}

      {themes.data && list.length === 0 && <p className="muted empty-state">No themes yet. Create one above, then choose it in a deck. Decks without a theme use the default look.</p>}

      {list.map((t) => (
        <div key={t.id} className="card row spread sl-deckrow">
          <div className="row sl-deckmain">
            <div className="sl-deckthumb static">
              <ThemeThumb config={t.config} />
            </div>
            <div>
              <h3>{t.name}</h3>
              <span className="muted">
                {t.config.font === 'julius' ? 'Julius' : 'Lato'} · text {t.config.text_color ?? '#FFFFFF'} · {t.config.background ? `${t.config.background.type} background` : 'default background'}
              </span>
            </div>
          </div>
          <div className="row wrap-sm">
            <button className="btn" onClick={() => setEditing({ theme: t, name: t.name, config: t.config })}>
              {canEdit ? 'Edit' : 'View'}
            </button>
            {canEdit && (
              <>
                <button className="btn" onClick={() => duplicate(t)}>
                  Duplicate
                </button>
                <button className="btn danger" onClick={() => remove(t)}>
                  Delete
                </button>
              </>
            )}
          </div>
        </div>
      ))}
    </div>
  )
}

function ThemeEditor({
  theme,
  initialName,
  initialConfig,
  others,
  lib,
  onDone,
}: {
  theme: SlideTheme | null
  initialName: string
  initialConfig: ThemeConfig
  others: SlideTheme[]
  lib: ReturnType<typeof useSlidesLibrary>
  onDone: () => void
}) {
  const { org, canEditContent } = useApp()
  const readOnly = !canEditContent('slides', null)
  const fallback = useDefaultColor()
  const [name, setName] = useState(initialName)
  const [cfg, setCfg] = useState<ThemeConfig>(() => ({ ...resolvedForEditing(initialConfig), background: initialConfig.background }))
  const [sample, setSample] = useState(SAMPLES[0].id)
  const [saving, setSaving] = useState(false)
  const [themeId, setThemeId] = useState<string | null>(theme?.id ?? null)

  const snap = (n: string, c: ThemeConfig) => JSON.stringify([n, c])
  const baseline = useRef(snap(initialName, { ...resolvedForEditing(initialConfig), background: initialConfig.background }))
  const dirty = !readOnly && snap(name, cfg) !== baseline.current
  useUnsavedGuard(dirty)

  const patch = (p: Partial<ThemeConfig>) => setCfg((c) => ({ ...c, ...p }))
  const resolved = useMemo(() => resolveTheme(cfg), [cfg])
  const bg = resolveBackground(undefined, null, cfg.background, fallback)
  const logo = useLogoFor(bg)
  const hasLogo = !!(org.branding.logo_url || org.branding.logo_dark_url)
  const ratio = worstContrast(resolved.textColor, bg)
  const frame = SAMPLES.find((s) => s.id === sample)!.frame

  async function save() {
    const n = name.trim()
    if (!n) return alert('Give the theme a name.')
    if (others.some((t) => t.name.toLowerCase() === n.toLowerCase())) return alert('A theme with that name already exists. Choose another name.')
    if (cfg.background && (cfg.background.type === 'image' || cfg.background.type === 'video') && !cfg.background.url) return alert('The background needs an image or video chosen (or set it back to the default).')
    const config: ThemeConfig = { ...cfg }
    if (!config.background) delete config.background
    setSaving(true)
    const ok = await attempt(async () => {
      const row = { organization_id: org.id, name: n, config }
      if (themeId) {
        const res = await supabase.from('slide_themes').update(row).eq('id', themeId).eq('organization_id', org.id).select('id')
        if (res.error) throw new Error(themeError(res.error))
        if (!res.data?.length) throw new Error("Couldn't save this theme. You may not have permission.")
      } else {
        const res = await supabase.from('slide_themes').insert(row).select('id').single()
        if (res.error) throw new Error(themeError(res.error))
        setThemeId((res.data as { id: string }).id)
      }
    })
    setSaving(false)
    if (ok) {
      baseline.current = snap(n, cfg)
      setName(n)
      setUnsaved(false)
      onDone()
    }
  }

  function leave() {
    if (dirty && !confirm('You have unsaved changes. Leave without saving?')) return
    setUnsaved(false)
    onDone()
  }

  return (
    <div className="stack">
      <div className="sl-work">
        <fieldset className="card stack sl-fieldset" disabled={readOnly}>
          <legend className="sr-only">Theme settings</legend>
          <label className="field">
            <span>Theme name</span>
            <input value={name} onChange={(e) => setName(e.target.value)} autoFocus={!theme} />
          </label>

          <div className="row wrap">
            <label className="field">
              <span>Font</span>
              <select value={cfg.font ?? 'lato'} onChange={(e) => patch({ font: e.target.value as 'lato' | 'julius' })}>
                <option value="lato">Lato (clean)</option>
                <option value="julius">Julius (classic)</option>
              </select>
            </label>
            <label className="field">
              <span>Align</span>
              <select value={cfg.align ?? 'center'} onChange={(e) => patch({ align: e.target.value as 'left' | 'center' })}>
                <option value="center">Centre</option>
                <option value="left">Left</option>
              </select>
            </label>
            <label className="field">
              <span>Where the text sits</span>
              <select value={cfg.position ?? 'center'} onChange={(e) => patch({ position: e.target.value as 'center' | 'lower' | 'top' })}>
                <option value="center">Middle</option>
                <option value="lower">Lower</option>
                <option value="top">Top</option>
              </select>
            </label>
          </div>

          <div className="row wrap">
            <label className="field grow">
              <span>Title size: {Math.round((cfg.title_scale ?? 1) * 100)}%</span>
              <input type="range" min={0.5} max={1.5} step={0.05} value={cfg.title_scale ?? 1} onChange={(e) => patch({ title_scale: Number(e.target.value) })} />
            </label>
            <label className="field grow">
              <span>Body size: {Math.round((cfg.body_scale ?? 1) * 100)}%</span>
              <input type="range" min={0.5} max={1.5} step={0.05} value={cfg.body_scale ?? 1} onChange={(e) => patch({ body_scale: Number(e.target.value) })} />
            </label>
            <label className="field grow">
              <span>Margin: {cfg.margin ?? 8}%</span>
              <input type="range" min={0} max={20} step={1} value={cfg.margin ?? 8} onChange={(e) => patch({ margin: Number(e.target.value) })} />
            </label>
          </div>
          <p className="help">Song lyrics use the title size. Text shrinks to fit when a slide has a lot of words.</p>

          <ColorField label="Text colour" value={cfg.text_color ?? '#FFFFFF'} onChange={(text_color) => patch({ text_color })} />
          {ratio !== null && ratio < 4.5 && (
            <p className="note warn" role="alert">
              Low contrast: this text colour on the background is {ratio.toFixed(1)}:1. Aim for 4.5:1 or more so it reads from the back of the room. Try a lighter or darker text colour, or a darker dim.
            </p>
          )}
          {ratio === null && cfg.background && <p className="help">The contrast check works for plain colours and gradients. With a picture or video, use the Dim slider so the words stay readable.</p>}

          <div className="row wrap">
            <label className="check">
              <input type="checkbox" checked={cfg.shadow ?? true} onChange={(e) => patch({ shadow: e.target.checked })} />
              Shadow behind text
            </label>
            <label className="check">
              <input type="checkbox" checked={cfg.outline ?? false} onChange={(e) => patch({ outline: e.target.checked })} />
              Dark outline on text
            </label>
            <label className="check">
              <input type="checkbox" checked={cfg.show_labels ?? true} onChange={(e) => patch({ show_labels: e.target.checked })} />
              Show section labels on lyric slides
            </label>
          </div>

          <div className="stack-sm">
            <span className="field-label">Church logo</span>
            <div className="row wrap">
              <label className="check">
                <input type="checkbox" checked={cfg.logo?.show ?? false} onChange={(e) => patch({ logo: { position: cfg.logo?.position ?? 'bottom_left', show: e.target.checked } })} />
                Show the church logo
              </label>
              <label className="field">
                <span>Corner</span>
                <select value={cfg.logo?.position ?? 'bottom_left'} disabled={!cfg.logo?.show} onChange={(e) => patch({ logo: { show: cfg.logo?.show ?? false, position: e.target.value as 'bottom_left' } })}>
                  <option value="bottom_left">Bottom left</option>
                  <option value="bottom_right">Bottom right</option>
                  <option value="top_left">Top left</option>
                  <option value="top_right">Top right</option>
                </select>
              </label>
            </div>
            {cfg.logo?.show && !hasLogo && <p className="note">Your church has no logo yet. Add one in Settings and it will appear here.</p>}
          </div>

          <div className="stack-sm">
            <span className="field-label">Default background</span>
            <BackgroundPicker value={cfg.background} onChange={(background) => patch({ background: background ?? undefined })} lib={lib} inheritLabel="Use default (church colour)" readOnly={readOnly} />
            <p className="help">A deck's background, or a slide's own, beats this one.</p>
          </div>
        </fieldset>

        <div className="card sl-preview-card stack-sm">
          <h3>Preview</h3>
          <div className="sl-seg" role="group" aria-label="Sample slide">
            {SAMPLES.map((s) => (
              <button key={s.id} type="button" className={sample === s.id ? 'on' : ''} aria-pressed={sample === s.id} onClick={() => setSample(s.id)}>
                {s.label}
              </button>
            ))}
          </div>
          <div className="sl-previews">
            <figure className="sl-fig land">
              <SlideFrame frame={frame} theme={resolved} background={bg} logo={logo} live />
              <figcaption className="muted">Landscape 16:9</figcaption>
            </figure>
            <figure className="sl-fig port">
              <SlideFrame frame={frame} theme={resolved} background={bg} logo={logo} portrait live />
              <figcaption className="muted">Portrait 9:16</figcaption>
            </figure>
          </div>
        </div>
      </div>

      <div className="row wrap">
        {!readOnly && (
          <button className="btn primary" onClick={save} disabled={saving}>
            {saving ? 'Saving…' : 'Save theme'}
          </button>
        )}
        <button className="btn" onClick={leave}>
          {readOnly ? 'Back' : 'Cancel'}
        </button>
        {dirty && <span className="muted" role="status">Unsaved changes</span>}
      </div>
    </div>
  )
}

/** Fills the config's blanks with the defaults so every control shows a real value (and the saved theme is complete). */
function resolvedForEditing(c: ThemeConfig): ThemeConfig {
  const r = resolveTheme(c)
  return {
    font: r.font,
    title_scale: r.titleScale,
    body_scale: r.bodyScale,
    text_color: r.textColor,
    align: r.align,
    position: r.position,
    shadow: r.shadow,
    outline: r.outline,
    margin: r.margin,
    show_labels: r.showLabels,
    logo: r.logo,
  }
}
