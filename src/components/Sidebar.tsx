import { useCallback, useEffect, useState, type ReactNode } from 'react'
import { useFocusable } from '../focus/FocusEngine'
import {
  HomeIcon,
  SearchIcon,
  LibraryIcon,
  FilmIcon,
  TvIcon,
  SettingsIcon,
  UpdateIcon,
} from './icons'

/**
 * Netflix/Hotstar-style left sidebar. Collapsed by default (icon only), it
 * expands to reveal the label when any of its items holds focus. Each item is
 * a focus engine sidebar entry, so D-pad Up/Down walks the rail and Right drops
 * into the content; Left from the leftmost content column reaches it.
 *
 * Items are mocks for now — onSelect is wired for Home/Search/Library, the
 * rest are placeholders pending real screens.
 */

export type SidebarItem = {
  id: string
  label: string
  icon: ReactNode
  onSelect?: () => void
}

/**
 * Canonical nav rail, shared by every screen that shows the sidebar. Screens
 * wire the handlers they can service via `withHandlers`; the rest stay
 * placeholders until their screens exist.
 */
export const NAV_ITEMS: SidebarItem[] = [
  { id: 'home', label: 'Home', icon: <HomeIcon /> },
  { id: 'search', label: 'Search', icon: <SearchIcon /> },
  { id: 'library', label: 'Library', icon: <LibraryIcon /> },
  { id: 'movies', label: 'Movies', icon: <FilmIcon /> },
  { id: 'tv', label: 'TV Shows', icon: <TvIcon /> },
  { id: 'settings', label: 'Settings', icon: <SettingsIcon /> },
  { id: 'update', label: 'Update', icon: <UpdateIcon /> },
]

/** Attach onSelect handlers to nav items by id; unmatched items stay as-is. */
export function withHandlers(
  handlers: Record<string, (() => void) | undefined>,
): SidebarItem[] {
  return NAV_ITEMS.map((it) => ({ ...it, onSelect: handlers[it.id] }))
}

function SidebarItemView({
  item,
  onFocusChange,
}: {
  item: SidebarItem
  onFocusChange: (focused: boolean) => void
}) {
  const { ref, focused } = useFocusable({
    isHeader: true,
    isSidebar: true,
    onSelect: () => item.onSelect?.(),
  })

  useEffect(() => {
    onFocusChange(focused)
  }, [focused, onFocusChange])

  return (
    <button
      ref={ref as React.RefObject<HTMLButtonElement>}
      className={`sidebar__item${focused ? ' sidebar__item--focused' : ''}`}
      type="button"
      aria-label={item.label}
    >
      <span className="sidebar__icon">{item.icon}</span>
      <span className="sidebar__label">{item.label}</span>
    </button>
  )
}

export function Sidebar({ items }: { items: SidebarItem[] }) {
  // Count of currently-focused items (at most one). The rail expands whenever
  // that count is > 0. Using a counter (not a boolean) keeps the expand state
  // correct as focus hops between adjacent items: blur fires before focus, so
  // a naive boolean would briefly drop to false mid-transition.
  const [focusedCount, setFocusedCount] = useState(0)
  const expanded = focusedCount > 0

  // Stable callback so the item effect deps don't churn on every render.
  const onFocusChange = useCallback(
    (focused: boolean) => {
      setFocusedCount((n) => (focused ? n + 1 : Math.max(0, n - 1)))
    },
    [],
  )

  return (
    <nav className={`sidebar${expanded ? ' sidebar--expanded' : ''}`} aria-label="Main">
      <div className="sidebar__items">
        {items.map((item) => (
          <SidebarItemView
            key={item.id}
            item={item}
            onFocusChange={onFocusChange}
          />
        ))}
      </div>
    </nav>
  )
}
