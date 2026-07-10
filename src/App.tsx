import { useCallback, useRef, useState } from 'react'
import { FocusProvider, type FocusApi } from './focus/FocusEngine'
import { Home } from './screens/Home'
import { Details } from './screens/Details'
import type { Media } from './api/tmdb'

export default function App() {
  const [selected, setSelected] = useState<Media | null>(null)
  // Imperative handle into the focus engine, populated by FocusProvider.
  const focusApi = useRef<FocusApi | null>(null)
  // The Home card that was focused when we entered Details, so Back can
  // return focus to it instead of dumping the user at the first card.
  const savedFocus = useRef<string | null>(null)

  // Open Details: remember the focused Home card first.
  const handleSelect = useCallback((m: Media) => {
    savedFocus.current = focusApi.current?.getFocusId() ?? null
    setSelected(m)
  }, [])

  // Back: drop the selection (Home is still mounted underneath) and restore
  // the card that was focused before. Functional update keeps the closure from
  // capturing a stale `selected`, so the FocusProvider listener never
  // re-registers on every render.
  const handleBack = useCallback(() => {
    setSelected((s) => {
      if (!s) return s
      const saved = savedFocus.current
      // Restore after the commit that re-shows Home and unmounts Details.
      if (saved) requestAnimationFrame(() => focusApi.current?.setFocus(saved))
      return null
    })
  }, [])

  return (
    <FocusProvider onBack={handleBack} apiRef={focusApi}>
      {/* Home stays mounted so its rails data, scroll position and focused
          card all survive a round-trip into Details — it's only hidden while
          Details is on top. display:contents keeps it layout-transparent when
          visible (as if this wrapper weren't here). */}
      <div style={{ display: selected ? 'none' : 'contents' }}>
        <Home onSelect={handleSelect} />
      </div>
      {selected && <Details media={selected} />}
    </FocusProvider>
  )
}
