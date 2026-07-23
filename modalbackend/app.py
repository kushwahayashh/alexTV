"""
AlexTV Library backend.

A small FastAPI app, deployed on Modal, that serves the media library the
AlexTV Library screen browses. Modelled on Movieapp/backend but trimmed to just
what the Library needs: browse the folder tree, stream a file with HTTP Range
support, and hand out a direct stream URL.

Layout on Modal:
  - Shared volume `vibe-media` mounted at `/vol`.
  - Media lives under `/vol/media`; that folder is the browsable root, so the
    Library never sees `/vol/.home` or anything else on the volume.

The Modal web_server ingress buffers responses, which is poor for video. So on
startup we open a Modal fast tunnel (a direct, low-latency path) and publish its
URL from the discovery endpoints. Clients hit `/` or `/start` first to learn the
fast-tunnel base URL, then do all listing/streaming against that.

Endpoints:
  GET /  and  /start          -> {"url": <fast-tunnel base>, "terminal_url": ...}
  GET /health                 -> {"ok": true}
  GET /list?path=/            -> folder listing (folders first, then files)
  GET /stream?path=/f.mkv     -> media stream (206 Partial Content on Range)
  GET /download-url?path=     -> {"url": ".../stream?path=..."}
  GET /terminal               -> xterm.js web terminal UI
  WS  /ws/terminal            -> PTY-backed shell (bash) for the volume

Deploy:  modal deploy app.py
"""

import mimetypes
import os
import re
import stat
import threading
import time
from pathlib import Path
from typing import Optional
from urllib.parse import quote

import anyio

try:
    import modal
except ImportError:
    modal = None

from terminal import add_terminal_routes

APP_NAME = "alextv-library"
MOUNT_PATH = "/vol"
# The Library only ever browses inside the media folder, never the whole volume.
MEDIA_ROOT = Path(MOUNT_PATH).resolve() / "media"
# The container's own $HOME (/root) is wiped on every restart, so tool state
# written there (yt-dlp/aria2 config, shell history, git config, pi-coding-agent
# state) is lost. Point HOME at this volume-backed dir so it persists instead.
# It lives outside MEDIA_ROOT, so the Library never lists it.
HOME_ROOT = Path(MOUNT_PATH).resolve() / ".home"

# Extensions we surface as playable media. Anything else is hidden from /list so
# the Library stays a clean movie/series browser.
MEDIA_EXTENSIONS = {
    ".mkv", ".mp4", ".avi", ".mov", ".ts", ".flv", ".webm", ".m4v",
    ".mp3", ".flac", ".wav", ".ogg", ".aac", ".wma", ".opus",
}

# mimetypes.guess_type() returns None for .mkv/.m4v/.ts on many systems, which
# would fall back to application/octet-stream and make browsers download rather
# than play. Pin the common ones so the Content-Type is always sensible.
MEDIA_MIME_TYPES = {
    ".mkv": "video/x-matroska",
    ".mp4": "video/mp4",
    ".m4v": "video/x-m4v",
    ".mov": "video/quicktime",
    ".avi": "video/x-msvideo",
    ".ts": "video/mp2t",
    ".flv": "video/x-flv",
    ".webm": "video/webm",
    ".mp3": "audio/mpeg",
    ".flac": "audio/flac",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".aac": "audio/aac",
    ".opus": "audio/opus",
    ".wma": "audio/x-ms-wma",
}

# Resolution badges parsed straight from the file name (cheap — no ffprobe).
# Ordered most-specific first so "2160p" wins before a bare "1080" check, etc.
_RES_PATTERNS = [
    (re.compile(r"\b(4k|2160p?|uhd)\b", re.IGNORECASE), "4K"),
    (re.compile(r"\b1440p?\b", re.IGNORECASE), "1440p"),
    (re.compile(r"\b1080p?\b", re.IGNORECASE), "1080p"),
    (re.compile(r"\b720p?\b", re.IGNORECASE), "720p"),
    (re.compile(r"\b480p?\b", re.IGNORECASE), "480p"),
]


def _format_bytes(size: int) -> str:
    """Human-readable size, e.g. 2.4 GB. Matches the mock's badge style."""
    if size <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB"]
    value = float(size)
    unit = 0
    while value >= 1024 and unit < len(units) - 1:
        value /= 1024
        unit += 1
    formatted = f"{value:.2f}".rstrip("0").rstrip(".")
    return f"{formatted} {units[unit]}"


def _resolution_label(name: str) -> Optional[str]:
    """Best-effort resolution badge from a file name, or None if unknown."""
    for pattern, label in _RES_PATTERNS:
        if pattern.search(name):
            return label
    return None


