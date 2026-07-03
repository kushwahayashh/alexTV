import { useCallback, useState } from 'react'
import { FocusProvider } from './focus/FocusEngine'
import { Home } from './screens/Home'
import { Details } from './screens/Details'
import type { Media } from './api/tmdb'

export default function App() {
  const [selected, setSelected] = useState<Media | null>(null)

  // Stable callback — uses the functional update form so the closure never
  // captures a stale `selected`, keeping the FocusProvider keydown listener
  // from re-registering on every render.
  const handleBack = useCallback(() => {
    setSelected((s) => (s ? null : s))
  }, [])

  return (
    <FocusProvider onBack={handleBack}>
      {selected ? (
        <Details media={selected} />
      ) : (
        <Home onSelect={setSelected} />
      )}
    </FocusProvider>
  )
}
