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
  useImperativeHandle,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from 'react'

export type Direction = 'up' | 'down' | 'left' | 'right'

/**
 * Imperative handle for reading/writing focus from outside the tree (e.g. the
 * App shell saving the focused card before opening Details and restoring it on
 * Back). `setFocus` is a no-op if the id isn't currently registered.
 */
export type FocusApi = {
  getFocusId: () => string | null
  setFocus: (id: string) => void
}

type FocusableEntry = {
  id: string
  element: HTMLElement
  onSelect?: () => void
  onFocus?: () => void
  isHeader?: boolean
  // Sidebar item: a header that stacks vertically (Netflix/Hotstar-style left
  // rail). Treated like a header for the hero-release / first-header paths, but
  // directional nav is rotated: Up/Down walks the rail and Right drops into the
  // content (Left does nothing). Left from the leftmost content column also
  // reaches the rail.
  isSidebar?: boolean
  // Text input: typing, Space, Backspace and Left/Right (caret) pass through to
  // the field; only Up (header) and Down/Enter (into the grid) navigate away.
  isInput?: boolean
  isCurrent?: boolean
  // 'top' scrolls the nearest scroll container fully to the top on focus (used
  // by hero action buttons so focusing them shows the whole hero instead of
  // lifting the button to the viewport top). 'nearest' scrolls only enough to
  // reveal the element (episode rows, so the hero stays visible). Default lifts
  // the element to the top (block:'start').
  scrollMode?: 'start' | 'top' | 'nearest'
  active: boolean
}

