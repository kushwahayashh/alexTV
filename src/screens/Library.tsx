import { useFocusable } from '../focus/FocusEngine'
import { HeaderButton } from '../components/HeaderButton'
import {
  itemsAtPath,
  type LibraryFile,
  type LibraryFolder,
  type LibraryItem,
} from '../api/library'

/**
 * File-manager style library. Browses the mock library tree (see
 * `api/library.ts`): the root lists movie files and series folders, opening a
 * folder drills into its episodes. The folder stack lives in App so the global
 * Back button can pop a level before closing the whole screen; this component
 * just renders the current level and reports folder-opens / file-picks up.
 */
export function Library({
  path,
  onGoHome,
  onOpenFolder,
  onPlayFile,
}: {
  path: string[]
  onGoHome: () => void
  onOpenFolder: (folderId: string) => void
  onPlayFile: (file: LibraryFile) => void
}) {
  const items = itemsAtPath(path)

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

      <div className="library__list">
        {items.map((item) => (
          <Row
            key={item.id}
            item={item}
            onOpenFolder={onOpenFolder}
            onPlayFile={onPlayFile}
          />
        ))}
      </div>
    </div>
  )
}

/** Current location as "Library / Folder / Subfolder". */
function Breadcrumb({ path }: { path: string[] }) {
  // Walk the tree once to turn folder ids into names.
  const names: string[] = []
  let level: LibraryItem[] = itemsAtPath([])
  for (const id of path) {
    const folder = level.find(
      (it) => it.id === id && it.type === 'folder',
    ) as LibraryFolder | undefined
    if (!folder) break
    names.push(folder.name)
    level = folder.children
  }

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
  onOpenFolder: (folderId: string) => void
  onPlayFile: (file: LibraryFile) => void
}) {
  const isFolder = item.type === 'folder'
  const { ref, focused } = useFocusable({
    scrollMode: 'nearest',
    onSelect: () => {
      if (isFolder) onOpenFolder(item.id)
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
      <span className="lib-row__meta">
        {isFolder ? (
          <span className="lib-badge">{item.children.length} episodes</span>
        ) : (
          <>
            {item.resolution && (
              <span className="lib-badge">{item.resolution}</span>
            )}
            {item.size && <span className="lib-badge">{item.size}</span>}
          </>
        )}
      </span>
      {isFolder && (
        <span className="lib-row__chevron" aria-hidden>
          ›
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
