import { useEffect, useState } from 'react'
import { useFocusable } from '../focus/FocusEngine'
import { IMG, type Media } from '../api/tmdb'
import { FadeImage } from '../components/FadeImage'
import { Player } from '../components/Player'

/**
 * Fullscreen movie/series details page. Mirrors the hero aesthetic (backdrop,
 * scrim, left-aligned content) and adds Play + Watch Later action buttons
 * styled like the navbar pills. Focus seeds on the Play button on mount so
 * the user can immediately press Enter to play.
 */
export function Details({ media }: { media: Media }) {
  const [showPlayer, setShowPlayer] = useState(false)
  const play = useFocusable({
    onSelect: () => setShowPlayer(true),
    active: !showPlayer,
  })
  const watchLater = useFocusable({
    onSelect: () => console.log('WATCH LATER', media.title),
    active: !showPlayer,
  })

  useEffect(() => {
    play.focusSelf()
  }, [showPlayer])

  return (
    <div className="details">
      <div className="details__hero">
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
            <span>{media.mediaType === 'tv' ? 'Series' : 'Movie'}</span>
            {media.year && <span>{media.year}</span>}
            <span>★ {media.rating || '—'}</span>
          </div>
          <p className="details__overview">{media.overview}</p>
          <div className="details__actions">
            <button
              ref={play.ref as React.RefObject<HTMLButtonElement>}
              className={`header-btn${play.focused ? ' header-btn--focused' : ''}`}
              type="button"
            >
              Play
            </button>
            <button
              ref={watchLater.ref as React.RefObject<HTMLButtonElement>}
              className={`header-btn${watchLater.focused ? ' header-btn--focused' : ''}`}
              type="button"
            >
              Watch Later
            </button>
          </div>
        </div>
      </div>
      {showPlayer && (
        <Player media={media} onClose={() => setShowPlayer(false)} />
      )}
    </div>
  )
}