type FocusContextValue = {
  register: (entry: FocusableEntry) => void
  unregister: (id: string) => void
  focusId: string | null
  setFocus: (id: string) => void
  setActive: (id: string, active: boolean) => void
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
    if (!entry.active) continue // skip elements behind a modal overlay
    const to = rectOf(entry.element)
    // Skip hidden nodes (display:none reports a zero rect) — e.g. the Home
    // cards sitting mounted-but-hidden behind the Details screen.
    if (to.width <= 0 && to.height <= 0) continue

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
  apiRef,
}: {
  children: ReactNode
  onBack?: () => void
  apiRef?: RefObject<FocusApi | null>
}) {
  const entries = useRef<Map<string, FocusableEntry>>(new Map())
  const [focusId, setFocusId] = useState<string | null>(null)
  const focusIdRef = useRef<string | null>(null)
  focusIdRef.current = focusId
  const headerIdsRef = useRef<Set<string>>(new Set())
  const sidebarIdsRef = useRef<Set<string>>(new Set())
  // Content item that had focus before the sidebar rail was entered (via Left).
  // On Right from the sidebar, focus returns here instead of jumping to the top.
  const sidebarReturnFocus = useRef<string | null>(null)

  const setFocus = useCallback((id: string) => {
    if (!entries.current.has(id)) return
    setFocusId(id)
    const entry = entries.current.get(id)
    entry?.onFocus?.()
    // Sidebar items live in a position:fixed rail that never scrolls, so
    // scrollIntoView would instead walk up to the nearest scroll container
    // (.home/.library) and yank the content vertically — causing the hero/
    // rails to jump when the rail expands. Skip scrolling for rail items.
    if (entry?.isSidebar) return
    // 'top' entries (hero action buttons) scroll their container fully to the
    // top so the whole hero shows, instead of lifting the button to the edge.
    if (entry?.scrollMode === 'top') {
      let p: HTMLElement | null = entry.element.parentElement
      while (p) {
        const oy = getComputedStyle(p).overflowY
        if ((oy === 'auto' || oy === 'scroll') && p.scrollHeight > p.clientHeight) {
          p.scrollTo({ top: 0, behavior: 'smooth' })
          return
        }
        p = p.parentElement
      }
      return
    }
    // 'nearest' entries (episode rows) scroll only enough to come into view,
    // so moving down the list doesn't yank the hero off screen.
    if (entry?.scrollMode === 'nearest') {
      entry.element.scrollIntoView({
        behavior: 'smooth',
        block: 'nearest',
        inline: 'center',
      })
      return
    }
    // block:'start' + the container's scroll-padding-top lifts the focused row
    // to a comfortable spot near the top so it's never clipped by the viewport
    // edge or the scaled-up focus outline.
    entry?.element.scrollIntoView({
      behavior: 'smooth',
      block: 'start',
      inline: 'center',
    })
  }, [])

  // Expose an imperative handle so the App shell can snapshot the focused card
  // before opening Details and restore it on Back. getFocusId reads the live
  // ref so callers always see the current focus.
  useImperativeHandle(
    apiRef,
    () => ({ getFocusId: () => focusIdRef.current, setFocus }),
    [setFocus],
  )

  // First focusable in document order — where focus enters when nothing is
  // focused yet (e.g. the user presses Down while the hero is showing).
  const firstInDomOrder = useCallback((): FocusableEntry | null => {
    let first: FocusableEntry | null = null
    for (const e of entries.current.values()) {
      if (e.isHeader) continue // header isn't part of the content grid
      if (!e.active) continue
      // Skip hidden nodes (zero rect), e.g. Home cards behind Details.
      const r = rectOf(e.element)
      if (r.width <= 0 && r.height <= 0) continue
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
    if (entry.isSidebar) sidebarIdsRef.current.add(entry.id)
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
    sidebarIdsRef.current.delete(id)
  }, [])

  const setActive = useCallback((id: string, active: boolean) => {
    const entry = entries.current.get(id)
    if (entry) entry.active = active
  }, [])

  // Whether the active screen has a visible hero to release focus into. Home
  // (and Details) show one; Library/Search don't. When there's no hero, the
  // "release to top" step is skipped so Up/Down hop straight between the header
  // and the content instead of wasting a press on an empty release.
  const heroVisible = useCallback((): boolean => {
    const heroes = document.querySelectorAll('.hero, .details__hero')
    for (const el of heroes) {
      const r = (el as HTMLElement).getBoundingClientRect()
      if (r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < window.innerHeight)
        return true
    }
    return false
  }, [])

  // Leftmost header in document order — where focus enters when pressing Up
  // from the hero.
  const firstHeader = useCallback((): FocusableEntry | null => {
    let first: FocusableEntry | null = null
    for (const id of headerIdsRef.current) {
      const e = entries.current.get(id)
      if (!e) continue
      // Sidebar items are in headerIdsRef but reached only via LEFT, not UP.
      if (e.isSidebar) continue
      // Skip hidden headers (zero rect), e.g. Home's header behind Details.
      const r = rectOf(e.element)
      if (r.width <= 0 && r.height <= 0) continue
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
        if (e.isSidebar) continue
        const to = rectOf(e.element)
        // Skip hidden headers (zero rect), e.g. Home's header sitting mounted
        // behind the Search screen.
        if (to.width <= 0 && to.height <= 0) continue
        const dx = to.cx - from.cx
        if (dir === 'left' ? dx >= -1 : dx <= 1) continue
        const cost = Math.abs(dx)
        if (!best || cost < best.cost) best = { id, cost }
      }
      return best?.id ?? null
    },
    [],
  )

  // First sidebar item in document order — where focus enters when content
  // reaches sideways for the rail (Left from the leftmost column).
  const firstSidebar = useCallback((): FocusableEntry | null => {
    let first: FocusableEntry | null = null
    let current: FocusableEntry | null = null
    for (const id of sidebarIdsRef.current) {
      const e = entries.current.get(id)
      if (!e) continue
      const r = rectOf(e.element)
      if (r.width <= 0 && r.height <= 0) continue
      if (e.isCurrent) current = e
      if (
        !first ||
        e.element.compareDocumentPosition(first.element) &
          Node.DOCUMENT_POSITION_FOLLOWING
      ) {
        first = e
      }
    }
    return current ?? first
  }, [])

  // Next sidebar item above/below the current one in the vertical rail.
  const nextSidebar = useCallback(
    (currentId: string, dir: 'up' | 'down'): string | null => {
      const cur = entries.current.get(currentId)
      if (!cur) return null
      const from = rectOf(cur.element)
      let best: { id: string; cost: number } | null = null
      for (const id of sidebarIdsRef.current) {
        if (id === currentId) continue
        const e = entries.current.get(id)
        if (!e) continue
        const to = rectOf(e.element)
        if (to.width <= 0 && to.height <= 0) continue
        const dy = to.cy - from.cy
        if (dir === 'up' ? dy >= -1 : dy <= 1) continue
        const cost = Math.abs(dy)
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
        const cur = focusIdRef.current
        const dir = dirMap[e.key]
        const curEntry = cur != null ? entries.current.get(cur) : null
        // Entry may be stale (leftover from a previous screen, now hidden
        // behind another screen with display:none — zero rect). Treat it as
        // no-focus so the first keypress on the new screen seeds correctly.
        const curAlive = curEntry != null && (() => {
          const r = curEntry.element.getBoundingClientRect()
          return r.width > 0 || r.height > 0
        })()

        // Text input focused: Left/Right belong to the caret — let the browser
        // handle them and don't navigate away. Up/Down still leave the field.
        if (curAlive && curEntry!.isInput) {
          if (dir === 'left' || dir === 'right') return
          e.preventDefault()
          if (dir === 'up') {
            const first = firstHeader()
            if (first) setFocus(first.id)
          } else {
            // Down: drop into the results grid (first focusable below).
            const next = findNext(entries.current, cur!, 'down')
            if (next) setFocus(next)
          }
          return
        }

        e.preventDefault()

        // Sidebar item focused: Up/Down walks the vertical rail, Right drops
        // into the content (restoring the item that had focus before the sidebar
        // was opened), Left is a no-op.
        if (curAlive && sidebarIdsRef.current.has(cur!)) {
          if (dir === 'up' || dir === 'down') {
            const next = nextSidebar(cur!, dir)
            if (next) setFocus(next)
          } else if (dir === 'right') {
            const saved = sidebarReturnFocus.current
            sidebarReturnFocus.current = null
            if (saved && entries.current.has(saved)) {
              setFocus(saved)
            } else if (heroVisible()) {
              releaseToTop()
            } else {
              const first = firstInDomOrder()
              if (first) setFocus(first.id)
            }
          }
          return
        }

        // Header focused: left/right moves between headers. Down drops into the
        // hero when there is one; otherwise straight into the content grid.
        if (curAlive && headerIdsRef.current.has(cur!)) {
          if (dir === 'down') {
            if (heroVisible()) {
              releaseToTop()
            } else {
              const first = firstInDomOrder()
              if (first) setFocus(first.id)
            }
          } else if (dir === 'left' || dir === 'right') {
            const next = nextHeader(cur!, dir)
            if (next) setFocus(next)
          }
          return
        }
        // Nothing focused yet (or stale). Up reaches the first header; any
        // other direction enters the content grid at the first card.
        if (!curAlive) {
          if (dir === 'up') {
            const first = firstHeader()
            if (first) setFocus(first.id)
            return
          }
          if (dir === 'left') {
            const sb = firstSidebar()
            if (sb) {
              setFocus(sb.id)
              return
            }
          }
          const first = firstInDomOrder()
          if (first) setFocus(first.id)
          return
        }
        const next = findNext(entries.current, cur!, dir)
        if (next) {
          setFocus(next)
        } else if (dir === 'up') {
          // Nothing above the top row. With a hero, release focus up to reveal
          // it (a second Up then reaches the header). Without one, jump straight
          // to the header so it's a single press.
          if (heroVisible()) {
            releaseToTop()
          } else {
            const first = firstHeader()
            if (first) setFocus(first.id)
          }
        } else if (dir === 'left') {
          // Nothing to the left of the first column. If a sidebar rail is
          // present, jump into it (Hotstar/Netflix-style left rail).
          const sb = firstSidebar()
          if (sb) {
            sidebarReturnFocus.current = cur
            setFocus(sb.id)
          }
        }
        return
      }

      const curEntry =
        focusIdRef.current != null
          ? entries.current.get(focusIdRef.current)
          : null
      const inInput = curEntry?.isInput === true

      if (e.key === 'Enter' || e.key === ' ') {
        // Space types into a focused input; only Enter acts on it.
        if (inInput && e.key === ' ') return
        e.preventDefault()
        if (curEntry) curEntry.onSelect?.()
        return
      }

      if (e.key === 'Escape' || e.key === 'Backspace') {
        // Backspace edits the text in a focused input rather than going back;
        // Escape still exits.
        if (inInput && e.key === 'Backspace') return
        e.preventDefault()
        onBack?.()
      }
    }

    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [
    setFocus,
    onBack,
    firstInDomOrder,
    releaseToTop,
    firstHeader,
    nextHeader,
    firstSidebar,
    nextSidebar,
    heroVisible,
  ])

  return (
    <FocusContext.Provider value={{ register, unregister, focusId, setFocus, setActive }}>
      {children}
    </FocusContext.Provider>
  )
}

let idCounter = 0

/**
 * Register a focusable node. Returns a ref to attach and whether it is focused.
 */
export function useFocusable<T extends HTMLElement = HTMLElement>(opts?: {
  onSelect?: () => void
  onFocus?: () => void
  isHeader?: boolean
  isSidebar?: boolean
  isInput?: boolean
  isCurrent?: boolean
  scrollMode?: 'start' | 'top' | 'nearest'
  active?: boolean
}) {
  const ctx = useContext(FocusContext)
  if (!ctx) throw new Error('useFocusable must be used within a FocusProvider')

  const idRef = useRef<string>('')
  if (!idRef.current) idRef.current = `f${idCounter++}`
  const id = idRef.current

  const ref = useRef<T | null>(null)
  const optsRef = useRef(opts)
  optsRef.current = opts

  // Keep stable refs to context methods so the layout effect doesn't re-run
  // on every focus change (which would unregister + re-register every
  // focusable element, creating a window where entries vanish).
  const registerRef = useRef(ctx.register)
  registerRef.current = ctx.register
  const unregisterRef = useRef(ctx.unregister)
  unregisterRef.current = ctx.unregister
  const setActiveRef = useRef(ctx.setActive)
  setActiveRef.current = ctx.setActive

  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    registerRef.current({
      id,
      element: el,
      onSelect: () => optsRef.current?.onSelect?.(),
      onFocus: () => optsRef.current?.onFocus?.(),
      isHeader: optsRef.current?.isHeader,
      isSidebar: optsRef.current?.isSidebar,
      isInput: optsRef.current?.isInput,
      isCurrent: optsRef.current?.isCurrent,
      scrollMode: optsRef.current?.scrollMode,
      active: optsRef.current?.active !== false,
    })
    return () => unregisterRef.current(id)
  }, [id])

  // Sync `active` changes without re-registering (keeps element ref stable).
  useEffect(() => {
    setActiveRef.current(id, opts?.active !== false)
  }, [id, opts?.active])

  return {
    ref: ref as React.RefObject<T>,
    focused: ctx.focusId === id,
    focusSelf: () => ctx.setFocus(id),
  }
}
