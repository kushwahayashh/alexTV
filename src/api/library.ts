/**
 * Library data layer.
 *
 * Talks to the AlexTV Library backend (FastAPI on Modal). The stable URL serves
 * the full API directly, so listing hits `/list?path=` straight against it.
 * Streaming should go through the fast tunnel — `fetchStreamUrl` resolves that
 * via `/download-url` when the player needs a URL to hand to the video element.
 */

const LIBRARY_BASE = 'https://alexhasitbig--alextv-library-start.modal.run'

export type LibraryFile = {
  type: 'file'
  name: string
  /** Backend path, e.g. "/Breaking Bad/S01E01.mkv". */
  path: string
  size: number | null
  /** Human-readable size badge, e.g. "2.4 GB". */
  sizeFormatted: string | null
  /** Filename-derived resolution badge, e.g. "1080p", or null if unknown. */
  resolution: string | null
  mtime: number
}

export type LibraryFolder = {
  type: 'folder'
  name: string
  path: string
  /** Number of media items inside, for the folder badge. */
  itemCount: number
  mtime: number
}

export type LibraryItem = LibraryFile | LibraryFolder

export type LibraryListing = {
  /** Path that was listed ("/" at the root). */
  path: string
  /** Parent path, or null at the root. */
  parentPath: string | null
  items: LibraryItem[]
}

/** List one level of the media tree. Folders first, then files. */
export async function fetchLibrary(path: string): Promise<LibraryListing> {
  const res = await fetch(
    `${LIBRARY_BASE}/list?path=${encodeURIComponent(path)}`,
  )
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.detail || 'Failed to load library')
  }
  return res.json()
}

/**
 * Resolve a playable stream URL for a file, preferring the fast tunnel the
 * backend hands back from `/download-url`. Falls back to a direct `/stream`
 * URL if that call fails.
 */
export async function fetchStreamUrl(path: string): Promise<string> {
  try {
    const res = await fetch(
      `${LIBRARY_BASE}/download-url?path=${encodeURIComponent(path)}`,
    )
    if (res.ok) {
      const data = await res.json()
      if (data.url) return data.url as string
    }
  } catch {
    // fall through to the direct stream URL
  }
  return `${LIBRARY_BASE}/stream?path=${encodeURIComponent(path)}`
}

/** Parent path of a backend path, "/" at or above the root. */
export function parentOf(path: string): string {
  const trimmed = path.replace(/\/+$/, '')
  const idx = trimmed.lastIndexOf('/')
  if (idx <= 0) return '/'
  return trimmed.slice(0, idx)
}