def _resolve_path(raw_path: str) -> Path:
    """Resolve a client path against MEDIA_ROOT, refusing anything that escapes it."""
    if not raw_path:
        raw_path = "/"
    if not raw_path.startswith("/"):
        raw_path = f"/{raw_path}"
    rel = raw_path.lstrip("/")
    full = (MEDIA_ROOT / rel).resolve()
    if full != MEDIA_ROOT and MEDIA_ROOT not in full.parents:
        raise ValueError("Invalid path")
    return full


def _display_path(full_path: Path) -> str:
    """Path as the client sees it: "/" at the root, "/Series/S01" below."""
    if full_path == MEDIA_ROOT:
        return "/"
    return "/" + full_path.relative_to(MEDIA_ROOT).as_posix()


async def _iter_file(
    path: Path,
    start: int,
    length: int,
    request=None,
    chunk_size: int = 1024 * 1024,
    touch=None,
):
    """
    Async generator that yields `length` bytes from `path` starting at `start`,
    1 MiB at a time — built to survive a media player's seek/buffer churn.

    Why async and disconnect-aware: a player abandons its current connection
    whenever the viewer seeks (or when it re-buffers), then opens a fresh range
    request. A naive blocking generator has no idea that happened and keeps
    reading the volume for a stream nobody is watching, pinning a worker thread
    the whole time. Enough abandoned streams over one long movie drain the
    thread pool and freeze the whole container — every /stream AND /list request
    then waits forever. (That is the "everything hung, calls piling up, only a
    restart fixed it" failure.)

    Two things prevent that here:
      * Each blocking disk read is pushed to a worker thread via anyio and the
        thread is released the instant that one 1 MiB read returns — threads are
        never held for the life of a stream, only for a single read.
      * Before every chunk we check request.is_disconnected(). The moment the
        player goes away, we stop and close the file, so an abandoned stream
        frees its resources immediately instead of running to the end of the
        movie. Starlette also cancels this generator on disconnect, which shuts
        the loop regardless.
    """
    f = await anyio.to_thread.run_sync(lambda: path.open("rb"))
    try:
        await anyio.to_thread.run_sync(f.seek, start)
        remaining = length
        while remaining > 0:
            if request is not None and await request.is_disconnected():
                break
            to_read = min(chunk_size, remaining)
            chunk = await anyio.to_thread.run_sync(f.read, to_read)
            if not chunk:
                break
            remaining -= len(chunk)
            if touch:
                try:
                    touch()
                except Exception:
                    pass
            yield chunk
    finally:
        await anyio.to_thread.run_sync(f.close)


