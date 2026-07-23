import { useEffect, useState } from 'react'
import { useFocusable } from '../focus/FocusEngine'
import { IMG, type Media } from '../api/tmdb'
import {
  resolveSeries,
  getSeasonFiles,
  type VideoFile,
} from '../api/stream'
import {
  buildSeasons,
  orderedEpisodes,
  epTitle,
  type SeasonOption,
} from '../api/series'
import { FadeImage } from '../components/FadeImage'
import { Player } from '../components/Player'

/**
 * Fullscreen movie/series details page. Mirrors the hero aesthetic (backdrop,
 * scrim, left-aligned content) and adds Play + Watch Later action buttons
 * styled like the navbar pills. Focus seeds on the Play button on mount so
 * the user can immediately press Enter to play.
 *
 * For series it also renders a sticky season bar + episode list below the hero.
 * FebBox is the source of truth: seasons are folders in the resolved share,
 * episodes are the video files inside them (see src/api/series.ts). Selecting an
 * episode — or Play, which targets the first episode of the first season —
 * opens the quality picker (Player with a startFid).
 */
export function Details({ media }: { media: Media }) {
  const isTv = media.mediaType === 'tv'

  // Movie playback (resolve happens inside Player). Series playback targets a
  // specific episode file (fid), so it carries a label too for the controls.
  const [showPlayer, setShowPlayer] = useState(false)
  const [episodePlay, setEpisodePlay] = useState<{
    fid: number
    label: string
  } | null>(null)
  const playerOpen = showPlayer || episodePlay != null

  // Series stream state, all sourced from FebBox.
  const [shareKey, setShareKey] = useState<string | null>(null)
  const [seasons, setSeasons] = useState<SeasonOption[] | null>(null) // null=loading
  const [flatEpisodes, setFlatEpisodes] = useState<VideoFile[] | null>(null)
  const [activeIdx, setActiveIdx] = useState(0)
  const [episodes, setEpisodes] = useState<VideoFile[] | null>(null) // null=loading
  const [seriesError, setSeriesError] = useState<string | null>(null)
  // The fid the hero Play button targets (first episode of the first season).
  const [playFid, setPlayFid] = useState<number | null>(null)

  const play = useFocusable<HTMLButtonElement>({
    onSelect: () => {
      if (!isTv) setShowPlayer(true)
      else if (playFid != null && episodes?.length)
        openEpisode(episodes[0], 0)
    },
    scrollMode: 'top',
    active: !playerOpen,
  })
  const watchLater = useFocusable<HTMLButtonElement>({
    onSelect: () => console.log('WATCH LATER', media.title),
    scrollMode: 'top',
    active: !playerOpen,
  })

  function openEpisode(ep: VideoFile, index: number) {
    const num = ep.episode ?? index + 1
    setEpisodePlay({ fid: ep.fid, label: `${media.title} · ${epTitle(ep, num)}` })
  }

  // Resolve the series once and build the season list from the share folders.
  useEffect(() => {
    if (!isTv) return
    let alive = true
    setSeasons(null)
    setEpisodes(null)
    setFlatEpisodes(null)
    setSeriesError(null)
    setActiveIdx(0)
    setPlayFid(null)
    resolveSeries(media.title, media.year)
      .then(({ shareKey, folders, rootVideoFiles }) => {
        if (!alive) return
        setShareKey(shareKey)
        const built = buildSeasons(folders)
        setSeasons(built)
        // A flat show (synthetic single "Episodes" season) has its files at the
        // root — keep them so selectSeason renders without another fetch.
        if (built.length === 1 && built[0].fid == null) {
          setFlatEpisodes(rootVideoFiles)
        }
      })
      .catch(() =>
        alive &&
        setSeriesError(
          "This series isn't available to stream right now.",
        ),
      )
    return () => {
      alive = false
    }
  }, [isTv, media.id])

  // Load the active season's episodes (from the pre-fetched flat list, or by
  // listing the season folder).
  useEffect(() => {
    if (!isTv || !seasons) return
    const season = seasons[activeIdx]
    if (!season) return
    if (flatEpisodes) {
      setEpisodes(orderedEpisodes(flatEpisodes))
      return
    }
    if (season.fid == null || !shareKey) return
    let alive = true
    setEpisodes(null)
    getSeasonFiles(shareKey, season.fid)
      .then((vids) => alive && setEpisodes(orderedEpisodes(vids)))
      .catch(() => alive && setEpisodes([]))
    return () => {
      alive = false
    }
  }, [isTv, seasons, activeIdx, flatEpisodes, shareKey])

  // Point the hero Play button at the first episode of the loaded season.
  useEffect(() => {
    if (episodes && episodes.length && playFid == null) {
      setPlayFid(episodes[0].fid)
    }
  }, [episodes, playFid])

  // Seed focus on Play once, on mount.
  useEffect(() => {
    play.focusSelf()
  }, [])

  return (
    <div className="details">
      <div className={`details__hero${isTv ? ' details__hero--tv' : ''}`}>
        {media.backdropPath && (
          <FadeImage
            key={media.id}
            className="details__bg"
            src={IMG.backdrop(media.backdropPath)}
            alt=""
          />
        )}
        <div className="details__scrim" />
        <div key={`c-${media.id}`} className="details__content">
          <h1 className="details__title">{media.title}</h1>
          <div className="details__facts">
            <span>{isTv ? 'Series' : 'Movie'}</span>
            {media.year && <span>{media.year}</span>}
            <span>Rating {media.rating || '—'}</span>
            {isTv && seasons && !flatEpisodes && seasons.length > 0 && (
              <span>
                {seasons.length} Season{seasons.length > 1 ? 's' : ''}
              </span>
            )}
          </div>
          <p className="details__overview">{media.overview}</p>
          <div className="details__actions">
            <button
              ref={play.ref}
              className={`header-btn${play.focused ? ' header-btn--focused' : ''}`}
              type="button"
            >
              ▶ Play
            </button>
            <button
              ref={watchLater.ref}
              className={`header-btn${watchLater.focused ? ' header-btn--focused' : ''}`}
              type="button"
            >
              + Watch Later
            </button>
          </div>
        </div>
      </div>

      {/* Series-only: sticky season bar + episode list below the hero. */}
      {isTv && (
        <section className="series">
          <div className="series__bar">
            <h2 className="series__heading">Episodes</h2>
            <div className="series__seasons">
              {seasons == null
                ? [0, 1, 2].map((i) => (
                    <div key={i} className="season-tab season-tab--skeleton" />
                  ))
                : seasons.map((s, i) => (
                    <SeasonTab
                      key={`${s.fid ?? 'flat'}-${i}`}
                      label={s.label}
                      active={i === activeIdx}
                      enabled={!playerOpen}
                      onSelect={() => setActiveIdx(i)}
                    />
                  ))}
            </div>
          </div>

          <div className="series__list">
            {seriesError ? (
              <p className="series__empty">{seriesError}</p>
            ) : episodes == null ? (
              [0, 1, 2, 3, 4].map((i) => (
                <div key={i} className="ep-row ep-row--skeleton" />
              ))
            ) : episodes.length === 0 ? (
              <p className="series__empty">No episodes found for this season.</p>
            ) : (
              episodes.map((ep, i) => (
                <EpisodeRow
                  key={ep.fid}
                  num={ep.episode ?? i + 1}
                  title={epTitle(ep, ep.episode ?? i + 1)}
                  fileName={ep.file_name}
                  resLabel={ep.resLabel}
                  enabled={!playerOpen}
                  onSelect={() => openEpisode(ep, i)}
                />
              ))
            )}
          </div>
        </section>
      )}

      {showPlayer && (
        <Player media={media} onClose={() => setShowPlayer(false)} />
      )}
      {episodePlay && (
        <Player
          media={media}
          startFid={episodePlay.fid}
          title={episodePlay.label}
          onClose={() => setEpisodePlay(null)}
        />
      )}
    </div>
  )
}

