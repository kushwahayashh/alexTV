# AlexStream

Search and stream movies & TV from ShowBox/FebBox. A small Node.js backend
bridges a TMDB-powered browse UI to playable streams, and an Android TV app
wraps that UI in a native shell with an ExoPlayer video player.

## Layout

```
.
├── backend/               # Node.js streaming backend
│   ├── server.js          # HTTP server + /api/* endpoints (no framework)
│   ├── config.js          # loads secrets from .env (ShowBox keys, FebBox cookie, proxy)
│   ├── fetch-utils.js     # fetch with timeout + retry
│   ├── subtitles.js       # FebBox subtitle scrape + SRT→VTT conversion
└── android/               # Android TV app (bundled web UI, native ExoPlayer)
    └── app/src/main/assets/ # vanilla ES module web UI bundled in the APK
```

## How it works

Browse/discovery data comes from **TMDB**, fetched client-side and cached.
Streaming is separate: a TMDB title is bridged to a **ShowBox** id at click
time (`/api/resolve`), then a share-key → files → links chain through
**FebBox** produces playable stream URLs. Subtitles are pulled from FebBox for
the exact file being played.

ShowBox requests are signed the way the MovieBox Android app does it
(Triple-DES + MD5 verify); FebBox is reached through a Cloudflare Worker proxy.

### API endpoints

| Endpoint | Purpose |
|---|---|
| `GET /api/search?q=` | Search ShowBox for movies + TV |
| `GET /api/resolve?title=&year=&type=` | Map a TMDB title to a ShowBox id |
| `GET /api/share-key?id=&type=` | Get a FebBox share key for a ShowBox id |
| `GET /api/files?shareKey=&parentId=` | List files/folders in a share |
| `GET /api/links?fid=` | Get quality/stream links for a file |
| `GET /api/subtitles?fid=` | List English subtitles for a file |
| `GET /api/subtitle?url=` | Proxy + convert one subtitle to WebVTT |

## Running the backend

Requires Node.js (≥ 20.6 for native `.env` loading via `process.loadEnvFile`).

```bash
cd backend
npm install
cp .env.example .env     # then fill in the values (see below)
npm start                # or: npm run dev  (auto-restart on change)
```

Server listens on `http://localhost:3000` (override with `PORT`).

### Environment variables (`.env`)

| Variable | Required | Notes |
|---|---|---|
| `SHOWBOX_IV` | yes | Triple-DES IV for request signing |
| `SHOWBOX_KEY` | yes | Triple-DES key for request signing |
| `FEBBOX_COOKIE` | yes | `ui` cookie value for FebBox |
| `SHOWBOX_BASE_URL` | no | defaults to the MovieBox mobile API |
| `SHOWBOX_APP_KEY` | no | defaults to `moviebox` |
| `FEBBOX_BASE_URL` | no | defaults to `https://www.febbox.com` |
| `PROXY_BASE` | no | Cloudflare Worker proxy base |
| `PORT` | no | defaults to `3000` |

`.env` is gitignored; never commit real secrets.

## Android TV app

`android/` is a native Android TV app that bundles the web UI in the APK.
The bundled JavaScript fetches `/api/*` and TMDB data from the hosted backend,
while Kotlin owns backend URL configuration, native ExoPlayer playback, and
subtitle fetching for the native player.

It talks to a hosted instance of this backend — set the backend URL in
`android/app/src/main/java/com/alexstream/tv/BackendConfig.kt`, then build:

```bash
cd android
./gradlew assembleDebug
```

See `android/README.md` for the full build/install/architecture details.

## Disclaimer

For personal and educational use. You are responsible for complying with the
terms of service of any third-party sources and with applicable law.
