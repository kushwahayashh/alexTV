# AlexTV (Web)

React + TypeScript + Vite prototype of the AlexTV UI. A D-pad-navigable,
TV-style streaming front-end that browses TMDB and plays movies through the
AlexStream backend.

## Stack

- React 18 + TypeScript
- Vite 5 (dev server + build)
- hls.js for HLS playback in the `<video>` element
- Cloudflare Worker proxy for TMDB + FebBox fetches (CORS bypass)

## Project layout

```
src/
  App.tsx              # Root: routes between Home and Details
  main.tsx             # Vite entry
  styles.css           # All styling (no CSS-in-JS, no Tailwind)
  api/
    tmdb.ts            # TMDB data layer (rails, hero, normalize)
    stream.ts          # Stream API client (resolve → files → links)
  components/
    Hero.tsx           # Auto-rotating cinematic hero
    PosterCard.tsx     # Poster card with focus lift
    Rail.tsx           # Horizontal scrolling rail of cards
    Player.tsx         # Three-step playback modal + video player
    HeaderButton.tsx   # Pill-shaped nav button
    FadeImage.tsx      # Image with fade-in on load
  screens/
    Home.tsx           # Hero + rails layout
    Details.tsx        # Fullscreen details with Play / Watch Later
  focus/
    FocusEngine.tsx    # Spatial D-pad focus engine (arrow keys + Enter)
```

## Focus engine

`FocusEngine.tsx` implements a spatial D-pad focus system, not DOM tab order.
Every focusable registers its DOM rect. On an arrow key the engine picks the
nearest neighbour in the pressed direction using a distance + alignment cost
(weighted so straight-line neighbours win). This is what makes the UI feel
like a real TV launcher and is the basis for the Flutter port.

- Arrow keys move focus spatially.
- Enter / Space / Select triggers `onSelect`.
- Escape / Backspace triggers `onBack` (exits Details back to Home).
- The seekbar intercepts left/right when focused so it seeks instead of
  moving focus away.

## Player flow

The `Player` component runs a three-step chain (movie-only for now):

1. **Resolve** — `resolveMovie(title, year)` calls the backend
   `/api/resolve` → `/api/share-key` → `/api/files` chain.
2. **File picker** — lists the returned `VideoFile[]` (file name, resolution,
   size). User picks one.
3. **Quality picker** — fetches `StreamLink[]` via `/api/links?fid=`. User
   picks a quality.
4. **Play** — the `proxiedUrl` is handed to `<video>`. HLS streams use
   `hls.js` (Chrome/Firefox); Safari uses native HLS; mp4 plays directly.

Escape steps back (links → files) or closes the player.

## TMDB rails

`fetchHomeRails()` pulls five rails in parallel:

- Trending This Week
- Popular Movies
- Top Rated
- Popular Series
- Coming Soon

The hero auto-rotates through the first 10 trending titles that have a
backdrop, every 10 seconds.

## Backend

The web app talks to the AlexStream backend (see `BACKEND_DOC.md`) at
`https://alexhasitbig--alexstream-serve.modal.run`. Endpoints used:

- `/api/resolve` — title + year → ShowBox ID
- `/api/share-key` — ShowBox ID → FebBox share key
- `/api/files` — share key → video file list
- `/api/links` — file ID → stream links (with proxied URLs)

TMDB is called browser-side through the Cloudflare Worker proxy
(`worker.js` in this repo, deployed at
`lunaissohot.lunastar0003.workers.dev`). The API key is currently inline in
`src/api/tmdb.ts` — fine for a local prototype, should move server-side for
production.

## Develop

```bash
npm install
npm run dev      # Vite dev server (host: true so TV can reach it)
npm run build    # tsc + vite build → dist/
npm run preview  # serve the built dist/
```

## Notes

- The web prototype and the Flutter Android TV app share the same UI, the
  same focus engine, and the same data layer. See `flutter/README.md`.
- The Cloudflare Worker (`worker.js`) is a separate deployment. It streams
  responses with Range support so seeking works, and only allows known
  FebBox / shegu hosts.