/* ---------- Series sub-components: season pill + episode row ---------- */
function SeasonTab({
  label,
  active,
  enabled,
  onSelect,
}: {
  label: string
  active: boolean
  enabled: boolean
  onSelect: () => void
}) {
  const { ref, focused } = useFocusable<HTMLButtonElement>({ onSelect, active: enabled })
  return (
    <button
      ref={ref}
      className={`season-tab${active ? ' season-tab--active' : ''}${
        focused ? ' season-tab--focused' : ''
      }`}
      type="button"
    >
      {label}
    </button>
  )
}

function EpisodeRow({
  num,
  title,
  fileName,
  resLabel,
  enabled,
  onSelect,
}: {
  num: number
  title: string
  fileName: string
  resLabel: string | null
  enabled: boolean
  onSelect: () => void
}) {
  const { ref, focused } = useFocusable<HTMLButtonElement>({ onSelect, active: enabled })
  return (
    <button
      ref={ref}
      className={`ep-row${focused ? ' ep-row--focused' : ''}`}
      type="button"
    >
      <span className="ep-row__num">{num}</span>
      <span className="ep-row__body">
        <span className="ep-row__title">{title}</span>
        <span className="ep-row__file">{fileName}</span>
      </span>
      {resLabel && <span className="ep-row__dur">{resLabel}</span>}
    </button>
  )
}
