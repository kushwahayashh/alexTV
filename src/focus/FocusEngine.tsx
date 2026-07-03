/**
 * Spatial D-pad focus engine.
 *
 * Every focusable element registers its DOM node here. On an arrow key we read
 * the live geometry of every registered node (getBoundingClientRect) and pick
 * the best candidate in the pressed direction using a distance + alignment cost.
 * This mirrors how a real TV focus engine (and Flutter's FocusTraversalPolicy)
 * reasons about focus, so the mental model carries over to the Flutter port.
 */
import {
  createContext,
  useContext,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from 'react'

export type Direction = 'up' | 'down' | 'left' | 'right'

type FocusableEntry = {
  id: string
  element: HTMLElement
  onSelect?: () => void
  onFocus?: () => void
}

type FocusContextValue = {
  register: (entry: FocusableEntry) => void
  unregister: (id: string) => void
  focusId: string | null
  setFocus: (id: string) => void
}

const FocusContext = createContext<FocusContextValue | null>(null)

function rectOf(el: HTMLElement) {
  const r = el.getBoundingClientRect()
  return { cx: r.left + r.width / 2, cy: r.top + r.height / 2, ...r }
}

/**
 * Given the current focused element and a direction, score every other
 * focusable and return the id of the best next target (or null if none).
 */
function findNext(
  entries: Map<string, FocusableEntry>,
  currentId: string,
  dir: Direction,
): string | null {
  const current = entries.get(currentId)
  if (!current) return null
  const from = rectOf(current.element)

  let best: { id: string; cost: number } | null = null

  for (const entry of entries.values()) {
    if (entry.id === currentId) continue
    const to = rectOf(entry.element)

    const dx = to.cx - from.cx
    const dy = to.cy - from.cy

    // Must lie in the pressed direction (with a small dead-zone tolerance).
    const inDirection =
      (dir === 'left' && dx < -1) ||
      (dir === 'right' && dx > 1) ||
      (dir === 'up' && dy < -1) ||
      (dir === 'down' && dy > 1)
    if (!inDirection) continue

    // Primary axis = travel distance in the pressed direction.
    // Cross axis = misalignment, weighted heavily so we prefer straight lines.
    const primary = dir === 'left' || dir === 'right' ? Math.abs(dx) : Math.abs(dy)
    const cross = dir === 'left' || dir === 'right' ? Math.abs(dy) : Math.abs(dx)
    const cost = primary + cross * 3

    if (!best || cost < best.cost) best = { id: entry.id, cost }
  }

  return best ? best.id : null
}

export function FocusProvider({
  children,
  onBack,
}: {
  children: ReactNode
  onBack?: () => void
}) {
  const entries = useRef<Map<string, FocusableEntry>>(new Map())
  const [focusId, setFocusId] = useState<string | null>(null)
  const focusIdRef = useRef<string | null>(null)
  focusIdRef.current = focusId

  const setFocus = useCallback((id: string) => {
    if (!entries.current.has(id)) return
    setFocusId(id)
    entries.current.get(id)?.onFocus?.()
    // block:'start' + the container's scroll-padding-top lifts the focused row
    // to a comfortable spot near the top so it's never clipped by the viewport
    // edge or the scaled-up focus outline.
    entries.current.get(id)?.element.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
      inline: 'center',
    })
  }, [])

  // First focusable in document order — where focus enters when nothing is
  // focused yet (e.g. the user presses Down while the hero is showing).
  const firstInDomOrder = useCallback((): FocusableEntry | null => {
    let first: FocusableEntry | null = null
    for (const e of entries.current.values()) {
      if (
        !first ||
        e.element.compareDocumentPosition(first.element) &
          Node.DOCUMENT_POSITION_FOLLOWING
      ) {
        first = e
      }
    }
    return first
  }, [])

  const register = useCallback((entry: FocusableEntry) => {
    // No auto-seed: nothing is focused on load so the hero is fully visible.
    entries.current.set(entry.id, entry)
  }, [])

  // Release focus (back to no selection) and scroll the content container to
  // the top so the hero shows fully — used when pressing Up from the top row.
  const releaseToTop = useCallback(() => {
    const cur = focusIdRef.current
    const el = cur ? entries.current.get(cur)?.element : null
    setFocusId(null)
    let p: HTMLElement | null = el?.parentElement ?? null
    while (p) {
      const oy = getComputedStyle(p).overflowY
      if ((oy === 'auto' || oy === 'scroll') && p.scrollHeight > p.clientHeight) {
        p.scrollTo({ top: 0, behavior: 'smooth' })
        return
      }
      p = p.parentElement
    }
  }, [])

  const unregister = useCallback((id: string) => {
    entries.current.delete(id)
  }, [])

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      const dirMap: Record<string, Direction> = {
        ArrowUp: 'up',
        ArrowDown: 'down',
        ArrowLeft: 'left',
        ArrowRight: 'right',
      }

      if (e.key in dirMap) {
        e.preventDefault()
        const cur = focusIdRef.current
        // Nothing focused yet (hero showing) — enter the grid at the first card.
        if (!cur) {
          const first = firstInDomOrder()
          if (first) setFocus(first.id)
          return
        }
        const next = findNext(entries.current, cur, dirMap[e.key])
        if (next) {
          setFocus(next)
        } else if (dirMap[e.key] === 'up') {
          // Nothing above the top row — release focus back up to the hero.
          releaseToTop()
        }
        return
      }

      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault()
        const cur = focusIdRef.current
        if (cur) entries.current.get(cur)?.onSelect?.()
        return
      }

      if (e.key === 'Escape' || e.key === 'Backspace') {
        e.preventDefault()
        onBack?.()
      }
    }

    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [setFocus, onBack, firstInDomOrder, releaseToTop])

  return (
    <FocusContext.Provider value={{ register, unregister, focusId, setFocus }}>
      {children}
    </FocusContext.Provider>
  )
}

let idCounter = 0

/**
 * Register a focusable node. Returns a ref to attach and whether it is focused.
 */
export function useFocusable(opts?: {
  onSelect?: () => void
  onFocus?: () => void
}) {
  const ctx = useContext(FocusContext)
  if (!ctx) throw new Error('useFocusable must be used within a FocusProvider')

  const idRef = useRef<string>('')
  if (!idRef.current) idRef.current = `f${idCounter++}`
  const id = idRef.current

  const ref = useRef<HTMLElement | null>(null)
  const optsRef = useRef(opts)
  optsRef.current = opts

  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    ctx.register({
      id,
      element: el,
      onSelect: () => optsRef.current?.onSelect?.(),
      onFocus: () => optsRef.current?.onFocus?.(),
    })
    return () => ctx.unregister(id)
  }, [ctx, id])

  return {
    ref: ref as React.RefObject<any>,
    focused: ctx.focusId === id,
    focusSelf: () => ctx.setFocus(id),
  }
}
