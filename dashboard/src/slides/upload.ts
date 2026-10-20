import * as tus from 'tus-js-client'
import { SUPABASE_KEY, SUPABASE_URL, supabase } from '../supabase'
import { randomName } from '../lib'

/** Uploads one image or video into the Slides media library (same resumable upload as the Media page). Throws a readable message. */
export async function uploadToSlidesLibrary(opts: {
  file: File
  orgId: string
  folderId: string | null
  siteId: string | null
  onProgress?: (percent: number) => void
}): Promise<void> {
  const { file, orgId, folderId, siteId, onProgress } = opts
  const kind = file.type.startsWith('video/') ? 'video' : file.type.startsWith('image/') ? 'image' : null
  if (!kind) throw new Error('Only videos and images can be uploaded.')
  const path = `${orgId}/${randomName(file.name)}`
  try {
    const { data } = await supabase.auth.getSession()
    await new Promise<void>((resolve, reject) => {
      new tus.Upload(file, {
        endpoint: `${SUPABASE_URL}/storage/v1/upload/resumable`,
        retryDelays: [0, 3000, 5000, 10000, 20000],
        headers: { authorization: `Bearer ${data.session?.access_token}`, apikey: SUPABASE_KEY, 'x-upsert': 'false' },
        uploadDataDuringCreation: true,
        removeFingerprintOnSuccess: true,
        chunkSize: 6 * 1024 * 1024,
        metadata: { bucketName: 'media', objectName: path, contentType: file.type, cacheControl: '3600' },
        onProgress: (sent, total) => onProgress?.(Math.round((sent / total) * 100)),
        onError: reject,
        onSuccess: () => resolve(),
      }).start()
    })
  } catch (e) {
    const message = (e as Error).message
    throw new Error(/maximum allowed size|413|too large/i.test(message) ? 'File is larger than your Supabase plan allows (50 MB on the free plan).' : message)
  }
  const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl
  const res = await supabase.from('media').insert({
    organization_id: orgId,
    module: 'slides',
    folder_id: folderId,
    site_id: siteId,
    title: file.name.replace(/\.[^.]+$/, ''),
    kind,
    storage_path: path,
    url,
    size_bytes: file.size,
  })
  if (res.error) {
    await supabase.storage.from('media').remove([path]) // don't leave an unlisted file behind
    throw new Error(res.error.message)
  }
}
