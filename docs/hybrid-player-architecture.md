Yes — this is a well-known pattern and it works well: **keep ExoPlayer's video surface 100% native (just the raw `SurfaceView`, no native UI at all), and build every control — play/pause button, seek bar, title cards, episode list, everything — in Flutter, floating on top.**

**How it works:**

1. **Native side (Kotlin)**: ExoPlayer instance wrapped in a `PlatformView` that exposes *just* the rendering surface. No buttons, no seekbar, no Compose UI at all — it's a dumb video canvas.
2. **Communication layer**:
   - `MethodChannel` — Flutter sends commands: `play()`, `pause()`, `seekTo(ms)`, `setTrack()`, `setSpeed()`, etc.
   - `EventChannel` — native streams state back continuously: playback position, buffering state, duration, isPlaying, errors. Flutter's UI (seekbar, loading spinner) just listens to this stream and redraws.
3. **Flutter side**: Full UI — your play/pause icon, scrubber, title/episode overlay, TV-style D-pad-navigable menu — all normal Flutter widgets, positioned in a `Stack` on top of the `PlatformView`.

**Why performance doesn't suffer**: The decode → render path is untouched — ExoPlayer still writes straight to its `SurfaceView`, same as pure native. Flutter isn't touching pixels of the video at all; it's just compositing a transparent UI layer above it. That compositing is cheap (it's just normal Flutter widget rendering, same cost as any other overlay UI).

**The one real gotcha — you asked for TV, so this matters**: Use **Hybrid Composition** (or the newer default Texture Layer Hybrid Composition in current Flutter) for the `PlatformView`. On older texture-based platform views, overlaying interactive Flutter widgets on top used to have z-order/input issues. Modern Flutter (3.x+) handles this correctly.

The trickier part specific to TV: **D-pad focus routing**. When you have a native `SurfaceView` underneath and Flutter widgets on top, you need to make sure remote key events go to Flutter's focus system for your controls, not get swallowed by the native view. Practically this means:
- Native view should not be focusable itself (`focusable = false` on the native surface)
- Flutter's `FocusNode`/`FocusTraversalGroup` handles all D-pad navigation for your controls
- Any native-only interaction (rare, since you're doing UI in Flutter) would need explicit MethodChannel bridging back for focus state

This is genuinely the standard architecture for hybrid Flutter TV players (Netflix, JioCinema-style apps built this way describe roughly this setup) — native decode/render, Flutter chrome. Want me to sketch out the actual Kotlin `PlatformView` class + the Flutter-side widget wiring (MethodChannel/EventChannel boilerplate) to get you started?