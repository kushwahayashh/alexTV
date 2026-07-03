import { useFocusable } from '../focus/FocusEngine'
import { IMG, type Media } from '../api/tmdb'

export function PosterCard({
  media,
  onSelect,
}: {
  media: Media
  onSelect: (m: Media) => void
}) {
  const { ref, focused } = useFocusable({
    onSelect: () => onSelect(media),
  })

  return (
    <div
      ref={ref}
      className={`poster${focused ? ' poster--focused' : ''}`}
    >
      {media.posterPath ? (
        <img className="poster__img" src={IMG.poster(media.posterPath)} alt={media.title} loading="lazy" />
      ) : (
        <div className="poster__placeholder">{media.title}</div>
      )}
    </div>
  )
}
