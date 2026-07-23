/**
 * Inline SVG icons for the sidebar. 24x24, currentColor, no fill so they pick
 * up the focused/unfocused colour from CSS. Kept minimal and stroke-based to
 * match the rest of the UI.
 */

type P = { className?: string }

const base = {
  width: 24,
  height: 24,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
}

export function HomeIcon({ className }: P) {
  return (
    <svg {...base} className={className}>
      <path d="M3 11.5L12 4l9 7.5" />
      <path d="M5 10v10h14V10" />
    </svg>
  )
}

export function SearchIcon({ className }: P) {
  return (
    <svg {...base} className={className}>
      <circle cx="11" cy="11" r="7" />
      <path d="M21 21l-4.3-4.3" />
    </svg>
  )
}

export function LibraryIcon({ className }: P) {
  return (
    <svg {...base} className={className}>
      <path d="M4 4h4v16H4z" />
      <path d="M10 4h4v16h-4z" />
      <path d="M17 5l3 .8-3 14.2-3-.8z" />
    </svg>
  )
}

export function FilmIcon({ className }: P) {
  return (
    <svg {...base} className={className}>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M7 4v16M17 4v16M3 9h4M17 9h4M3 15h4M17 15h4" />
    </svg>
  )
}

export function TvIcon({ className }: P) {
  return (
    <svg {...base} className={className}>
      <rect x="3" y="7" width="18" height="13" rx="2" />
      <path d="M8 3l4 4 4-4" />
    </svg>
  )
}

export function SettingsIcon({ className }: P) {
  return (
    <svg {...base} className={className}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </svg>
  )
}

export function UpdateIcon({ className }: P) {
  // Download-to-tray glyph — arrow into a base line, reads as "download update".
  return (
    <svg {...base} className={className}>
      <path d="M12 3v12" />
      <path d="M7 10l5 5 5-5" />
      <path d="M5 21h14" />
    </svg>
  )
}

// Filled tabler glyphs (fill, no stroke) for action buttons.
const filled = {
  width: 24,
  height: 24,
  viewBox: '0 0 24 24',
  fill: 'currentColor',
}

export function PlayIcon({ className }: P) {
  return (
    <svg {...filled} className={className}>
      <path d="M6 4v16a1 1 0 0 0 1.524 .852l13 -8a1 1 0 0 0 0 -1.704l-13 -8a1 1 0 0 0 -1.524 .852z" />
    </svg>
  )
}

export function PlusIcon({ className }: P) {
  return (
    <svg {...filled} className={className}>
      <path d="M12 4a1 1 0 0 1 1 1v6h6a1 1 0 0 1 0 2h-6v6a1 1 0 0 1 -2 0v-6h-6a1 1 0 0 1 0 -2h6v-6a1 1 0 0 1 1 -1" />
    </svg>
  )
}
