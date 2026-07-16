/**
 * TMDB data layer. Read-only, browser-side fetch with the v3 API key.
 * Note: for the Flutter port the key should move server-side / into secure
 * storage — fine to keep inline for this local prototype.
 */

const API_KEY = '8bd45cfb804f84ce85fa6accd833d6a1'
const BASE = 'https://api.themoviedb.org/3'
const PROXY = 'https://lunaissohot.lunastar0003.workers.dev/?destination='

export const IMG = {
  poster: (path: string | null) =>
    path ? `https://image.tmdb.org/t/p/w342${path}` : '',
  backdrop: (path: string | null) =>
    path ? `https://image.tmdb.org/t/p/original${path}` : '',
}

export type Media = {
  id: number
  title: string
  posterPath: string | null
  backdropPath: string | null
  overview: string
  rating: number
  year: string
  mediaType: 'movie' | 'tv'
}

type TmdbItem = {
  id: number
  title?: string
  name?: string
  poster_path: string | null
  backdrop_path: string | null
  overview: string
  vote_average: number
  release_date?: string
  first_air_date?: string
  media_type?: string
}

function normalize(item: TmdbItem, fallbackType: 'movie' | 'tv'): Media {
  const date = item.release_date || item.first_air_date || ''
  const type = (item.media_type === 'tv' || item.media_type === 'movie'
    ? item.media_type
    : fallbackType) as 'movie' | 'tv'
  return {
    id: item.id,
    title: item.title || item.name || 'Untitled',
    posterPath: item.poster_path,
    backdropPath: item.backdrop_path,
    overview: item.overview,
    rating: Math.round(item.vote_average * 10) / 10,
    year: date ? date.slice(0, 4) : '',
    mediaType: type,
  }
}

async function get(path: string): Promise<TmdbItem[]> {
  const sep = path.includes('?') ? '&' : '?'
  const targetUrl = `${BASE}${path}${sep}api_key=${API_KEY}`
  const proxiedUrl = `${PROXY}${encodeURIComponent(targetUrl)}`
  const res = await fetch(proxiedUrl)
  if (!res.ok) throw new Error(`TMDB ${res.status} on ${path}`)
  const json = await res.json()
  return json.results ?? []
}

/**
 * TMDB multi-search — the search box data source. Mirrors the reference impl:
 * hit /search/multi, drop `person` results and anything without a poster, and
 * normalize to the shared Media shape so results reuse PosterCard / Details.
 * media_type is present on multi-search rows, so normalize keys off it (the
 * 'movie' fallback only applies to the rare row missing the field).
 */
export async function searchMulti(query: string): Promise<Media[]> {
  const q = query.trim()
  if (!q) return []
  const items = await get(
    `/search/multi?query=${encodeURIComponent(q)}&include_adult=false`,
  )
  return items
    .filter(
      (i) =>
        (i.media_type === 'movie' || i.media_type === 'tv') && i.poster_path,
    )
    .map((i) => normalize(i, 'movie'))
}

export type Rail = { title: string; items: Media[] }

export async function fetchHomeRails(): Promise<Rail[]> {
  const [trending, popularMovies, topRated, popularTv, upcoming] =
    await Promise.all([
      get('/trending/all/week'),
      get('/movie/popular'),
      get('/movie/top_rated'),
      get('/tv/popular'),
      get('/movie/upcoming'),
    ])

  return [
    { title: 'Trending This Week', items: trending.map((i) => normalize(i, 'movie')) },
    { title: 'Popular Movies', items: popularMovies.map((i) => normalize(i, 'movie')) },
    { title: 'Top Rated', items: topRated.map((i) => normalize(i, 'movie')) },
    { title: 'Popular Series', items: popularTv.map((i) => normalize(i, 'tv')) },
    { title: 'Coming Soon', items: upcoming.map((i) => normalize(i, 'movie')) },
  ]
}
