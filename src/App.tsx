import { useCallback, useRef, useState } from 'react'
import { FocusProvider, type FocusApi } from './focus/FocusEngine'
import { Home } from './screens/Home'
import { Search } from './screens/Search'
import { Library } from './screens/Library'
import { Details } from './screens/Details'
import type { Media } from './api/tmdb'
import { parentOf, type LibraryFile } from './api/library'

export default function App() {
  const [selected, setSelected] = useState<Media | null>(null)
  const [showSearch, setShowSearch] = useState(false)
  const [showLibrary, setShowLibrary] = useState(false)
  // Backend path of the current library level; "/" is the root.
  const [libraryPath, setLibraryPath] = useState('/')
  const libraryPathRef = useRef('/')
  // Imperative handle into the focus engine, populated by FocusProvider.
  const focusApi = useRef<FocusApi | null>(null)
  // The card focused before Details was opened, so Back can restore it.
  const detailsReturnFocus = useRef<string | null>(null)

  // Open Details from whichever screen is on top; remember the focused item.
  const handleSelect = useCallback((m: Media) => {
    detailsReturnFocus.current = focusApi.current?.getFocusId() ?? null
    setSelected(m)
  }, [])

  // Back from Details: drop the selection (the screen underneath is still
  // mounted) and restore the item it was opened from.
  const handleCloseDetails = useCallback(() => {
    setSelected((s) => {
      if (!s) return s
      const saved = detailsReturnFocus.current
      if (saved) requestAnimationFrame(() => focusApi.current?.setFocus(saved))
      return null
    })
  }, [])

  // Open Search from Home.
  const handleOpenSearch = useCallback(() => {
    setShowSearch(true)
  }, [])

  // Back from Search: return to Home.
  const handleCloseSearch = useCallback(() => {
    setShowSearch(false)
  }, [])

  // Open Library from Home; start at root.
  const handleOpenLibrary = useCallback(() => {
    libraryPathRef.current = '/'
    setLibraryPath('/')
    setShowLibrary(true)
  }, [])

  // Fully close Library and return to Home with the hero visible and sidebar
  // collapsed (no focus restoration — the saved focus was a sidebar item which
  // would re-expand the sidebar).
  const handleExitLibrary = useCallback(() => {
    setShowLibrary(false)
    libraryPathRef.current = '/'
    setLibraryPath('/')
  }, [])

  // Back from Library: climb into the current folder's parent if we're drilled
  // in, otherwise close the screen and return to Home.
  const handleCloseLibrary = useCallback(() => {
    const cur = libraryPathRef.current
    if (cur !== '/') {
      const parent = parentOf(cur)
      libraryPathRef.current = parent
      setLibraryPath(parent)
    } else {
      setShowLibrary(false)
    }
  }, [])

  const handleOpenFolder = useCallback((folderPath: string) => {
    libraryPathRef.current = folderPath
    setLibraryPath(folderPath)
  }, [])

  const handlePlayFile = useCallback((file: LibraryFile) => {
    // Player wiring lands later; for now just surface the pick.
    console.log('play library file', file.name)
  }, [])

  // Back button routes to the topmost layer: Details → Search/Library → Home.
  const handleBack = useCallback(() => {
    if (selected) handleCloseDetails()
    else if (showLibrary) handleCloseLibrary()
    else if (showSearch) handleCloseSearch()
  }, [
    selected,
    showLibrary,
    showSearch,
    handleCloseDetails,
    handleCloseLibrary,
    handleCloseSearch,
  ])

  return (
    <FocusProvider onBack={handleBack} apiRef={focusApi}>
      {/* Home stays mounted so its rails data, scroll position and focused
          card all survive a round-trip into Search/Details — it's only hidden
          while a screen is on top. display:contents keeps it layout-transparent
          when visible (as if this wrapper weren't here). */}
      <div
        style={{
          display:
            selected || showSearch || showLibrary ? 'none' : 'contents',
        }}
      >
        <Home
          onSelect={handleSelect}
          onOpenSearch={handleOpenSearch}
          onOpenLibrary={handleOpenLibrary}
        />
      </div>
      {/* Search likewise stays mounted (hidden) under Details so Back from a
          result returns to the same query and grid position. */}
      {showSearch && (
        <div style={{ display: selected ? 'none' : 'contents' }}>
          <Search onSelect={handleSelect} />
        </div>
      )}
      {showLibrary && (
        <div style={{ display: selected ? 'none' : 'contents' }}>
          <Library
            path={libraryPath}
            onGoHome={handleExitLibrary}
            onOpenFolder={handleOpenFolder}
            onPlayFile={handlePlayFile}
          />
        </div>
      )}
      {selected && <Details media={selected} />}
    </FocusProvider>
  )
}
