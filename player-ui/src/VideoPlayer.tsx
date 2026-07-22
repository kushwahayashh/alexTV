import { useEffect, useRef, useState, useCallback } from 'react'

/**
 * Standalone video player UI for iterating on the controls overlay.
 *
 * Layout:
 *   Top bar:    [title]
 *   Bottom bar: [seekbar]
 *               [current time           total time]
 *               [Subtitles] [Audio]
 *
 * Focus model (D-pad):
 *   Row 0: [seek]
 *   Row 1: [subtitles] [audio]
 *
 *   - Up/Down moves between rows.
 *   - Left/Right moves within a row, EXCEPT on the seekbar where it seeks 10s.
 *   - Enter triggers the focused control's action (seekbar toggles play/pause).
 *   - Backspace/Escape closes the player (or closes an open menu first).
 *
 * Controls auto-hide after 4s of inactivity; any key resurfaces them.
 */

const SEEK_STEP = 10 // seconds per arrow press on the seekbar (base step)
const HIDE_DELAY = 4000 // ms of inactivity before controls fade out
// Max gap between key-repeat events still counted as "holding". Slower than
// this resets the accel ramp so a fresh tap always starts at the base step.
const ACCEL_WINDOW = 300 // ms

type ControlId = 'seek' | 'subtitles' | 'audio'
type MenuKind = 'audio' | 'subtitles'

// Mock tracks shown in the Audio / Subtitles menus. Both use the same modal UI
// (player-overlay / player-modal / player-list / player-item) as the main
// app's quality picker in src/components/Player.tsx.
type Track = { id: string; label: string; meta: string }

// Placeholder rows matching the Compose PlayerActivity structure:
//  - OFF: first row of ORG subs, index 0, default-selected (no subtitles).
//  - NONE: shown in WebSubs when there are no sideloaded web subs.
//  - DEFAULT_AUDIO: shown in Audio when ExoPlayer parsed no audio tracks.
const OFF_TRACK: Track = { id: 'sub-off', label: 'Off', meta: '' }
const NONE_TRACK: Track = { id: 'web-none', label: 'None', meta: '' }
const DEFAULT_AUDIO_TRACK: Track = { id: 'audio-none', label: 'Default', meta: '' }

const AUDIO_TRACKS: Track[] = [
  { id: 'en-51', label: 'English', meta: '5.1 · AC3' },
  { id: 'en-stereo', label: 'English', meta: 'Stereo · AAC' },
  { id: 'es-stereo', label: 'Spanish', meta: 'Stereo · AAC' },
]

const SUBTITLE_ORG: Track[] = [
  { id: 'org-en', label: 'English', meta: 'Embedded' },
  { id: 'org-en-sdh', label: 'English (SDH)', meta: 'Embedded' },
  { id: 'org-es', label: 'Spanish', meta: 'Embedded' },
]

const SUBTITLE_WEB: Track[] = [
  { id: 'web-en', label: 'English', meta: 'Web' },
  { id: 'web-es', label: 'Spanish', meta: 'Web' },
  { id: 'web-fr', label: 'French', meta: 'Web' },
  { id: 'web-de', label: 'German', meta: 'Web' },
  { id: 'web-it', label: 'Italian', meta: 'Web' },
  { id: 'web-pt', label: 'Portuguese', meta: 'Web' },
  { id: 'web-ja', label: 'Japanese', meta: 'Web' },
  { id: 'web-ko', label: 'Korean', meta: 'Web' },
  { id: 'web-ar', label: 'Arabic', meta: 'Web' },
]

// Per-menu config: a list of sections (each with its own heading). D-pad
// navigation flows through every section as one continuous index; the headings
// only divide the list visually. Structure mirrors the Compose PlayerActivity:
//  - Audio: single section, "Default" placeholder if no tracks.
//  - Subtitles: ORG subs = "Off" + embedded tracks; WebSubs = web tracks or
//    "None" placeholder if empty.
type MenuSection = { heading: string; tracks: Track[] }
const MENUS: Record<MenuKind, MenuSection[]> = {
  audio: [
    {
      heading: 'Audio Tracks',
      tracks: AUDIO_TRACKS.length ? AUDIO_TRACKS : [DEFAULT_AUDIO_TRACK],
    },
  ],
  subtitles: [
    { heading: 'ORG subs', tracks: [OFF_TRACK, ...SUBTITLE_ORG] },
    {
      heading: 'WebSubs',
      tracks: SUBTITLE_WEB.length ? SUBTITLE_WEB : [NONE_TRACK],
    },
  ],
}

// Flattened track list for a menu — used for indexing + selection.
function menuTracks(kind: MenuKind): Track[] {
  return MENUS[kind].flatMap((s) => s.tracks)
}

