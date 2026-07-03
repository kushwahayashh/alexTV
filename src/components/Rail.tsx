import { PosterCard } from './PosterCard'
import type { Media, Rail as RailData } from '../api/tmdb'

export function Rail({
  rail,
  onSelect,
}: {
  rail: RailData
  onSelect: (m: Media) => void
}) {
  return (
    <section className="rail">
      <h2 className="rail__title">{rail.title}</h2>
      <div className="rail__track">
        {rail.items.map((media) => (
          <PosterCard
            key={`${media.mediaType}-${media.id}`}
            media={media}
            onSelect={onSelect}
          />
        ))}
      </div>
    </section>
  )
}
