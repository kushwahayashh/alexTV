import { useFocusable } from '../focus/FocusEngine'
import { FadeImage } from './FadeImage'
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
        <FadeImage className="poster__img" src={IMG.poster(media.posterPath)} alt="" loading="lazy" />
      ) : (
        <div className="poster__placeholder" />
      )}
    </div>
  )
}
