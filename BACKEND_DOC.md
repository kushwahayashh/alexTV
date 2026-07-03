# AlexStream Backend

Node.js backend that bridges the Android TV app to TMDB (browse), ShowBox
(search/resolve), and FebBox (files/links/subtitles).

## Endpoints

| Method | Path | What it does |
|--------|------|--------------|
| GET | `/health` | Health check |
| GET | `/api/search?q=` | Search ShowBox for movies + TV |
| GET | `/api/resolve?title=&year=&type=` | Map a TMDB title to a ShowBox ID |
| GET | `/api/share-key?id=&type=` | Get a FebBox share key from a ShowBox ID |
| GET | `/api/files?shareKey=&parentId=` | List files in a FebBox share |
| GET | `/api/links?fid=` | Get stream quality links for a file |
| GET | `/api/subtitles?fid=` | List English subtitles for a file |
| GET | `/api/subtitle?url=` | Proxy + convert one subtitle SRT to WebVTT |
| GET | `/api/tmdb/*` | Proxy TMDB API (key injected server-side) |

## Typical Flow

```
TMDB browse → /api/search → /api/resolve → /api/share-key → /api/files → /api/links → /api/subtitles
```

User picks a title on TMDB, backend resolves it to a ShowBox ID, gets a FebBox
share key, lists files, fetches stream links, and pulls subtitles.

## Examples

```bash
# Search
curl "https://alexhasitbig--alexstream-serve.modal.run/api/search?q=inception"
# → {"results":[{"id":4059,"title":"Inception","year":2010,...}]}

# Resolve to ShowBox ID
curl "https://alexhasitbig--alexstream-serve.modal.run/api/resolve?title=Inception&year=2010&type=movie"
# → {"id":4059,"title":"Inception","year":2010}

# Get FebBox share key (type=1 movie, type=2 tv)
curl "https://alexhasitbig--alexstream-serve.modal.run/api/share-key?id=4059&type=1"
# → {"shareKey":"Bp1Hw1MK"}

# List files
curl "https://alexhasitbig--alexstream-serve.modal.run/api/files?shareKey=Bp1Hw1MK"
# → {"files":[...],"videoFiles":[{"fid":2605016,"file_name":"Inception.2010.1080p...mp4","resLabel":"1080p",...}]}
#    For TV shows, root returns season folders. Pass parentId=<folder fid> to drill in.

# Get stream links
curl "https://alexhasitbig--alexstream-serve.modal.run/api/links?fid=2605016"
# → {"links":[{"url":"...","quality":"1080p","proxiedUrl":"...",...}]}

# Get subtitles
curl "https://alexhasitbig--alexstream-serve.modal.run/api/subtitles?fid=2605016"
# → {"subtitles":[{"id":"1","lang":"eng","url":"/api/subtitle?url=..."}]}

# TMDB proxy (any TMDB v3 path works after /api/tmdb)
curl "https://alexhasitbig--alexstream-serve.modal.run/api/tmdb/trending/all/week"
```

## Files

| File | Purpose |
|------|---------|
| `server.js` | HTTP server, routing, ShowBox request signing, all endpoint logic |
| `config.js` | Loads `.env`, exports config for ShowBox/FebBox/TMDB |
| `fetch-utils.js` | fetch with timeout + retry |
| `subtitles.js` | FebBox subtitle scrape, English filter, SRT→VTT conversion |

## Env Variables

Copy `.env.example` to `.env`. Required: `SHOWBOX_IV`, `SHOWBOX_KEY`,
`FEBBOX_COOKIE`. Everything else has defaults.

## Run Locally

```bash
cd backend
npm install
cp .env.example .env   # fill in the three required vars
npm start              # or npm run dev for auto-restart
```

## Deploy (Modal)

```bash
modal deploy modal_app.py
```

Live URL: `https://alexhasitbig--alexstream-serve.modal.run`

## Notes

- ShowBox requests are TripleDES-encrypted + MD5-signed (mimics MovieBox app).
- FebBox is reached through a Cloudflare Worker proxy (`PROXY_BASE`).
- Empty results (`{"links":[]}`, etc.) usually mean the `FEBBOX_COOKIE` expired.
- All errors return `{"error": "..."}` with appropriate HTTP status.
