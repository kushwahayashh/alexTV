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
 * Three-step playback modal:
 *   1. Resolve movie → list video files
 *   2. Pick a file → fetch stream links (quality options)
 *   3. Pick a link → play in <video> (HLS via hls.js, native mp4)
 */
export function Player({ media, onClose }: { media: Media; onClose: () => void }) {
  const [phase, setPhase] = useState<Phase>('loading')
  const [files, setFiles] = useState<VideoFile[]>([])
  const [links, setLinks] = useState<StreamLink[]>([])
  const [streamUrl, setStreamUrl] = useState<string | null>(null)
  const [error, setError] = useState('')

  // Kick off the resolve chain on mount.
  useEffect(() => {
    let alive = true
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
  }, [media])

  // Intercept Escape in capture phase so it closes the player instead of
  // bubbling to the FocusEngine's onBack (which would exit Details entirely).
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== 'Escape' && e.key !== 'Backspace') return
      e.preventDefault()
      e.stopPropagation()
      setPhase((p) => {
        if (p === 'links') return 'files'
        onClose()
        return p
      })
    }
    window.addEventListener('keydown', onKey, true)
    return () => window.removeEventListener('keydown', onKey, true)
  }, [onClose])

  // Play a given stream link.
  function playLink(link: StreamLink) {
    setStreamUrl(link.proxiedUrl)
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
        <VideoPlayer url={streamUrl} />
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
function VideoPlayer({ url }: { url: string }) {
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
        controls
        autoPlay
      />
      {usingHls && <div className="player-badge">HLS</div>}
    </div>
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
