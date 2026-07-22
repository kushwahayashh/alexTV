import { useEffect, useState } from 'react'
import { searchMulti, type Media } from '../api/tmdb'
import { useFocusable } from '../focus/FocusEngine'
import { PosterCard } from '../components/PosterCard'

const DEBOUNCE_MS = 350

type Status = 'idle' | 'loading' | 'ready'

/**
 * TMDB-first search screen. Typing debounces 350ms then hits /search/multi;
 * results render as a poster grid that hands each pick to the shared Details →
 * Player flow via onSelect. A single minimal search box sits top-center; the
 * focus engine drives D-pad nav (Down/Enter → grid) while this component
 * mirrors focus onto the real <input> so keystrokes land in the field. Back
 * (Esc) returns to Home, handled globally by the focus provider.
 */
export function Search({ onSelect }: { onSelect: (m: Media) => void }) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<Media[]>([])
  const [status, setStatus] = useState<Status>('idle')

  const field = useFocusable({
    isInput: true,
    // When the engine focuses the field, give the real input DOM focus so the
    // caret shows and keystrokes register.
    onFocus: () => field.ref.current?.focus(),
  })

  // Seed focus on the input when the screen mounts.
  useEffect(() => {
    field.focusSelf()
    field.ref.current?.focus()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Debounced search. Empty query resets to the idle empty-state.
  useEffect(() => {
    const q = query.trim()
    if (!q) {
      setResults([])
      setStatus('idle')
      return
    }
    setStatus('loading')
    let alive = true
    const timer = setTimeout(() => {
      searchMulti(q)
        .then((items) => {
          if (!alive) return
          setResults(items)
          setStatus('ready')
        })
        .catch((err) => {
          console.error(err)
          if (alive) {
            setResults([])
            setStatus('ready')
          }
        })
    }, DEBOUNCE_MS)
    return () => {
      alive = false
      clearTimeout(timer)
    }
  }, [query])

  const trimmed = query.trim()

  return (
    <div className="search">
      <div className="search__bar-wrap">
        <svg
          className="search__icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth={2.2}
          strokeLinecap="round"
          aria-hidden
        >
          <circle cx="11" cy="11" r="7" />
          <line x1="16.5" y1="16.5" x2="21" y2="21" />
        </svg>
        <input
          ref={field.ref as React.RefObject<HTMLInputElement>}
          className="search__input"
          type="text"
          placeholder="Search movies & series…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          spellCheck={false}
          autoComplete="off"
        />
      </div>

      {status === 'loading' && (
        <div className="search__grid">
          {Array.from({ length: 14 }).map((_, i) => (
            <div key={i} className="poster poster--skeleton" />
          ))}
        </div>
      )}
      {status === 'ready' && results.length === 0 && (
        <div className="search__msg">No results for “{trimmed}”.</div>
      )}
      {results.length > 0 && status === 'ready' && (
        <div className="search__grid">
          {results.map((media) => (
            <PosterCard
              key={`${media.mediaType}-${media.id}`}
              media={media}
              onSelect={onSelect}
            />
          ))}
        </div>
      )}
    </div>
  )
}
