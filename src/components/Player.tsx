import { useEffect, useRef, useState } from 'react'
import Hls from 'hls.js'
import { useFocusable } from '../focus/FocusEngine'
import {
  resolveMovie,
  getLinks,
  type VideoFile,
  type StreamLink,
} from '../api/stream'
import type { Media } from '../api/tmdb'

type Phase = 'loading' | 'files' | 'links' | 'playing' | 'error'

/**
 * Playback modal. Two entry modes:
 *   • Movie (no `startFid`): resolve title → list files → pick file → links → play.
 *   • Episode (`startFid` given): the caller (Details) already resolved the
 *     episode file, so skip straight to fetching its quality links → play.
 */
export function Player({
  media,
  startFid,
  title,
  onClose,
}: {
  media: Media
  startFid?: number
  title?: string
  onClose: () => void
}) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [files, setFiles] = useState<VideoFile[]>([])
  const [links, setLinks] = useState<StreamLink[]>([])
  const [streamUrl, setStreamUrl] = useState<string | null>(null)
  const [error, setError] = useState('')

  // Title shown on the playback controls (episode label or movie title).
  const displayTitle = title || media.title

  // Kick off the resolve chain on mount. Episodes skip resolve — the caller
  // handed us the file's fid, so go straight to its links.
  useEffect(() => {
    let alive = true
    if (startFid != null) {
      getLinks(startFid)
        .then((l) => {
          if (!alive) return
          setLinks(l)
          setPhase(l.length ? 'links' : 'error')
          if (!l.length) setError('No stream links for this episode.')
        })
        .catch((e) => {
          if (!alive) return
          setError(String(e.message || e))
          setPhase('error')
        })
      return () => {
        alive = false
      }
    }
    resolveMovie(media.title, media.year)
      .then((f) => {
        if (!alive) return
        setFiles(f)
        setPhase(f.length ? 'files' : 'error')
        if (!f.length) setError('No video files found.')
      })
      .catch((e) => {
        if (!alive) return
        setError(String(e.message || e))
        setPhase('error')
      })
    return () => {
      alive = false
    }
  }, [media, startFid])

  // Intercept Escape in capture phase so it closes the player instead of
  // bubbling to the FocusEngine's onBack (which would exit Details entirely).
  // Back ladder: links → files (movie) or links → close (episode).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== 'Escape' && e.key !== 'Backspace') return
      e.preventDefault()
      e.stopPropagation()
      setPhase((p) => {
        if (p === 'links' && startFid == null) return 'files'
        onClose()
        return p
      })
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [onClose, startFid])

  // Play a given stream link.
  function playLink(link: StreamLink) {
    setStreamUrl(link.url)
    setPhase('playing')
  }

  // Pick a file → fetch its links.
  function pickFile(file: VideoFile) {
    setPhase('loading')
    getLinks(file.fid)
      .then((l) => {
        setLinks(l)
        setPhase(l.length ? 'links' : 'error')
        if (!l.length) setError('No stream links for this file.')
      })
      .catch((e) => {
        setError(String(e.message || e))
        setPhase('error')
      })
  }

  return (
    <div className="player-overlay">
      {phase === 'loading' && (
        <div className="player-modal">
          <div className="player-list">
            {[0, 1, 2].map((i) => (
              <div key={i} className="player-skeleton" />
            ))}
          </div>
        </div>
      )}

      {phase === 'files' && (
        <FilePicker files={files} onPick={pickFile} />
      )}

      {phase === 'links' && (
        <QualityPicker links={links} onPick={playLink} />
      )}

      {phase === 'playing' && streamUrl && (
        <VideoPlayer url={streamUrl} title={displayTitle} />
      )}

      {phase === 'error' && (
        <ErrorState error={error} onClose={onClose} />
      )}
    </div>
  )
}

/* ---------- Focusable list item ---------- */
function PlayerItem({
  label,
  meta,
  onSelect,
  autoFocus,
}: {
  label: string
  meta: string
  onSelect: () => void
  autoFocus?: boolean
}) {
  const { ref, focused, focusSelf } = useFocusable({ onSelect })

  useEffect(() => {
    if (autoFocus) focusSelf()
  }, [])

  return (
    <button
      ref={ref as React.RefObject<HTMLButtonElement>}
      className={`player-item${focused ? ' player-item--focused' : ''}`}
      type="button"
    >
      <span className="player-item__label">{label}</span>
      <span className="player-item__meta">{meta}</span>
    </button>
  )
}

/* ---------- Step 1: File picker ---------- */
function FilePicker({
  files,
  onPick,
}: {
  files: VideoFile[]
  onPick: (f: VideoFile) => void
}) {
  return (
    <div className="player-modal">
      <div className="player-list">
        {files.map((f, i) => (
          <PlayerItem
            key={f.fid}
            label={f.file_name}
            meta={`${f.resLabel} · ${f.file_size}`}
            onSelect={() => onPick(f)}
            autoFocus={i === 0}
          />
        ))}
      </div>
    </div>
  )
}

