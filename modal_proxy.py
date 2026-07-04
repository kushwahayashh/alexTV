"""
Modal streaming proxy for FebBox / shegu.net.

Replaces the Cloudflare Worker proxy — Modal runs on AWS IPs, which the
FebBox CDN (usa7-as*.shegu.net) does not block (unlike Cloudflare egress).

Deploy:
    modal deploy modal_proxy.py

Usage:
    https://<you>--alexstream-proxy.modal.run/?destination=<url-encoded-target>

- Streams non-manifest responses (mp4, .ts segments) with Range support.
- Rewrites HLS m3u8 manifests so sub-playlists and segments route through
  this proxy too (same as the CF worker).
- CORS headers for browser apps.
"""

import re
import urllib.parse

from fastapi import Request, Response
from fastapi.responses import StreamingResponse
from modal import App, Image, fastapi_endpoint

app = App("alexstream-proxy")

image = Image.debian_slim().pip_install("httpx", "fastapi")

STREAM_HOSTS = ("shegu.net", "febbox.com")
PROXY_BASE = "https://alexhasitbig--alexstream-proxy-proxy.modal.run"

CORS_HEADERS = {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, HEAD, OPTIONS",
    "access-control-allow-headers": "range, user-agent, referer",
    "access-control-expose-headers": "content-range, content-length, accept-ranges",
}

BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"


def is_stream_host(hostname: str) -> bool:
    return any(hostname == h or hostname.endswith("." + h) for h in STREAM_HOSTS)


def is_m3u8(content_type: str, path: str) -> bool:
    ct = (content_type or "").lower()
    p = path.lower()
    return "mpegurl" in ct or "m3u8" in ct or p.endswith(".m3u8") or p.endswith(".m3u")


def wrap_proxy(raw_url: str) -> str:
    try:
        parsed = urllib.parse.urlparse(raw_url)
        if is_stream_host(parsed.hostname or ""):
            return f"{PROXY_BASE}?destination={urllib.parse.quote(raw_url, safe='')}"
    except Exception:
        pass
    return raw_url


def resolve_url(raw: str, origin: str, base_path: str) -> str:
    if raw.startswith("http://") or raw.startswith("https://"):
        return raw
    if raw.startswith("/"):
        return origin + raw
    return origin + base_path + raw


def rewrite_m3u8(text: str, target_url: str) -> str:
    parsed = urllib.parse.urlparse(target_url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    path = parsed.path
    base_path = path[: path.rfind("/") + 1] if "/" in path else "/"

    def replace_uri(m):
        raw = m.group(1)
        return f'URI="{wrap_proxy(resolve_url(raw, origin, base_path))}"'

    text = re.sub(r'URI="([^"]+)"', replace_uri, text)

    lines = []
    for line in text.split("\n"):
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#"):
            lines.append(line)
        else:
            lines.append(wrap_proxy(resolve_url(trimmed, origin, base_path)))

    return "\n".join(lines)


@app.function(image=image, min_containers=1)
@fastapi_endpoint(method="GET")
async def proxy(request: Request):
    import httpx

    destination = request.query_params.get("destination", "")

    if not destination:
        return Response(
            "Proxy is running. Add ?destination=https://example.com",
            media_type="text/plain",
        )

    try:
        target = urllib.parse.urlparse(destination)
    except Exception:
        return Response(
            '{"error": "Invalid destination URL"}',
            media_type="application/json",
            status_code=400,
        )

    if not is_stream_host(target.hostname or ""):
        return Response(
            f"Host not allowed: {target.hostname}",
            media_type="text/plain",
            status_code=403,
        )

    upstream_headers = {"user-agent": BROWSER_UA}
    range_header = request.headers.get("range")
    if range_header:
        upstream_headers["range"] = range_header

    # Manifests must be buffered whole so we can rewrite their inner URLs.
    # Everything else (mp4, .ts segments) is streamed chunk-by-chunk so a
    # multi-GB 4K file never lands in container memory.
    looks_like_manifest = target.path.lower().endswith((".m3u8", ".m3u"))

    if looks_like_manifest:
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(60.0, connect=15.0),
                follow_redirects=True,
            ) as client:
                resp = await client.get(destination, headers=upstream_headers)
                content_type = resp.headers.get("content-type", "")

                if is_m3u8(content_type, target.path):
                    rewritten = rewrite_m3u8(resp.text, destination)
                    headers = dict(CORS_HEADERS)
                    return Response(
                        content=rewritten,
                        media_type="application/vnd.apple.mpegurl",
                        headers=headers,
                        status_code=resp.status_code,
                    )

                # Server didn't actually serve a manifest — fall through to a
                # direct byte return (already in memory).
                resp_headers = dict(resp.headers)
                resp_headers.update(CORS_HEADERS)
                return Response(
                    content=resp.content,
                    media_type=content_type,
                    headers=resp_headers,
                    status_code=resp.status_code,
                )
        except Exception as e:
            return Response(
                f"Proxy fetch failed: {e}",
                media_type="text/plain",
                status_code=502,
                headers=CORS_HEADERS,
            )

    # Streaming path: mp4 / .ts / anything large. Keep the client + upstream
    # response open for the lifetime of the byte stream.
    client = httpx.AsyncClient(
        timeout=httpx.Timeout(None, connect=15.0),
        follow_redirects=True,
    )
    try:
        req = client.build_request("GET", destination, headers=upstream_headers)
        upstream = await client.send(req, stream=True)
    except Exception as e:
        await client.aclose()
        return Response(
            f"Proxy fetch failed: {e}",
            media_type="text/plain",
            status_code=502,
            headers=CORS_HEADERS,
        )

    # Forward the bytes-relevant upstream headers (content-range, length, type,
    # accept-ranges) so ExoPlayer's Range requests and seeking work.
    passthrough = {}
    for h in ("content-type", "content-length", "content-range", "accept-ranges"):
        if h in upstream.headers:
            passthrough[h] = upstream.headers[h]
    passthrough.update(CORS_HEADERS)

    async def body():
        try:
            async for chunk in upstream.aiter_bytes(chunk_size=65536):
                yield chunk
        finally:
            await upstream.aclose()
            await client.aclose()

    return StreamingResponse(
        body(),
        status_code=upstream.status_code,
        headers=passthrough,
        media_type=upstream.headers.get("content-type"),
    )