class _ActivityTracker:
    """Records the last request time so the container can idle down when quiet."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._last = time.monotonic()

    def touch(self) -> None:
        with self._lock:
            self._last = time.monotonic()

    def idle_seconds(self) -> float:
        with self._lock:
            return time.monotonic() - self._last


def create_api_app(activity: _ActivityTracker, tunnel_info: dict):
    from fastapi import FastAPI, HTTPException, Request
    from fastapi.middleware.cors import CORSMiddleware
    from fastapi.responses import JSONResponse, Response, StreamingResponse

    api_app = FastAPI(title="AlexTV Library")

    @api_app.on_event("startup")
    async def _raise_thread_capacity() -> None:
        # Sync work (the /list directory scan, the terminal's PTY reads) runs in
        # anyio's shared worker-thread pool, whose default cap (~40) sits below
        # the 100 concurrent requests modal.concurrent(max_inputs=100) allows.
        # Streaming no longer parks threads for a stream's lifetime, but raise
        # the ceiling anyway so a burst of listings can never starve the pool.
        try:
            limiter = anyio.to_thread.current_default_thread_limiter()
            limiter.total_tokens = 200
        except Exception:
            pass

    # The TV app and the web prototype call this from other origins; allow all.
    api_app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["GET", "HEAD"],
        allow_headers=["*"],
    )

    @api_app.middleware("http")
    async def _touch_activity(request: Request, call_next):
        activity.touch()
        return await call_next(request)

    def _discovery() -> dict:
        # Hand out the fast tunnel URL clients should use for streaming. The
        # tunnel is a direct low-latency path, unlike the buffered web_server
        # ingress this discovery endpoint is reached through.
        url = tunnel_info.get("url")
        if not url:
            raise HTTPException(status_code=503, detail="Tunnel not ready yet")
        return {
            "url": url,
            "terminal_url": f"{url}/terminal",
            "cached": True,
        }

    @api_app.get("/")
    def root() -> dict:
        return _discovery()

    @api_app.get("/start")
    def start_discovery() -> dict:
        return _discovery()

    @api_app.get("/health")
    def health() -> dict:
        return {"ok": True}

    @api_app.get("/list")
    def list_items(path: str = "/") -> JSONResponse:
        """
        List one level of the media tree. Folders come first (alphabetical),
        then files (newest first). Non-media files are hidden. Each file carries
        a size + a filename-derived resolution badge for the Library rows.
        """
        try:
            target = _resolve_path(path)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if not target.exists():
            raise HTTPException(status_code=404, detail="Path not found")
        if not target.is_dir():
            raise HTTPException(status_code=400, detail="Path is not a directory")

        # Stat each entry exactly once, up front, tolerating entries that vanish
        # mid-scan. The terminal is a live shell writing to this same folder
        # (yt-dlp/aria2 finishing a download, an mv/rename), so a file can
        # disappear between iterdir() and stat() — skip it rather than 500.
        entries = []
        for entry in target.iterdir():
            if entry.name.startswith("."):
                continue
            try:
                st = entry.stat()
            except OSError:
                continue
            is_dir = stat.S_ISDIR(st.st_mode)
            if not is_dir and entry.suffix.lower() not in MEDIA_EXTENSIONS:
                continue
            entries.append((entry, st, is_dir))

        # Folders A→Z, then files newest-first, mirroring the reference backend.
        # Sort on the cached stat so we don't re-stat (and don't race) here.
        entries.sort(
            key=lambda e: (
                not e[2],
                e[0].name.lower() if e[2] else -e[1].st_mtime,
            )
        )

        items = []
        for entry, st, is_dir in entries:
            item = {
                "type": "folder" if is_dir else "file",
                "name": entry.name,
                "path": _display_path(entry),
                "size": None if is_dir else st.st_size,
                "sizeFormatted": None if is_dir else _format_bytes(st.st_size),
                "mtime": st.st_mtime,
            }
            if is_dir:
                # Episode count for the folder badge; cheap directory scan.
                try:
                    item["itemCount"] = sum(
                        1
                        for c in entry.iterdir()
                        if not c.name.startswith(".")
                        and (c.is_dir() or c.suffix.lower() in MEDIA_EXTENSIONS)
                    )
                except OSError:
                    item["itemCount"] = 0
            else:
                item["resolution"] = _resolution_label(entry.name)
            items.append(item)

        return JSONResponse(
            {
                "path": _display_path(target),
                "parentPath": None if target == MEDIA_ROOT else _display_path(target.parent),
                "items": items,
            }
        )

    def _media_type(name: str) -> str:
        ext = os.path.splitext(name)[1].lower()
        if ext in MEDIA_MIME_TYPES:
            return MEDIA_MIME_TYPES[ext]
        mime_type, _ = mimetypes.guess_type(name)
        return mime_type or "application/octet-stream"

    @api_app.head("/stream")
    def stream_head(path: str):
        """Answer the HEAD probe some players send before ranging."""
        try:
            target = _resolve_path(path)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if not target.exists() or not target.is_file():
            raise HTTPException(status_code=404, detail="File not found")
        file_size = target.stat().st_size
        return Response(
            headers={
                "Accept-Ranges": "bytes",
                "Content-Length": str(file_size),
            },
            media_type=_media_type(target.name),
        )

    @api_app.get("/stream")
    async def stream_file(request: Request, path: str):
        """Stream a media file, honouring a Range header so the player can seek."""
        try:
            target = _resolve_path(path)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if not target.exists() or not target.is_file():
            raise HTTPException(status_code=404, detail="File not found")

        file_size = target.stat().st_size
        range_header = request.headers.get("range")
        media_type = _media_type(target.name)

        if range_header is None:
            headers = {
                "Accept-Ranges": "bytes",
                "Content-Length": str(file_size),
            }
            return StreamingResponse(
                _iter_file(target, 0, file_size, request=request, touch=activity.touch),
                media_type=media_type,
                headers=headers,
            )

        match = re.match(r"bytes=(\d*)-(\d*)", range_header)
        if not match or match.group(0) != range_header.strip():
            raise HTTPException(status_code=416, detail="Invalid Range header")
        start_str, end_str = match.groups()
        if start_str:
            # Normal range: bytes=START-  or  bytes=START-END
            start = int(start_str)
            end = int(end_str) if end_str else file_size - 1
        elif end_str:
            # Suffix range: bytes=-N means "the last N bytes", not the first N.
            suffix = int(end_str)
            if suffix == 0:
                raise HTTPException(status_code=416, detail="Range out of bounds")
            start = max(0, file_size - suffix)
            end = file_size - 1
        else:
            raise HTTPException(status_code=416, detail="Invalid Range header")
        if start >= file_size:
            raise HTTPException(status_code=416, detail="Range out of bounds")
        end = min(end, file_size - 1)
        length = end - start + 1
        headers = {
            "Content-Range": f"bytes {start}-{end}/{file_size}",
            "Accept-Ranges": "bytes",
            "Content-Length": str(length),
        }
        return StreamingResponse(
            _iter_file(target, start, length, request=request, touch=activity.touch),
            status_code=206,
            media_type=media_type,
            headers=headers,
        )

    @api_app.get("/download-url")
    def download_url(request: Request, path: str) -> dict:
        """Return an absolute /stream URL for a file (handy for the player)."""
        try:
            target = _resolve_path(path)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if not target.exists() or not target.is_file():
            raise HTTPException(status_code=404, detail="File not found")
        # Prefer the fast-tunnel base (correct https scheme + low-latency path).
        # request.base_url reports http:// behind Modal's tunnel proxy, which
        # breaks the player, so only fall back to it if the tunnel isn't up yet.
        base = tunnel_info.get("url") or str(request.base_url).rstrip("/")
        return {"url": f"{base}/stream?path={quote(path)}"}

    # xterm.js web terminal (/terminal + /ws/terminal), serving the volume.
    add_terminal_routes(api_app, touch=activity.touch)

    return api_app


# --- Modal deployment (skipped when modal isn't installed). ---
if modal is not None:
    _here = os.path.dirname(__file__)
    image = (
        modal.Image.debian_slim()
        .apt_install(
            "ca-certificates",
            "bash",
            "curl",
            "ffmpeg",
            "aria2",
            "git",
        )
        .run_commands(
            "pip3 install -U pip",
            "pip3 install fastapi 'uvicorn[standard]'",
            # yt-dlp from pip stays more current than the apt package.
            "pip3 install -U yt-dlp",
        )
        .run_commands(
            # Latest Node.js (24.x) + npm via NodeSource.
            "curl -fsSL https://deb.nodesource.com/setup_24.x | bash -",
            "apt-get install -y nodejs",
            "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
        )
        # terminal.py must import alongside app.py; terminal.html is served
        # from /app. xterm.js assets load from a CDN, so no vendor dir needed.
        .add_local_file(os.path.join(_here, "terminal.py"), "/root/terminal.py", copy=True)
        .add_local_file(os.path.join(_here, "terminal.html"), "/app/terminal.html", copy=True)
    )

    app = modal.App(APP_NAME, image=image)
    media_volume = modal.Volume.from_name("alextv-library", create_if_missing=True)

    @app.function(
        timeout=86400,
        min_containers=1,
        max_containers=1,
        volumes={MOUNT_PATH: media_volume},
    )
    @modal.concurrent(max_inputs=100)
    @modal.web_server(8000, startup_timeout=60)
    def start():
        os.makedirs(MEDIA_ROOT, exist_ok=True)
        # Persist HOME on the volume so tool configs survive restarts. Set it in
        # the process env before anything spawns so uvicorn and every terminal
        # subprocess inherit it.
        os.makedirs(HOME_ROOT, exist_ok=True)
        os.environ["HOME"] = str(HOME_ROOT)
        import uvicorn

        activity = _ActivityTracker()
        tunnel_info: dict = {}

        def _open_tunnel():
            # Hold a fast tunnel open for the life of the container and publish
            # its URL so the discovery endpoints (/ and /start) can hand it out.
            # The fast tunnel is a direct, low-latency path — far better for
            # media streaming than the buffered web_server ingress.
            while True:
                try:
                    with modal.forward(8000) as t:
                        tunnel_info["url"] = t.url.rstrip("/")
                        while True:
                            time.sleep(3600)
                except Exception:
                    tunnel_info.pop("url", None)
                    time.sleep(2)

        threading.Thread(target=_open_tunnel, daemon=True).start()

        def _commit_volume():
            # Modal auto-commits the volume in the background and on a clean
            # shutdown, but a hard SIGKILL (timeout, redeploy, crash) can lose
            # everything written since the last commit. The terminal exists to
            # download/rename files into /vol/media, so commit on a short cycle
            # to keep that window small and not lose a finished download.
            while True:
                time.sleep(30)
                try:
                    media_volume.commit()
                except Exception:
                    pass

        threading.Thread(target=_commit_volume, daemon=True).start()

        config = uvicorn.Config(
            create_api_app(activity, tunnel_info),
            host="0.0.0.0",
            port=8000,
            log_level="warning",
        )
        server = uvicorn.Server(config)
        threading.Thread(target=server.run, daemon=True).start()