/* ---------- Step 2: Quality picker ---------- */
function QualityPicker({
  links,
  onPick,
}: {
  links: StreamLink[]
  onPick: (l: StreamLink) => void
}) {
  return (
    <div className="player-modal">
      <div className="player-list">
        {links.map((link, i) => (
          <PlayerItem
            key={i}
            label={link.quality}
            meta={`${link.ext} · ${link.speed}`}
            onSelect={() => onPick(link)}
            autoFocus={i === 0}
          />
        ))}
      </div>
    </div>
  )
}

/* ---------- Step 3: Video player ---------- */
function VideoPlayer({ url, title }: { url: string; title: string }) {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [usingHls, setUsingHls] = useState(false)

  useEffect(() => {
    const video = videoRef.current
    if (!video) return

    // Native HLS (Safari) or direct mp4.
    if (video.canPlayType('application/vnd.apple.mpegurl')) {
      video.src = url
      video.play()
      return
    }

    // hls.js for Chrome/Firefox/etc.
    if (url.includes('.m3u8')) {
      const hls = new Hls()
      hls.loadSource(url)
      hls.attachMedia(video)
      hls.on(Hls.Events.MANIFEST_PARSED, () => video.play())
      setUsingHls(true)
      return () => {
        hls.destroy()
      }
    }

    // Direct mp4.
    video.src = url
    video.play()
  }, [url])

  return (
    <div className="player-video-wrap">
      <video
        ref={videoRef}
        className="player-video"
        autoPlay
        playsInline
      />
      {usingHls && <div className="player-badge">HLS</div>}
      <PlayerControls title={title} />
    </div>
  )
}

/* ---------- Player controls overlay ---------- */
const SEEK_STEP = 0.05 // 5% per arrow press

function fmtTime(sec: number) {
  const h = Math.floor(sec / 3600)
  const m = Math.floor((sec % 3600) / 60)
  const s = Math.floor(sec % 60)
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
  return `${m}:${String(s).padStart(2, '0')}`
}

function PlayerControls({ title }: { title: string }) {
  const [progress, setProgress] = useState(0.32) // 0–1
  const duration = 7695 // 2:08:15 in seconds (placeholder)

  const { ref: seekRef, focused: seekFocused } = useFocusable({ onSelect: () => {} })
  const { ref: playRef, focused: playFocused } = useFocusable({ onSelect: () => {} })
  const { ref: subRef, focused: subFocused } = useFocusable({ onSelect: () => {} })
  const { ref: audioRef, focused: audioFocused } = useFocusable({ onSelect: () => {} })

  // When the seekbar is focused, intercept left/right to seek instead of
  // letting the FocusEngine move focus to another control.
  useEffect(() => {
    if (!seekFocused) return
    function onKey(e: KeyboardEvent) {
      if (e.key === 'ArrowLeft') {
        e.preventDefault()
        e.stopPropagation()
        setProgress((p) => Math.max(0, p - SEEK_STEP))
      } else if (e.key === 'ArrowRight') {
        e.preventDefault()
        e.stopPropagation()
        setProgress((p) => Math.min(1, p + SEEK_STEP))
      }
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [seekFocused])

  const currentSec = progress * duration
  const pct = `${(progress * 100).toFixed(1)}%`

  return (
    <>
      {/* Top bar: title */}
      <div className="player-top">
        <div className="player-top__title">{title}</div>
      </div>

      {/* Bottom bar: seek + controls */}
      <div className="player-bottom">
        <div className="player-seek">
          <span className="player-seek__time">{fmtTime(currentSec)}</span>
          <div
            ref={seekRef as React.RefObject<HTMLDivElement>}
            className={`player-seek__bar${seekFocused ? ' player-seek__bar--focused' : ''}`}
          >
            <div className="player-seek__fill" style={{ width: pct }} />
            <div className="player-seek__knob" style={{ left: pct }} />
          </div>
          <span className="player-seek__time">{fmtTime(duration)}</span>
        </div>

        <div className="player-controls-row">
          <button
            ref={playRef as React.RefObject<HTMLButtonElement>}
            className={`player-pill-btn${playFocused ? ' player-pill-btn--focused' : ''}`}
            type="button"
          >
            Play
          </button>
          <div style={{ flex: 1 }} />
          <button
            ref={subRef as React.RefObject<HTMLButtonElement>}
            className={`player-pill-btn${subFocused ? ' player-pill-btn--focused' : ''}`}
            type="button"
          >
            Subtitles
          </button>
          <button
            ref={audioRef as React.RefObject<HTMLButtonElement>}
            className={`player-pill-btn${audioFocused ? ' player-pill-btn--focused' : ''}`}
            type="button"
          >
            Audio
          </button>
        </div>
      </div>
    </>
  )
}

/* ---------- Error state ---------- */
function ErrorState({ error, onClose }: { error: string; onClose: () => void }) {
  const { ref, focused, focusSelf } = useFocusable({ onSelect: onClose })

  useEffect(() => {
    focusSelf()
  }, [])

  return (
    <div className="player-modal">
      <p className="player-error-text">{error}</p>
      <button
        ref={ref as React.RefObject<HTMLButtonElement>}
        className={`header-btn${focused ? ' header-btn--focused' : ''}`}
        type="button"
      >
        Back
      </button>
    </div>
  )
}
