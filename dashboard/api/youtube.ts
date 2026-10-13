// Shared by the Netlify function (production) and the Vite dev server (local).
// Each church passes its own channel id (Settings -> YouTube channel); nothing is hard-coded here.
export type YouTubeEntry = { id: string; title: string; published: string }

export const isChannelId = (id: string | null): id is string => !!id && /^UC[\w-]{22}$/.test(id)

const tag = (xml: string, name: string) => xml.match(new RegExp(`<${name}>([^<]*)</${name}>`))?.[1] ?? ''
const decode = (s: string) =>
  s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")

/** Latest 15 live streams ("UULV" playlist) or uploads from the channel's public RSS feed. No API key needed. */
export async function channelFeed(channelId: string, kind: 'streams' | 'videos'): Promise<YouTubeEntry[]> {
  const feed =
    kind === 'streams'
      ? `https://www.youtube.com/feeds/videos.xml?playlist_id=UULV${channelId.slice(2)}`
      : `https://www.youtube.com/feeds/videos.xml?channel_id=${channelId}`
  const res = await fetch(feed)
  if (!res.ok) throw new Error(`YouTube feed returned ${res.status}`)
  const xml = await res.text()
  return [...xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)].map(([, entry]) => ({
    id: tag(entry, 'yt:videoId'),
    title: decode(tag(entry, 'title')),
    published: tag(entry, 'published'),
  }))
}

/** Title for any public video, for pasted links. */
export async function videoTitle(id: string): Promise<string | null> {
  const res = await fetch(
    `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(`https://www.youtube.com/watch?v=${id}`)}`,
  )
  return res.ok ? ((await res.json()) as { title: string }).title : null
}

export async function handleYouTubeApi(url: URL): Promise<Response> {
  try {
    const id = url.searchParams.get('video')
    const channel = url.searchParams.get('channel')
    let body: unknown
    if (id) body = { title: /^[\w-]{11}$/.test(id) ? await videoTitle(id) : null }
    else if (isChannelId(channel))
      body = { channelId: channel, items: await channelFeed(channel, url.searchParams.get('kind') === 'videos' ? 'videos' : 'streams') }
    else body = { items: [] }
    return Response.json(body, { headers: { 'Cache-Control': 'public, max-age=600' } })
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 502 })
  }
}
