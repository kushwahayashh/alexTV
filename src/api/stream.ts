/**
 * Stream API client — chains through the AlexStream backend to resolve a
 * TMDB title to a playable stream URL. Handles both movies (flat file list)
 * and series (season folders → episode files), mirroring the reference
 * alexstream app.
 */

const BASE = 'https://alexhasitbig--alexstream-serve.modal.run'

export type VideoFile = {
  fid: number
  file_name: string
  ext: string
  resLabel: string
  file_size: string
  // Parsed from the filename by the backend (null when unrecognisable).
  season: number | null
  episode: number | null
}

export type Folder = {
  fid: number
  file_name: string
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

/**
 * List a FebBox share directory. `parentId` navigates into a folder ('0' is the
 * share root). Returns the video files (with parsed season/episode) plus any
 * sub-folders. The deployed backend may omit `folders`, so derive them from the
 * raw `files` list when absent (an entry is a folder when `is_dir === 1`).
 */
async function getFiles(
  shareKey: string,
  parentId = '0',
): Promise<{ videoFiles: VideoFile[]; folders: Folder[] }> {
  const data = await getJson(
    `/api/files?shareKey=${shareKey}&parentId=${parentId}`,
  )
  const rawFiles: any[] = data.files ?? []
  const rawFolders: any[] =
    data.folders ?? rawFiles.filter((f) => f.is_dir === 1)
  const folders: Folder[] = rawFolders.map((f) => ({
    fid: f.fid,
    file_name: f.file_name,
  }))
  return { videoFiles: data.videoFiles ?? [], folders }
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
  return (await getFiles(shareKey)).videoFiles
}

/**
 * Resolve chain for a series: title+year → ShowBox ID → TV share key → root
 * listing. Returns the share key (for lazy per-season folder navigation), the
 * root folders (season folders), and any video files sitting at the root (for
 * shows that are a flat episode list with no season folders).
 */
export async function resolveSeries(
  title: string,
  year: string,
): Promise<{ shareKey: string; folders: Folder[]; rootVideoFiles: VideoFile[] }> {
  const id = await resolveTitle(title, year, 'tv')
  const shareKey = await getShareKey(id, 2)
  const { videoFiles, folders } = await getFiles(shareKey)
  return { shareKey, folders, rootVideoFiles: videoFiles }
}

/** List the episode files inside a season folder. */
export async function getSeasonFiles(
  shareKey: string,
  folderFid: number,
): Promise<VideoFile[]> {
  return (await getFiles(shareKey, String(folderFid))).videoFiles
}
