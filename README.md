# AlexTV

A TV-style streaming launcher for Android TV and the web — browse TMDB, resolve
titles to streamable sources via a custom backend, and play them with a
D-pad-navigable UI.

## What it does

- **Content discovery** — five TMDB rails (Trending, Popular, Top Rated, TV
  Series, Coming Soon) plus a cinematic auto-rotating hero
- **Debounced search** — TMDB multi-search with poster grid
- **Streaming resolution** — resolves any TMDB title through ShowBox → FebBox,
  fetches video files with quality picker, and plays via HLS
- **TV series support** — season folder navigation, episode deduplication,
  season tab bar
- **Personal media library** — browse and play files from a cloud media volume
  with breadcrumb navigation and watch-progress tracking with resume
- **Self-update** — Flutter app downloads the latest APK from GitHub Releases
  and hands off to the system installer

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  React Web App (/)          Flutter Android TV App  │
│  Vite + TypeScript          Dart + ExoPlayer        │
│  D-pad spatial focus        D-pad spatial focus     │
├─────────────────────────────────────────────────────┤
│  Cloudflare Worker  ──  TMDB proxy + FebBox CORS   │
│  AlexStream backend ──  ShowBox / FebBox resolver   │
│  AlexTV Library     ──  Media volume browser/player │
└─────────────────────────────────────────────────────┘
```

Three frontends share the same UI, focus engine, and data layer:
- **React web app** (`/`) — browser prototype, ports to TV via Vite `host:true`
- **Flutter Android TV app** (`flutter/`) — native Android TV with ExoPlayer
- **Player UI prototype** (`player-ui/`) — standalone player controls sandbox

Two backend services:
- **AlexStream** (Node.js, deployed on Modal) — ShowBox integration:
  resolve → share-key → files → stream links
- **AlexTV Library** (`modalbackend/`) — FastAPI on Modal: browse and stream a
  personal media volume, plus an xterm.js terminal for management

One proxy:
- **Cloudflare Worker** (`worker.js`) — TMDB API proxy with CORS, FebBox
  stream URL rewriting with Range support for seeking

## Project layout

```
src/                          # React web app
  App.tsx                     # Root: sidebar + screen routing
  styles.css                  # All styling (~26 KB, no CSS framework)
  api/
    tmdb.ts                   # TMDB data layer (rails, search, normalize)
    stream.ts                 # Stream resolution chain (resolve → files → links)
    library.ts                # Library backend client
    series.ts                 # Series helpers: season parsing, episode dedup
  components/
    Hero.tsx                  # Auto-rotating cinematic hero (10 s interval)
    PosterCard.tsx            # Poster card with focus lift animation
    Rail.tsx                  # Horizontal scrolling rail of poster cards
    Player.tsx                # Three-step modal: file picker → quality → video
    Sidebar.tsx               # Netflix-style collapsible left sidebar
    HeaderButton.tsx          # Pill-shaped nav/sort button
    FadeImage.tsx             # Image with fade-in on load
    Spinner.tsx               # Apple-style loading spinner
    icons.tsx                 # Inline SVG sidebar icons
  screens/
    Home.tsx                  # Hero + content rails
    Details.tsx               # Fullscreen details + Play + season picker
    Search.tsx                # Debounced TMDB multi-search (350 ms)
    Library.tsx               # File-manager library browser with breadcrumbs
  focus/
    FocusEngine.tsx           # Spatial D-pad focus engine

flutter/                      # Flutter Android TV app
  lib/
    main.dart                 # App entry, design scaler, route helpers
    routes.dart               # Shared page transitions + push-guard
    theme.dart                # Design tokens (colors, sizes)
    api/                      # Mirrors React api/: tmdb, stream, library, series
    components/               # Mirrors React components: hero, cards, player, sidebar
    screens/                  # Mirrors React screens: home, details, search, library
    focus/                    # Focus engine Dart port + FocusableState mixin
    update/                   # Self-updater (download APK → system installer)
  android/app/src/main/kotlin/com/example/alextv/
    MainActivity.kt           # Registers platform views
    PlayerActivity.kt         # Native ExoPlayer activity
    PlaybackProgressStore.kt  # Watch-progress persistence
    surfaceplayer/            # SurfaceView + ExoPlayer platform view
  plugins/video_player_android/  # Vendored plugin with ExoPlayer decoder fallback

player-ui/                    # Standalone player controls prototype (port 5174)

modalbackend/                 # Library backend (FastAPI on Modal)
  app.py                      # API: browse, stream, PTY shell
  terminal.py                 # PTY-over-WebSocket for xterm.js
  terminal.html               # xterm.js frontend

worker.js                     # Cloudflare Worker: TMDB + FebBox proxy

docs/
  hybrid-player-architecture.md  # Native decode + Flutter chrome notes

.github/workflows/
  android-build.yml           # CI: builds Flutter APK → rolling GitHub Release
```

## Focus engine

Both React and Flutter use a **spatial D-pad focus system** (not DOM tab order
or Flutter's built-in focus). Each focusable registers its bounding rect, and
arrow keys pick the nearest neighbour using distance + alignment cost weighting.
This is what makes the UI feel like a real TV launcher.

- Arrow keys move focus spatially
- Enter / Select triggers `onSelect`
- Back / Escape triggers `onBack` to the previous screen
- Holding an arrow key on the seekbar ramps seek speed
- Controls auto-hide after 4 s of inactivity

## Stream resolution chain

1. **Resolve** — TMDB title + year → ShowBox ID (`/api/resolve`)
2. **Share key** — ShowBox ID → FebBox share key (`/api/share-key`)
3. **Files** — share key → video file list with name, resolution, size
   (`/api/files`; for series: `/api/files?tv_key=...`)
4. **Links** — file ID → stream links with proxy URLs (`/api/links`)
5. **Play** — HLS goes through `hls.js` (web) or native ExoPlayer (Flutter);
   mp4 plays directly

## Develop

### Web app

```bash
npm install
npm run dev      # Vite dev server (host: true so TV can reach it)
npm run build    # tsc + vite build → dist/
npm run preview  # Serve the built dist/
```

### Flutter Android TV app

```bash
cd flutter
flutter pub get
flutter analyze
flutter run                    # Debug on connected TV / emulator
flutter build apk --release    # Release APK
```

### Player UI sandbox

```bash
cd player-ui
npm install
npm run dev      # Runs on port 5174
```

### Library backend

```bash
cd modalbackend
pip install modal
modal deploy app.py
```

Requires a Modal volume (`vibe-media`) mounted at `/vol` with media under
`/vol/media`.

## Backend endpoints

| Service | URL |
|---|---|
| AlexStream | `https://alexhasitbig--alexstream-serve.modal.run` |
| AlexTV Library | `https://alexhasitbig--alextv-library-start.modal.run` |
| Cloudflare Worker | `https://lunaissohot.lunastar0003.workers.dev` |

The TMDB API key is inline in `src/api/tmdb.ts` (fine for a local prototype;
should move server-side for production).

## CI/CD

GitHub Actions (`.github/workflows/android-build.yml`) triggers on pushes to
`main` and PRs — builds the Flutter release APK and publishes it to a rolling
GitHub Release (tag `latest`). The Flutter app's self-updater fetches from this
release.
