import * as tus from 'tus-js-client'
import { SUPABASE_KEY, SUPABASE_URL, supabase } from '../supabase'
import { randomName } from '../lib'
import type { Media, Module } from '../types'

/**
 * Uploads one file into a module's media library (the same resumable upload and `media` row as the Media page) and
 * returns the new row. Throws a readable message; an unlisted file is removed again if the row cannot be written.
 */
export async function uploadMedia(opts: {
  file: File
  orgId: string
  module: Module
  folderId: string | null
  siteId: string | null
  onProgress?: (percent: number) => void
  signal?: AbortSignal
}): Promise<Media> {
  const { file, orgId, module, folderId, siteId, onProgress, signal } = opts
  const kind: Media['kind'] | null = file.type.startsWith('video/') ? 'video' : file.type.startsWith('image/') ? 'image' : file.type.startsWith('audio/') ? 'audio' : null
  if (!kind) throw new Error('Only videos, images and audio can be uploaded.')
  const path = `${orgId}/${randomName(file.name)}`
  try {
    const { data } = await supabase.auth.getSession()
    await new Promise<void>((resolve, reject) => {
      const upload = new tus.Upload(file, {
        endpoint: `${SUPABASE_URL}/storage/v1/upload/resumable`,
        retryDelays: [0, 3000, 5000, 10000, 20000],
        headers: { authorization: `Bearer ${data.session?.access_token}`, apikey: SUPABASE_KEY, 'x-upsert': 'false' },
        uploadDataDuringCreation: true,
        removeFingerprintOnSuccess: true,
        chunkSize: 6 * 1024 * 1024, // Supabase requires exactly 6 MB chunks
        metadata: { bucketName: 'media', objectName: path, contentType: file.type, cacheControl: '3600' },
        onProgress: (sent, total) => onProgress?.(Math.round((sent / total) * 100)),
        onError: reject,
        onSuccess: () => resolve(),
      })
      signal?.addEventListener('abort', () => (upload.abort(true).catch(() => {}), reject(new Error('Cancelled'))))
      upload.start()
    })
  } catch (e) {
    const message = (e as Error).message
    throw new Error(/maximum allowed size|413|too large/i.test(message) ? 'File is larger than your Supabase plan allows (50 MB on the free plan).' : message)
  }
  const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl
  const res = await supabase
    .from('media')
    .insert({
      organization_id: orgId,
      module,
      folder_id: folderId,
      site_id: siteId,
      title: file.name.replace(/\.[^.]+$/, ''),
      kind,
      storage_path: path,
      url,
      size_bytes: file.size,
    })
    .select('*')
    .single()
  if (res.error) {
    await supabase.storage.from('media').remove([path])
    throw new Error(res.error.message)
  }
  return res.data as Media
}

/** Creates a media folder at the top of a module's library, with a name that is not taken. Returns its id and the name used. */
export async function createImportFolder(opts: { orgId: string; module: Module; siteId: string | null; wanted: string }): Promise<{ id: string; name: string }> {
  const { orgId, module, siteId, wanted } = opts
  const rows = await supabase.from('media_folders').select('name').eq('organization_id', orgId).eq('module', module).is('parent_id', null)
  if (rows.error) throw new Error(rows.error.message)
  const taken = (rows.data ?? []).map((r: { name: string }) => r.name)
  const name = uniqueName(taken, wanted)
  const res = await supabase.from('media_folders').insert({ organization_id: orgId, module, parent_id: null, site_id: siteId, name }).select('id').single()
  if (res.error) throw new Error(res.error.message)
  return { id: (res.data as { id: string }).id, name }
}

/** 'Easter' -> 'Easter', or 'Easter (2)' when taken (case-insensitive, like the database's unique index). */
export function uniqueName(taken: string[], wanted: string): string {
  const used = new Set(taken.map((n) => n.toLowerCase()))
  let name = wanted
  for (let i = 2; used.has(name.toLowerCase()); i++) name = `${wanted} (${i})`
  return name
}
