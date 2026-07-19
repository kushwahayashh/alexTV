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

      <Breadcrumb path={path} onNavigate={onOpenFolder} />


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

/**
 * Location trail, always rooted at "Home" ("Home › Breaking Bad › S01").
 * Each crumb is focusable and navigates to that folder level when selected, so
 * clicking a crumb climbs back up the tree.
 */
function Breadcrumb({
  path,
  onNavigate,
}: {
  path: string
  onNavigate: (folderPath: string) => void
}) {
  const names = path.split('/').filter(Boolean)
  // Build the (label, target-path) pairs: Home at root, then each folder level.
  const crumbs = [
    { label: 'Home', target: '/' },
    ...names.map((name, i) => ({
      label: name,
      target: '/' + names.slice(0, i + 1).join('/'),
    })),
  ]

  // The whole bar is one focusable item, like a list row. Selecting it climbs
  // one folder up (to the parent of the current level).
  const parentTarget = crumbs.length > 1 ? crumbs[crumbs.length - 2].target : '/'
  const { ref, focused } = useFocusable({
    scrollMode: 'nearest',
    onSelect: () => onNavigate(parentTarget),
  })

  return (
    <div
      ref={ref as React.RefObject<HTMLDivElement>}
      className={`library__crumbbar${
        focused ? ' library__crumbbar--focused' : ''
      }`}
      onClick={() => onNavigate(parentTarget)}
    >
      <span className="library__crumb-icon" aria-hidden>
        <FolderUpIcon />
      </span>
      <div className="library__crumbs">
        {crumbs.map((crumb, i) => {
          const isLast = i === crumbs.length - 1
          return (
            <span key={crumb.target} className="library__crumb-part">
              {i > 0 && <span className="library__crumb-sep">/</span>}
              <span
                className={`library__crumb${
                  isLast ? ' library__crumb--current' : ''
                }`}
              >
                {crumb.label}
              </span>
            </span>
          )
        })}
      </div>
    </div>
  )
}

/**
 * MOCK: fake watch-progress so we can preview the resume bar styling. Hashes the
 * file path to a stable fraction; ~40% of files get a bar, the rest none. This
 * stands in for the native PlaybackProgressStore the Android build reads back.
 */
function mockProgress(item: LibraryItem): number {
  if (item.type === 'folder') return 0
  let h = 0
  for (let i = 0; i < item.path.length; i++) {
    h = (h * 31 + item.path.charCodeAt(i)) >>> 0
  }
  if (h % 5 >= 2) return 0 // ~60% have no progress
  return 0.08 + ((h >>> 3) % 85) / 100 // 0.08 .. 0.93
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
  const progress = mockProgress(item)
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
      <div className="lib-row__content">
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
      {progress > 0 && (
        <div className="lib-row__progress" aria-hidden>
          <div
            className="lib-row__progress-fill"
            style={{ width: `${Math.max(2, progress * 100)}%` }}
          />
        </div>
      )}
    </div>
  )
}

function FolderUpIcon() {
  // "Level up" arrow — bends up and to the left, meaning go up one folder.
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M9 14 4 9l5-5" />
      <path d="M4 9h11a5 5 0 0 1 5 5v6" />
    </svg>
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
