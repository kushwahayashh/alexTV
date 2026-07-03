/**
 * Stream API client — chains through the AlexStream backend to resolve a
 * TMDB title to a playable stream URL. Movie-only for now.
 */

const BASE = 'https://alexhasitbig--alexstream-serve.modal.run'

export type VideoFile = {
  fid: number
  file_name: string
  ext: string
  resLabel: string
  file_size: string
}

export type StreamLink = {
  url: string
  quality: string
  ext: string
  speed: string
  proxiedUrl: string
}

async function getJson(path: string): Promise<any> {
  const res = await fetch(`${BASE}${path}`)
  if (!res.ok) throw new Error(`${path} → ${res.status}`)
  return res.json()
}

/** Resolve a TMDB title+year to a ShowBox ID. */
async function resolveTitle(
  title: string,
  year: string,
  type: 'movie' | 'tv',
): Promise<number> {
  const data = await getJson(
    `/api/resolve?title=${encodeURIComponent(title)}&year=${year}&type=${type}`,
  )
  if (!data.id) throw new Error('Could not resolve title')
  return data.id
}

/** Get a FebBox share key from a ShowBox ID. type: 1=movie, 2=tv */
async function getShareKey(showboxId: number, type: 1 | 2): Promise<string> {
  const data = await getJson(`/api/share-key?id=${showboxId}&type=${type}`)
  if (!data.shareKey) throw new Error('Could not get share key')
  return data.shareKey
}

/** List video files in a FebBox share. */
async function getFiles(shareKey: string): Promise<VideoFile[]> {
  const data = await getJson(`/api/files?shareKey=${shareKey}`)
  return data.videoFiles ?? []
}

/** Get stream links for a specific file. */
export async function getLinks(fid: number): Promise<StreamLink[]> {
  const data = await getJson(`/api/links?fid=${fid}`)
  return data.links ?? []
}

/**
 * Full resolve chain for a movie: title+year → ShowBox ID → share key → files.
 * Returns the video files so the user can pick which one to play.
 */
export async function resolveMovie(
  title: string,
  year: string,
): Promise<VideoFile[]> {
  const id = await resolveTitle(title, year, 'movie')
  const shareKey = await getShareKey(id, 1)
  return getFiles(shareKey)
}
