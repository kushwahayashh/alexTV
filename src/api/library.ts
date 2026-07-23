/**
 * Library data layer.
 *
 * Talks to the AlexTV Library backend (FastAPI on Modal). The stable URL serves
 * the full API directly, so listing hits `/list?path=` straight against it.
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

/** Parent path of a backend path, "/" at or above the root. */
export function parentOf(path: string): string {
  const trimmed = path.replace(/\/+$/, '')
  const idx = trimmed.lastIndexOf('/')
  if (idx <= 0) return '/'
  return trimmed.slice(0, idx)
}
