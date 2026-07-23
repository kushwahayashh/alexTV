/**
 * Series stream helpers — pure logic ported 1:1 from the reference alexstream
 * app (android/app/src/main/assets/detail.js). FebBox is the source of truth
 * for what's actually playable: seasons are folders in the share, episodes are
 * the video files inside them (or at the root for flat shows). TMDB is not used
 * here — episode names are derived from the filename.
 */
import type { VideoFile, Folder } from './stream'

export type SeasonOption = {
  // Folder fid to list episodes from; null for a flat show's synthetic season.
  fid: number | null
  label: string
  number: number
}

function isSeasonFolder(folder: Folder): boolean {
  return /^\s*(season\s*\d{1,2}|s\d{1,2})\s*$/i.test(folder.file_name || '')
}

function seasonNumber(folder: Folder): number {
  const m = (folder.file_name || '').match(/\d+/)
  return m ? Number(m[0]) : 0
}

function seasonLabel(folder: Folder): string {
  const n = seasonNumber(folder)
  return n === 0 ? 'Specials' : `Season ${n}`
}

/**
 * Build the season list from a share's root folders. Prefers real "Season N"
 * folders; if there are none, returns a single synthetic "Episodes" season so
 * flat shows (all episodes at the root) still work. Sorted by season number.
 */
export function buildSeasons(folders: Folder[]): SeasonOption[] {
  const seasonDirs = folders.filter(isSeasonFolder)
  const dirs = (seasonDirs.length ? seasonDirs : folders)
    .slice()
    .sort((a, b) => (seasonNumber(a) || Infinity) - (seasonNumber(b) || Infinity))
  if (!dirs.length) {
    return [{ fid: null, label: 'Episodes', number: 1 }]
  }
  return dirs.map((f) => ({
    fid: f.fid,
    label: seasonLabel(f),
    number: seasonNumber(f),
  }))
}

function resRank(resLabel: string | null): number {
  return parseInt(resLabel || '', 10) || 0
}

/**
 * Collapse multiple source files of the same episode down to the highest
 * resolution. Files with an unrecognised episode number are kept as-is.
 */
function bestPerEpisode(episodes: VideoFile[]): VideoFile[] {
  const best = new Map<number, VideoFile>()
  const unknown: VideoFile[] = []
  for (const ep of episodes) {
    if (ep.episode == null) {
      unknown.push(ep)
      continue
    }
    const current = best.get(ep.episode)
    if (!current || resRank(ep.resLabel) > resRank(current.resLabel)) {
      best.set(ep.episode, ep)
    }
  }
  return [...best.values(), ...unknown]
}

/** Sort by episode number, then by resolution (highest first). */
function episodeSort(a: VideoFile, b: VideoFile): number {
  return (
    (a.episode ?? 1e9) - (b.episode ?? 1e9) ||
    resRank(b.resLabel) - resRank(a.resLabel)
  )
}

/** best-per-episode + sorted, ready to render. */
export function orderedEpisodes(files: VideoFile[]): VideoFile[] {
  return bestPerEpisode(files).sort(episodeSort)
}

/**
 * Friendly episode title from the filename (backend files have no title field):
 * "...S01E03.The.Reckoning.1080p..." → "The Reckoning", else "Episode N".
 */
export function epTitle(file: VideoFile, num: number): string {
  const raw = file.file_name || ''
  const m = raw.match(
    /[sS]\d{1,2}[eE]\d{1,3}[.\s_-]+(.+?)[.\s_-]+(?:\d{3,4}p|web|bluray|hdtv|x26|h26|hevc|aac|ddp|dts)/i,
  )
  if (m && m[1]) {
    const title = m[1].replace(/[.\s_-]+/g, ' ').trim()
    if (title && !/^\d+$/.test(title)) return title
  }
  return `Episode ${num}`
}
