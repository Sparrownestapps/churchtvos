import { useMemo } from 'react'
import { useApp } from '../context'
import { supabase } from '../supabase'
import type { Media, MediaFolder } from '../types'
import type { SlideTheme } from '../slidesTypes'
import type { SlidesLibrary, SongForSlides } from '../slidesPages.types'
import { fetchAll, must, useLoad } from '../lib'

/** The Slides media library (files and folders with module = 'slides'). */
export function useSlidesLibrary(): SlidesLibrary | undefined {
  const { org } = useApp()
  const { data, reload } = useLoad(async () => {
    const [media, folders] = await Promise.all([
      fetchAll<Media>((a, b) => supabase.from('media').select('*').eq('organization_id', org.id).eq('module', 'slides').order('title').order('id').range(a, b)),
      fetchAll<MediaFolder>((a, b) => supabase.from('media_folders').select('*').eq('organization_id', org.id).eq('module', 'slides').order('name').order('id').range(a, b)),
    ])
    return { media, folders }
  }, [org.id])
  return useMemo(() => (data ? { ...data, reload } : undefined), [data, reload])
}

/** The church's themes, by name. */
export function useThemes() {
  const { org } = useApp()
  return useLoad(async () => {
    const rows = must(await supabase.from('slide_themes').select('*').eq('organization_id', org.id).order('name'))
    return rows as SlideTheme[]
  }, [org.id])
}

/** Library songs with what Slides needs. The song library is optional: if it can't be read the list is empty. */
export function useSongs() {
  const { org } = useApp()
  return useLoad(async () => {
    try {
      return await fetchAll<SongForSlides>((a, b) =>
        supabase.from('songs').select('id,title,authors,ccli_number,copyright,sections,arrangement,lines_per_slide').eq('organization_id', org.id).order('title').range(a, b),
      )
    } catch {
      return [] as SongForSlides[]
    }
  }, [org.id])
}
