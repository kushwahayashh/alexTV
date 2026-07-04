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

const SEEK_STEP = 10 // seconds per arrow press on the seekbar
const HIDE_DELAY = 4000 // ms of inactivity before controls fade out

type ControlId = 'seek' | 'subtitles' | 'audio'

const ROW_ORDER: ControlId[][] = [
  ['seek'],
  ['subtitles', 'audio'],
]

function fmtTime(sec: number) {
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = Math.floor(sec % 60)
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${m}:${String(s).padStart(2, '0')}`
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

  // Refs so the keyboard listener never needs to re-register.
  const focusedRef = useRef(focused)
  focusedRef.current = focused

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

  const seekBy = useCallback(
    (delta: number) => {
      setPosition((p) => Math.max(0, Math.min(duration, p + delta)))
    },
    [duration],
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

    function trigger(id: ControlId) {
      switch (id) {
        case 'seek':
          setIsPlaying((p) => !p)
          break
      }
    }

    function onKey(e: KeyboardEvent) {
      bumpActivity()
      const cur = focusedRef.current

      switch (e.key) {
        case 'ArrowLeft':
          e.preventDefault()
          if (cur === 'seek') {
            seekBy(-SEEK_STEP)
          } else {
            const n = findInRow('left')
            if (n) setFocused(n)
          }
          return
        case 'ArrowRight':
          e.preventDefault()
          if (cur === 'seek') {
            seekBy(SEEK_STEP)
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
          onClose()
          return
      }
    }

    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [bumpActivity, seekBy, onClose])

  const progress = duration > 0 ? position / duration : 0
  const pct = `${(progress * 100).toFixed(1)}%`

  return (
    <div className="player-stage">
      <img
        className="player-mock-video"
        src="https://image.tmdb.org/t/p/original/r013C8Me2bZ0pUi0OWJRh0h7MzT.jpg"
        alt=""
      />

      {/* Top bar */}
      <div className={`player-top${controlsVisible ? '' : ' player-top--hidden'}`}>
        <div className="player-top__title">{title}</div>
      </div>

      {/* Center play indicator (when paused) */}
      {!isPlaying && (
        <div className="player-center-icon" aria-hidden>
          ▶
        </div>
      )}

      {/* Bottom bar */}
      <div className={`player-bottom${controlsVisible ? '' : ' player-bottom--hidden'}`}>
        <div className="player-seek">
          <div
            className={`player-seek__bar${focused === 'seek' ? ' player-seek__bar--focused' : ''}`}
          >
            <div className="player-seek__fill" style={{ width: pct }} />
            <div className="player-seek__playhead" style={{ left: pct }} />
          </div>
          <div className="player-seek__times">
            <span className="player-seek__time">{fmtTime(position)}</span>
            <span className="player-seek__time">{fmtTime(duration)}</span>
          </div>
        </div>

        <div className="player-controls-row">
          <button
            className={`player-pill-btn${focused === 'subtitles' ? ' player-pill-btn--focused' : ''}`}
            type="button"
          >
            Subtitles
          </button>
          <button
            className={`player-pill-btn${focused === 'audio' ? ' player-pill-btn--focused' : ''}`}
            type="button"
          >
            Audio
          </button>
        </div>
      </div>
    </div>
  )
}