// Rows are ordered top-to-bottom so D-pad Up/Down matches on-screen layout:
// the Subtitles/Audio pills sit in the top bar, the seekbar in the bottom bar.
const ROW_ORDER: ControlId[][] = [
  ['subtitles', 'audio'],
  ['seek'],
]

function fmtTime(sec: number) {
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = Math.floor(sec % 60)
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${m}:${String(s).padStart(2, '0')}`
}

// Inline icons for the top-bar controls. 24px viewBox, currentColor so they
// pick up the button's text color (and invert on focus with the circle button).
function SubtitlesIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="3" y="5" width="18" height="14" rx="2.5" fill="none" stroke="currentColor" strokeWidth="2" />
      <rect x="6" y="13" width="5" height="2" rx="1" fill="currentColor" />
      <rect x="13" y="13" width="5" height="2" rx="1" fill="currentColor" />
      <rect x="6" y="9" width="8" height="2" rx="1" fill="currentColor" />
      <rect x="16" y="9" width="2" height="2" rx="1" fill="currentColor" />
    </svg>
  )
}

function AudioIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path stroke="none" d="M0 0h24v24H0z" fill="none" />
      <path d="M16.083 2h-4.083a1 1 0 0 0 -1 1v11.5a1.5 1.5 0 1 1 -2.519 -1.1l.12 -.1a1 1 0 0 0 .399 -.8v-4.326a1 1 0 0 0 -1.23 -.974a7.5 7.5 0 0 0 1.73 14.8l.243 -.005a7.5 7.5 0 0 0 7.257 -7.495v-2.7l.311 .153c1.122 .53 2.333 .868 3.59 .993a1 1 0 0 0 1.099 -.996v-4.033a1 1 0 0 0 -.834 -.986a5.005 5.005 0 0 1 -4.097 -4.096a1 1 0 0 0 -.986 -.835z" />
    </svg>
  )
}

export function VideoPlayer({
  title,
  duration,
  onClose,
}: {
  title: string
  duration: number
  onClose: () => void
}) {
  const [position, setPosition] = useState(0)
  const [isPlaying, setIsPlaying] = useState(true)
  const [focused, setFocused] = useState<ControlId>('seek')
  const [controlsVisible, setControlsVisible] = useState(true)
  const hideTimer = useRef<number | null>(null)

  // Menu state: which menu (if any) is open, which row is highlighted while
  // navigating it, and the selected track per menu kind.
  const [selected, setSelected] = useState<Record<MenuKind, number>>({
    audio: 0,
    subtitles: 0,
  })
  const [menuOpen, setMenuOpen] = useState<MenuKind | null>(null)
  const [menuIdx, setMenuIdx] = useState(0)

  // Refs so the keyboard listener never needs to re-register.
  const focusedRef = useRef(focused)
  focusedRef.current = focused
  const menuOpenRef = useRef(menuOpen)
  menuOpenRef.current = menuOpen
  const menuIdxRef = useRef(menuIdx)
  menuIdxRef.current = menuIdx
  const selectedRef = useRef(selected)
  selectedRef.current = selected
  // Snapshot of controls visibility, read at the top of onKey BEFORE the
  // activity bump re-shows them — so Back can tell if they were hidden.
  const controlsVisibleRef = useRef(controlsVisible)
  controlsVisibleRef.current = controlsVisible

  // Refs for target-scroll: every rendered row, the scroll container, and the
  // direction of the last Up/Down move (so we can lead the scroll ahead of the
  // highlight). Mirrors the homepage's scrollIntoView-based auto-scroll.
  const itemRefs = useRef<(HTMLButtonElement | null)[]>([])
  const modalRef = useRef<HTMLDivElement | null>(null)
  const menuDirRef = useRef(0) // -1 up, +1 down, 0 on open

  // Accelerated seeking: while Left/Right is held on the seekbar, each repeat
  // grows the step so a long hold covers ground fast. accelCount is the run of
  // consecutive presses in one direction; accelDir is that direction (-1/+1);
  // accelLast is the timestamp of the last press (to detect release/pause).
  const accelCountRef = useRef(0)
  const accelDirRef = useRef(0)
  const accelLastRef = useRef(0)

  // Mock playback timer — advances position when playing.
  useEffect(() => {
    if (!isPlaying) return
    const id = window.setInterval(() => {
      setPosition((p) => (p >= duration ? duration : p + 1))
    }, 1000)
    return () => window.clearInterval(id)
  }, [isPlaying, duration])

  // Auto-hide controls after inactivity.
  const bumpActivity = useCallback(() => {
    setControlsVisible(true)
    if (hideTimer.current) window.clearTimeout(hideTimer.current)
    hideTimer.current = window.setTimeout(() => {
      setControlsVisible(false)
    }, HIDE_DELAY)
  }, [])

  useEffect(() => {
    bumpActivity()
    return () => {
      if (hideTimer.current) window.clearTimeout(hideTimer.current)
    }
  }, [bumpActivity])

  // Keep the highlighted menu row in view with a "trail" behind it. Rather than
  // waiting until the highlight hits an edge, we scroll a row LEAD positions
  // ahead of it into view, so ~LEAD rows stay visible in the direction of
  // travel. At the very top/bottom we snap the container fully so the section
  // heading (top) or last row (bottom) is never clipped. Same smooth
  // scrollIntoView the homepage's FocusEngine uses.
  useEffect(() => {
    if (!menuOpen) return
    const count = menuTracks(menuOpen).length
    const LEAD = 3
    const modal = modalRef.current

    // Near an end → snap the whole container so nothing gets clipped.
    if (modal && menuIdx <= LEAD) {
      modal.scrollTo({ top: 0, behavior: 'smooth' })
      return
    }
    if (modal && menuIdx >= count - 1 - LEAD) {
      modal.scrollTo({ top: modal.scrollHeight, behavior: 'smooth' })
      return
    }

    // Otherwise reveal a row LEAD ahead in the direction of travel, leaving a
    // trail of rows behind the highlight.
    const target = Math.max(0, Math.min(count - 1, menuIdx + menuDirRef.current * LEAD))
    itemRefs.current[target]?.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
  }, [menuOpen, menuIdx])

  const seekBy = useCallback(
    (delta: number) => {
      setPosition((p) => Math.max(0, Math.min(duration, p + delta)))
    },
    [duration],
  )

  // Compute one accelerated seek step for a Left/Right press. A fresh tap (or a
  // direction change, or a press after the accel window lapses) starts at the
  // base step; holding the key ramps the step up in tiers the longer it's held.
  const accelSeek = useCallback(
    (dir: -1 | 1) => {
      const now = Date.now()
      const held =
        accelDirRef.current === dir && now - accelLastRef.current <= ACCEL_WINDOW
      accelCountRef.current = held ? accelCountRef.current + 1 : 0
      accelDirRef.current = dir
      accelLastRef.current = now

      // Tiered multiplier by how long the key has been held. Gentle ramp:
      // stays at the base step for a while, then eases up.
      const c = accelCountRef.current
      const mult = c < 8 ? 1 : c < 18 ? 2 : c < 30 ? 3 : 4
      seekBy(dir * SEEK_STEP * mult)
    },
    [seekBy],
  )

  // Single stable keyboard listener — reads from refs.
  useEffect(() => {
    function findInRow(dir: 'left' | 'right'): ControlId | null {
      const cur = focusedRef.current
      const rowIdx = ROW_ORDER.findIndex((r) => r.includes(cur))
      const row = ROW_ORDER[rowIdx]
      const colIdx = row.indexOf(cur)
      if (dir === 'left' && colIdx > 0) return row[colIdx - 1]
      if (dir === 'right' && colIdx < row.length - 1) return row[colIdx + 1]
      return null
    }

    function moveRow(dir: 'up' | 'down'): ControlId | null {
      const cur = focusedRef.current
      const rowIdx = ROW_ORDER.findIndex((r) => r.includes(cur))
      const next = dir === 'up' ? rowIdx - 1 : rowIdx + 1
      if (next < 0 || next >= ROW_ORDER.length) return null
      const row = ROW_ORDER[next]
      const colIdx = ROW_ORDER[rowIdx].indexOf(cur)
      return row[Math.min(colIdx, row.length - 1)] ?? row[0]
    }

    function openMenu(kind: MenuKind) {
      menuDirRef.current = 0
      setMenuIdx(selectedRef.current[kind])
      setMenuOpen(kind)
    }

    function trigger(id: ControlId) {
      switch (id) {
        case 'seek':
          setIsPlaying((p) => !p)
          break
        case 'audio':
          openMenu('audio')
          break
        case 'subtitles':
          openMenu('subtitles')
          break
      }
    }

    function onKey(e: KeyboardEvent) {
      // Read visibility before the bump re-shows the controls.
      const wasVisible = controlsVisibleRef.current
      bumpActivity()

      // ---- A menu is open: it captures all navigation ----
      const openKind = menuOpenRef.current
      if (openKind) {
        const count = menuTracks(openKind).length
        switch (e.key) {
          case 'ArrowUp':
            e.preventDefault()
            menuDirRef.current = -1
            setMenuIdx((i) => Math.max(0, i - 1))
            return
          case 'ArrowDown':
            e.preventDefault()
            menuDirRef.current = 1
            setMenuIdx((i) => Math.min(count - 1, i + 1))
            return
          case 'Enter':
          case ' ':
            e.preventDefault()
            setSelected((s) => ({ ...s, [openKind]: menuIdxRef.current }))
            setMenuOpen(null)
            return
          case 'Escape':
          case 'Backspace':
            e.preventDefault()
            setMenuOpen(null)
            return
          default:
            return
        }
      }

      const cur = focusedRef.current

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault()
          if (cur === 'seek') {
            accelSeek(-1)
          } else {
            const n = findInRow('left')
            if (n) setFocused(n)
          }
          return
        case 'ArrowRight':
          e.preventDefault()
          if (cur === 'seek') {
            accelSeek(1)
          } else {
            const n = findInRow('right')
            if (n) setFocused(n)
          }
          return
        case 'ArrowUp': {
          e.preventDefault()
          const n = moveRow('up')
          if (n) setFocused(n)
          return
        }
        case 'ArrowDown': {
          e.preventDefault()
          const n = moveRow('down')
          if (n) setFocused(n)
          return
        }
        case 'Enter':
        case ' ':
          e.preventDefault()
          trigger(cur)
          return
        case 'Escape':
        case 'Backspace':
          e.preventDefault()
          // If the controls were visible, Back just hides them. Only Back with
          // controls already hidden closes the player.
          if (wasVisible) {
            if (hideTimer.current) window.clearTimeout(hideTimer.current)
            setControlsVisible(false)
          } else {
            onClose()
          }
          return
      }
    }

    // Releasing the arrow key ends the hold, so the next press starts fresh
    // at the base step.
    function onKeyUp(e: KeyboardEvent) {
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        accelCountRef.current = 0
        accelDirRef.current = 0
      }
    }

    window.addEventListener('keydown', onKey)
    window.addEventListener('keyup', onKeyUp)
    return () => {
      window.removeEventListener('keydown', onKey)
      window.removeEventListener('keyup', onKeyUp)
    }
  }, [bumpActivity, seekBy, accelSeek, onClose])

  const progress = duration > 0 ? position / duration : 0
  const pct = `${(progress * 100).toFixed(1)}%`

  return (
    <div className="player-stage">
      <img
        className="player-mock-video"
        src="https://image.tmdb.org/t/p/original/O2ioY0wpltYjcevoP90MCEhGVO.jpg"
        alt=""
      />

      {/* Top bar */}
      <div className={`player-top${controlsVisible ? '' : ' player-top--hidden'}`}>
        <div className="player-top__title">{title}</div>
      </div>

      {/* Bottom bar */}
      <div className={`player-bottom${controlsVisible ? '' : ' player-bottom--hidden'}`}>
        {/* Icon controls, right-aligned above the seek bar */}
        <div className="player-controls">
          <button
            className={`player-circle-btn${focused === 'subtitles' ? ' player-circle-btn--focused' : ''}`}
            type="button"
            aria-label="Subtitles"
          >
            <SubtitlesIcon />
          </button>
          <button
            className={`player-circle-btn${focused === 'audio' ? ' player-circle-btn--focused' : ''}`}
            type="button"
            aria-label="Audio"
          >
            <AudioIcon />
          </button>
        </div>
        <div className="player-seek">
          <div
            className={`player-seek__bar${focused === 'seek' ? ' player-seek__bar--focused' : ''}`}
          >
            <div className="player-seek__fill" style={{ width: pct }} />
          </div>
          <div className="player-seek__times">
            <span className="player-seek__time">{fmtTime(position)}</span>
            <span className="player-seek__time">{fmtTime(duration)}</span>
          </div>
        </div>
      </div>

      {/* Audio / Subtitles menu — same modal UI as the main app's quality picker */}
      {menuOpen && (
        <div className="player-overlay">
          <div className="player-modal">
            <div className="player-modal__scroll" ref={modalRef}>
              {(() => {
              let gi = -1 // running index across all sections
              return MENUS[menuOpen].map((section) => (
                <div key={section.heading} className="player-menu-section">
                  <div className="player-modal__title">{section.heading}</div>
                  <div className="player-list">
                    {section.tracks.map((track) => {
                      const idx = ++gi
                      return (
                        <button
                          key={track.id}
                          ref={(el) => {
                            itemRefs.current[idx] = el
                          }}
                          className={`player-item${idx === menuIdx ? ' player-item--focused' : ''}`}
                          type="button"
                        >
                          <span className="player-item__label">
                            {track.label}
                            {idx === selected[menuOpen] ? ' ✔' : ''}
                          </span>
                          <span className="player-item__meta">{track.meta}</span>
                        </button>
                      )
                    })}
                  </div>
                </div>
              ))
            })()}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
