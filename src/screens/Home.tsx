import { useEffect, useState } from 'react'
import { fetchHomeRails, type Media, type Rail as RailData } from '../api/tmdb'
import { Hero } from '../components/Hero'
import { Rail } from '../components/Rail'
import { HeaderButton } from '../components/HeaderButton'
import { Spinner } from '../components/Spinner'

const HERO_ROTATE_MS = 10000

export function Home({
  onSelect,
  onOpenSearch,
  onOpenLibrary,
}: {
  onSelect: (m: Media) => void
  onOpenSearch: () => void
  onOpenLibrary: () => void
}) {
  const [rails, setRails] = useState<RailData[]>([])
  const [featured, setFeatured] = useState<Media[]>([])
  const [heroIndex, setHeroIndex] = useState(0)
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading')

  useEffect(() => {
    let alive = true
    fetchHomeRails()
      .then((data) => {
        if (!alive) return
        setRails(data)
        // Feature the trending items that actually have a backdrop to show.
        setFeatured(
          (data[0]?.items ?? []).filter((m) => m.backdropPath).slice(0, 10),
        )
        setStatus('ready')
      })
      .catch((err) => {
        console.error(err)
        if (alive) setStatus('error')
      })
    return () => {
      alive = false
    }
  }, [])

  // Hero cycles on its own, independent of card focus.
  useEffect(() => {
    if (featured.length < 2) return
    const timer = setInterval(() => {
      setHeroIndex((i) => (i + 1) % featured.length)
    }, HERO_ROTATE_MS)
    return () => clearInterval(timer)
  }, [featured])

  if (status === 'loading') {
    return (
      <div className="screen-msg screen-msg--loader">
        <Spinner />
      </div>
    )
  }
  if (status === 'error') {
    return <div className="screen-msg">Failed to load. Check the network / API key.</div>
  }

  return (
    <div className="home">
      <div className="home__hero-wrap">
        <Hero media={featured[heroIndex] ?? null} />
        <div className="home__header home__header--left">
          <HeaderButton label="Home" />
          <HeaderButton label="Search" onSelect={onOpenSearch} />
          <HeaderButton label="Library" onSelect={onOpenLibrary} />
        </div>
        <div className="home__header home__header--right">
          <HeaderButton label="Update" />
        </div>
      </div>
      <div className="home__rails">
        {rails.map((rail) => (
          <Rail
            key={rail.title}
            rail={rail}
            onSelect={onSelect}
          />
        ))}
      </div>
    </div>
  )
}
