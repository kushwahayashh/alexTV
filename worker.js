/**
 * Cloudflare Worker — streaming proxy for FebBox / shegu.net.
 *
 * https://<worker>.workers.dev/?destination=<url-encoded-target>
 *
 * - Streams non-manifest responses (mp4 segments, .ts, etc) with Range support.
 * - Rewrites HLS m3u8 manifests so every sub-playlist and segment URL routes
 *   back through this proxy. Without rewriting, ExoPlayer reads the absolute
 *   shegu.net URLs inside the manifest and fetches them directly, bypassing
 *   the proxy entirely.
 * - Adds CORS headers so browser apps (hls.js) can fetch through it.
 */

const STREAM_HOSTS = ['shegu.net', 'febbox.com'];

function isStreamHost(hostname) {
  return STREAM_HOSTS.some(
    (h) => hostname === h || hostname.endsWith('.' + h),
  );
}

function isM3u8(contentType, targetUrl) {
  const ct = (contentType || '').toLowerCase();
  const path = targetUrl.pathname.toLowerCase();
  return (
    ct.includes('mpegurl') ||
    ct.includes('m3u8') ||
    path.endsWith('.m3u8') ||
    path.endsWith('.m3u')
  );
}

function wrapProxy(rawUrl, proxyBase) {
  try {
    const parsed = new URL(rawUrl);
    if (isStreamHost(parsed.hostname)) {
      return `${proxyBase}?destination=${encodeURIComponent(rawUrl)}`;
    }
  } catch {
    // not a valid URL — leave as-is
  }
  return rawUrl;
}

function rewriteM3u8(text, targetUrl, proxyBase) {
  const origin = targetUrl.origin;
  const basePath = targetUrl.pathname.substring(
    0,
    targetUrl.pathname.lastIndexOf('/') + 1,
  );

  function resolve(raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return origin + raw;
    return origin + basePath + raw;
  }

  // 1. Rewrite URI="..." attributes inside tags
  //    (#EXT-X-MEDIA, #EXT-X-STREAM-INF, #EXT-X-KEY, #EXT-X-MAP)
  text = text.replace(/URI="([^"]+)"/g, (_match, raw) => {
    return `URI="${wrapProxy(resolve(raw), proxyBase)}"`;
  });

  // 2. Rewrite standalone URL lines (segment / sub-playlist references)
  return text
    .split('\n')
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return line;
      return wrapProxy(resolve(trimmed), proxyBase);
    })
    .join('\n');
}

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, HEAD, OPTIONS',
    'access-control-allow-headers': 'range, user-agent, referer',
    'access-control-expose-headers':
      'content-range, content-length, accept-ranges',
  };
}

export default {
  async fetch(request) {
    const url = new URL(request.url);

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders() });
    }

    const destination = url.searchParams.get('destination');

    if (!destination) {
      return new Response(
        'Proxy is running. Add ?destination=https://example.com',
        { status: 200, headers: { 'content-type': 'text/plain; charset=utf-8' } },
      );
    }

    let target;
    try {
      target = new URL(destination);
    } catch {
      return new Response(JSON.stringify({ error: 'Invalid destination URL' }), {
        status: 400,
        headers: { 'content-type': 'application/json; charset=utf-8' },
      });
    }

    const headers = new Headers(request.headers);
    headers.delete('host');
    headers.delete('cf-connecting-ip');
    headers.delete('cf-ipcountry');
    headers.delete('cf-ray');
    headers.delete('x-forwarded-for');
    headers.delete('x-forwarded-proto');
    headers.delete('x-real-ip');

    const upstream = await fetch(target.toString(), {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
      redirect: 'follow',
    });

    // Build response headers: upstream + CORS
    const respHeaders = new Headers(upstream.headers);
    for (const [k, v] of Object.entries(corsHeaders())) {
      respHeaders.set(k, v);
    }

    // HLS manifest: buffer, rewrite all URLs to route through this proxy,
    // return. This ensures ExoPlayer fetches segments via the proxy too.
    if (isM3u8(upstream.headers.get('content-type'), target)) {
      const text = await upstream.text();
      const proxyBase = url.origin + url.pathname;
      const rewritten = rewriteM3u8(text, target, proxyBase);
      respHeaders.set('content-type', 'application/vnd.apple.mpegurl');
      respHeaders.delete('content-length'); // length changed after rewriting
      return new Response(rewritten, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers: respHeaders,
      });
    }

    // Everything else (mp4, .ts segments, etc): stream directly.
    return new Response(upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: respHeaders,
    });
  },
};
