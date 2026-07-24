# AlexTV (Android TV)

Flutter port of the AlexTV web prototype. A D-pad-navigable Android TV
streaming app that browses TMDB and plays movies through the AlexStream
backend, with native ExoPlayer hardware decoding and self-update from GitHub
releases.

## Stack

- Flutter (stable, currently 3.44.x)
- `http` for backend + TMDB calls
- `google_fonts` (Space Grotesk, app-wide)
- `video_player` with a vendored `video_player_android` patch
- `path_provider` + `open_filex` for APK self-update
- Native platform view (`SurfaceView`) wrapping ExoPlayer

## Project layout

```
lib/
  main.dart                       # App entry, DesignScaler, AppShell routing
  theme.dart                      # AppColors, AppSizes (design width, paddings)
  surface_video_player.dart       # Native ExoPlayer SurfaceView controller
  api/
    tmdb.dart                     # TMDB data layer (rails, hero, Media model)
    stream.dart                   # Stream API client (resolve → files → links)
  components/
    hero.dart                     # Auto-rotating cinematic hero + Scrim/FadeIn
    poster_card.dart              # Poster card with focus lift
    rail.dart                     # Horizontal scrolling rail of cards
    player.dart                   # Three-step playback modal (files → links → player)
    video_player_screen.dart      # Fullscreen player with custom TV controls
    header_button.dart            # Pill-shaped nav button
    update_button.dart            # Update button that triggers self-update
    fade_image.dart               # Image with fade-in via frameBuilder
  screens/
    home.dart                     # Hero + rails layout
    details.dart                  # Fullscreen details with Play / Watch Later
  focus/
    focus_engine.dart             # Spatial D-pad focus engine (Dart port)
  update/
    updater.dart                  # Download latest APK + hand to installer
plugins/
  video_player_android/             # Vendored plugin (Java) with ExoPlayer decoder fallback
android/app/src/main/kotlin/com/example/alextv/
  MainActivity.kt                   # Registers the SurfaceVideoPlayer platform view
  surfaceplayer/
    SurfaceVideoPlayerFactory.kt    # PlatformView factory (SurfaceView + ExoPlayer)
    SurfaceVideoPlayer.kt           # ExoPlayer wrapper, method channel
```

## Design scaler

TVs report a narrow logical canvas at a high device-pixel-ratio, which makes
a fixed-size UI render zoomed in. `_DesignScaler` in `main.dart` lays the app
out at a fixed `designWidth` and uses `FittedBox` to uniformly scale it to
fill the real screen. A matching `MediaQuery` is injected so height-relative
layout (e.g. the hero) stays correct. The web prototype sees the same canvas
in a wide browser dev window, so both look identical.

## Focus engine

`focus/focus_engine.dart` is a 1:1 Dart port of the React `FocusEngine.tsx`.
Every focusable registers a `GlobalKey`. On an arrow key the engine reads
the live `RenderBox` rect of each registered node and picks the best
candidate in the pressed direction using the same distance + alignment cost
(weighted so straight-line neighbours win).

- Arrows move focus spatially.
- Enter / Space / Select triggers `onSelect`.
- Escape / Backspace / GoBack triggers `onBack`.
- The seekbar intercepts left/right when focused so it seeks instead of
  moving focus away.
- Header buttons (Home, Search, Library, Update) are reached by pressing Up
  from the hero, then traversed left/right.

## Player flow

`components/player.dart` runs the same three-step chain as the web app:

1. **Resolve** — `resolveMovie(title, year)` calls the backend
   `/api/resolve` → `/api/share-key` → `/api/files` chain.
2. **File picker** — lists the returned `VideoFile[]`.
3. **Quality picker** — fetches `StreamLink[]` via `/api/links?fid=`.
4. **Play** — the `proxiedUrl` is handed to `VideoPlayerScreen`, which mounts
   the native `SurfaceVideoPlayerController` view.

Back steps back (links → files) or closes the player.

## Native ExoPlayer

`surface_video_player.dart` registers a platform view
(`com.example.alextv/surface_video_player`) backed by ExoPlayer rendering to
a `SurfaceView` (not `TextureView`). On Android TV, hardware decoders may
fail when rendering to a `SurfaceTexture` (Flutter's default); `SurfaceView`
renders directly to the display, bypassing the extra GPU composition pass
that causes the failure.

The vendored `plugins/video_player_android/` patches the upstream plugin to
enable ExoPlayer's decoder fallback so TV hardware codec issues don't kill
playback. It's pulled in via `dependency_overrides` in `pubspec.yaml` and
excluded from `flutter analyze` via the `plugins**` glob in
`analysis_options.yaml`.

The player UI (`video_player_screen.dart`) overlays a custom TV control set:

- Top bar: video title.
- Bottom bar: focusable seekbar (left/right seeks ±10s when focused),
  Play/Pause pill (left), Subtitles + Audio pills (right, mock).

## Self-update

`update/updater.dart` downloads the latest `alexTV.apk` from the rolling
GitHub release, writes it to a fixed path in app storage (overwriting any
previous download so stale APKs don't pile up), and hands it to the system
package installer via `open_filex`. The Update button in the header triggers
this.

## CI

`.github/workflows/android-build.yml` builds a release APK on every push to
`main`/`master` and on PRs. The APK is published to a single rolling GitHub
Release (`latest` tag) so the self-updater always pulls the newest build.
Java 17 + Flutter 3.44.4, with Gradle and Flutter SDK caching for faster
repeat builds.

## Backend

The app talks to the AlexStream backend (see `../BACKEND_DOC.md`) at
`https://alexhasitbig--alexstream-serve.modal.run`. Endpoints used:

- `/api/resolve` — title + year → ShowBox ID
- `/api/share-key` — ShowBox ID → FebBox share key
- `/api/files` — share key → video file list
- `/api/links` — file ID → stream links (with proxied URLs)

TMDB is called through the Cloudflare Worker proxy (the same one the web app
uses). The API key is currently inline in `lib/api/tmdb.dart` — fine for a
local prototype, should move server-side / into secure storage for
production.

## Develop

```bash
flutter pub get
flutter analyze
flutter run                 # debug on a connected TV / emulator
flutter build apk --release # release APK → build/app/outputs/flutter-apk/
```

## Notes

- The Flutter app and the React web prototype share the same UI, the same
  focus engine, and the same data layer. See `../README.md`.
- Movie-only for now; TV show resolution (seasons / episodes) is not wired
  up yet.
