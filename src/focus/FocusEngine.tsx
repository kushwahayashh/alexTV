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
  isHeader?: boolean
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
  return {
    cx: r.left + r.width / 2,
    cy: r.top + r.height / 2,
    left: r.left,
    top: r.top,
    right: r.right,
    bottom: r.bottom,
    width: r.width,
    height: r.height,
  }
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
    if (entry.isHeader) continue // header reached only via the explicit Up-from-hero path
    const to = rectOf(entry.element)

    const dx = to.cx - from.cx
    const dy = to.cy - from.cy

    // Must lie in the pressed direction (with a small dead-zone tolerance).
    // Left/right only move within the same row (vertical ranges overlap), so
    // pressing past the last/first item just stops — no row jumping.
    const sameRow = to.top < from.bottom && to.bottom > from.top
    const inDirection =
      (dir === 'left' && dx < -1 && sameRow) ||
      (dir === 'right' && dx > 1 && sameRow) ||
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
  const headerIdsRef = useRef<Set<string>>(new Set())

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
      if (e.isHeader) continue // header isn't part of the content grid
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
    if (entry.isHeader) headerIdsRef.current.add(entry.id)
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
    headerIdsRef.current.delete(id)
  }, [])

  // Leftmost header in document order — where focus enters when pressing Up
  // from the hero.
  const firstHeader = useCallback((): FocusableEntry | null => {
    let first: FocusableEntry | null = null
    for (const id of headerIdsRef.current) {
      const e = entries.current.get(id)
      if (!e) continue
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

  // Next header in the pressed horizontal direction, or null if none.
  const nextHeader = useCallback(
    (currentId: string, dir: 'left' | 'right'): string | null => {
      const cur = entries.current.get(currentId)
      if (!cur) return null
      const from = rectOf(cur.element)
      let best: { id: string; cost: number } | null = null
      for (const id of headerIdsRef.current) {
        if (id === currentId) continue
        const e = entries.current.get(id)
        if (!e) continue
        const to = rectOf(e.element)
        const dx = to.cx - from.cx
        if (dir === 'left' ? dx >= -1 : dx <= 1) continue
        const cost = Math.abs(dx)
        if (!best || cost < best.cost) best = { id, cost }
      }
      return best?.id ?? null
    },
    [],
  )

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
        const dir = dirMap[e.key]
        // Header focused: left/right moves between headers, down drops to hero.
        if (cur != null && headerIdsRef.current.has(cur)) {
          if (dir === 'down') {
            releaseToTop()
          } else if (dir === 'left' || dir === 'right') {
            const next = nextHeader(cur, dir)
            if (next) setFocus(next)
          }
          return
        }
        // Nothing focused yet (hero showing). Up reaches the first header; any
        // other direction enters the content grid at the first card.
        if (!cur) {
          if (dir === 'up') {
            const first = firstHeader()
            if (first) setFocus(first.id)
            return
          }
          const first = firstInDomOrder()
          if (first) setFocus(first.id)
          return
        }
        const next = findNext(entries.current, cur, dir)
        if (next) {
          setFocus(next)
        } else if (dir === 'up') {
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
  }, [setFocus, onBack, firstInDomOrder, releaseToTop, firstHeader, nextHeader])

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
  isHeader?: boolean
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
      isHeader: optsRef.current?.isHeader,
    })
    return () => ctx.unregister(id)
  }, [ctx, id])

  return {
    ref: ref as React.RefObject<any>,
    focused: ctx.focusId === id,
    focusSelf: () => ctx.setFocus(id),
  }
}
