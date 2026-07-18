import { useEffect, useState } from 'react'
import { useFocusable } from '../focus/FocusEngine'
import { HeaderButton } from '../components/HeaderButton'
import { Spinner } from '../components/Spinner'
import {
  fetchLibrary,
  type LibraryFile,
  type LibraryItem,
  type LibraryListing,
} from '../api/library'

type Status = 'loading' | 'ready' | 'error'

/**
 * File-manager style library, backed by the AlexTV Library backend. The current
 * path lives in App so the global Back button can climb folders before closing
 * the whole screen; this component fetches and renders the level at that path
 * and reports folder-opens / file-picks up.
 */
export function Library({
  path,
  onGoHome,
  onOpenFolder,
  onPlayFile,
}: {
  path: string
  onGoHome: () => void
  onOpenFolder: (folderPath: string) => void
  onPlayFile: (file: LibraryFile) => void
}) {
  const [listing, setListing] = useState<LibraryListing | null>(null)
  const [status, setStatus] = useState<Status>('loading')

  useEffect(() => {
    let alive = true
    setStatus('loading')
    fetchLibrary(path)
      .then((data) => {
        if (!alive) return
        setListing(data)
        setStatus('ready')
      })
      .catch((err) => {
        console.error(err)
        if (alive) setStatus('error')
      })
    return () => {
      alive = false
    }
  }, [path])

  return (
    <div className="library">
      <div className="library__topbar">
        <div className="library__nav">
          <HeaderButton label="Home" onSelect={onGoHome} />
          <HeaderButton label="Search" />
          <HeaderButton label="Library" />
        </div>
      </div>

      <Breadcrumb path={path} />

      {status === 'loading' && (
        <div className="library__msg library__msg--loader">
          <Spinner />
        </div>
      )}
      {status === 'error' && (
        <div className="library__msg">Failed to load the library.</div>
      )}
      {status === 'ready' && listing && listing.items.length === 0 && (
        <div className="library__msg">This folder is empty.</div>
      )}
      {status === 'ready' && listing && listing.items.length > 0 && (
        <div className="library__list">
          {listing.items.map((item) => (
            <Row
              key={item.path}
              item={item}
              onOpenFolder={onOpenFolder}
              onPlayFile={onPlayFile}
            />
          ))}
        </div>
      )}
    </div>
  )
}

/** Current location as the folder path below the root ("Breaking Bad / S01"). */
function Breadcrumb({ path }: { path: string }) {
  const names = path.split('/').filter(Boolean)
  // At the root there's nothing to show — we already know we're in the Library.
  if (names.length === 0) return null

  return (
    <div className="library__crumbs">
      {names.map((name, i) => (
        <span key={i} className="library__crumb-part">
          {i > 0 && <span className="library__crumb-sep">›</span>}
          <span className="library__crumb">{name}</span>
        </span>
      ))}
    </div>
  )
}

function Row({
  item,
  onOpenFolder,
  onPlayFile,
}: {
  item: LibraryItem
  onOpenFolder: (folderPath: string) => void
  onPlayFile: (file: LibraryFile) => void
}) {
  const isFolder = item.type === 'folder'
  const { ref, focused } = useFocusable({
    scrollMode: 'nearest',
    onSelect: () => {
      if (isFolder) onOpenFolder(item.path)
      else onPlayFile(item)
    },
  })

  return (
    <div
      ref={ref}
      className={`lib-row${focused ? ' lib-row--focused' : ''}`}
    >
      <span className="lib-row__icon" aria-hidden>
        {isFolder ? <FolderIcon /> : <FileIcon />}
      </span>
      <span className="lib-row__name">{item.name}</span>
      {!isFolder && item.sizeFormatted && (
        <span className="lib-row__meta">
          <span className="lib-row__size">{item.sizeFormatted}</span>
        </span>
      )}
    </div>
  )
}

function FolderIcon() {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M10 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-8l-2-2z" />
    </svg>
  )
}

function FileIcon() {
  // App-window glyph (Tabler): rounded frame with a titlebar dot row.
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M19 4a3 3 0 0 1 3 3v10a3 3 0 0 1 -3 3h-14a3 3 0 0 1 -3 -3v-10a3 3 0 0 1 3 -3zm-12.99 3l-.127 .007a1 1 0 0 0 .117 1.993l.127 -.007a1 1 0 0 0 -.117 -1.993zm3 0l-.127 .007a1 1 0 0 0 .117 1.993l.127 -.007a1 1 0 0 0 -.117 -1.993z" />
    </svg>
  )
}
