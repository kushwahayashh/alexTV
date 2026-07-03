import { IMG, type Media } from '../api/tmdb'

/** Cinematic hero that auto-rotates through featured titles on its own. */
export function Hero({ media }: { media: Media | null }) {
  if (!media) return <div className="hero hero--empty" />

  return (
    <div className="hero">
      {media.backdropPath && (
        // key forces a remount per title so the fade-in animation replays.
        <img
          key={media.id}
          className="hero__bg"
          src={IMG.backdrop(media.backdropPath)}
          alt=""
        />
      )}
      <div className="hero__scrim" />
      <div key={`c-${media.id}`} className="hero__content">
        <h1 className="hero__title">{media.title}</h1>
        <div className="hero__facts">
          <span>{media.mediaType === 'tv' ? 'Series' : 'Movie'}</span>
          {media.year && <span>{media.year}</span>}
          <span>★ {media.rating || '—'}</span>
        </div>
        <p className="hero__overview">{media.overview}</p>
      </div>
    </div>
  )
}
