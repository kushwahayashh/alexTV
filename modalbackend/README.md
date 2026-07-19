# AlexTV Library backend

FastAPI app (deployed on Modal) that serves the media library the AlexTV
**Library** screen browses, plus a web terminal for managing the volume. It's a
trimmed cousin of `Movieapp/backend` — the Library pieces (browse the tree,
stream files with HTTP Range) and the xterm.js terminal, without the
file-manager SPA or mkdir/rename/delete routes.

Not wired into the app yet — the Library still reads mock data from
`src/api/library.ts`. This is the real thing it will point at.

## Fast tunnel + discovery

Modal's `web_server` ingress (the `...modal.run` URL you get from `modal
deploy`) buffers responses, which is poor for video streaming. So on startup the
container opens a Modal **fast tunnel** — a direct, low-latency path — and
publishes its URL from the discovery endpoints.

Clients use two steps, same as `Movieapp/backend`:

1. `GET https://<app>.modal.run/` (or `/start`) → `{"url": "<fast-tunnel base>"}`
2. Do all listing/streaming/terminal against that fast-tunnel base URL.

If you hit `/` right after deploy and get `503 Tunnel not ready yet`, wait a
second and retry — the tunnel takes a moment to come up.

## Endpoints

| Method | Path | What it does |
|--------|------|--------------|
| GET | `/` or `/start` | `{"url": "<fast-tunnel base>", "terminal_url": ...}` — call first |
| GET | `/health` | `{"ok": true}` |
| GET | `/list?path=/` | List one level of the tree (folders first, then files) |
| GET | `/stream?path=/f.mkv` | Stream a file; honours `Range` for seeking (206) |
| GET | `/download-url?path=` | `{"url": ".../stream?path=..."}` for the player |
| GET | `/terminal` | xterm.js web terminal UI |
| WS | `/ws/terminal` | PTY-backed `bash` shell, opened in `/vol/media` |

### `/list` response

```jsonc
{
  "path": "/",
  "parentPath": null,                 // null at the root
  "items": [
    { "type": "folder", "name": "Breaking Bad", "path": "/Breaking Bad",
      "size": null, "sizeFormatted": null, "mtime": 1784..., "itemCount": 2 },
    { "type": "file", "name": "Inception (2010) 1080p BluRay.mkv",
      "path": "/Inception (2010) 1080p BluRay.mkv",
      "size": 5000, "sizeFormatted": "4.88 KB", "mtime": 1784...,
      "resolution": "1080p" }              // parsed from the file name
  ]
}
```

This maps cleanly onto the Library's `LibraryItem` shape: folders → drill-in
rows (`itemCount` → "N episodes" badge), files → play rows (`sizeFormatted` and
`resolution` → the badges).

## Behaviour

- Root is `/vol/media` on the Modal volume — the Library never sees the rest of
  the volume.
- Only media extensions are listed (`.mkv .mp4 .avi .mov .ts .flv .webm .m4v`
  plus common audio); dotfiles and everything else are hidden.
- Folders sort A→Z, files newest-first (mirrors the reference backend). Note:
  for series folders this shows episodes newest-first — switch the sort key in
  `list_items` to `e.name.lower()` if you want strict episode order.
- Resolution badge is parsed from the file name (`4K/1440p/1080p/720p/480p`),
  so there's no per-file `ffprobe` cost. `null` when it can't tell.
- Every client path is resolved against the media root and anything escaping it
  (`../..`) is rejected with `400`.

## Terminal

`/terminal` serves an xterm.js UI that talks to `/ws/terminal`, a PTY-backed
`bash` opened in the media folder. Handy for uploading, renaming, or running
`ffmpeg`/`yt-dlp`/`aria2` against the volume without a file-manager UI. xterm.js
assets are loaded from a CDN.

There is **no auth** on the terminal — it's a full shell on the volume. Fine for
a private prototype behind an obscure Modal URL; put it behind auth (or drop the
routes) before exposing this anywhere real.

## Files

| File | Purpose |
|------|---------|
| `app.py` | The app: path helpers, Range streaming, routes, Modal deploy |
| `terminal.py` | PTY-over-WebSocket shell + `/terminal` HTML route |
| `terminal.html` | xterm.js frontend (loads xterm.js from a CDN) |

## Deploy (Modal)

```bash
pip install modal
modal deploy app.py
```

Uses the `alextv-library` volume mounted at `/vol`, serving `/vol/media`.
One always-on container (`min_containers=1`) so streaming stays warm.
