import zlib from 'node:zlib';
import { FEBBOX } from './config.js';
import { retryFetch } from './fetch-utils.js';

async function febboxHtml(url) {
  const res = await retryFetch(url, {
    headers: {
      cookie: `ui=${FEBBOX.cookie}`,
      referer: FEBBOX.baseUrl,
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.text();
}

// FebBox hosts subtitles tied to the exact file being streamed, so they're
// already in sync with the video (unlike title-matched external subs). They live
// in the file's player page, embedded as an escaped HTML string of <li> entries.
async function getFebboxSubtitles(fid) {
  const res = await febboxHtml(`${FEBBOX.baseUrl}/file/player?fid=${fid}`);
  // The subtitle list is an escaped HTML string inside the page's JS; unescape
  // the quotes/slashes so the <li ...> tags can be matched.
  const html = res.replace(/\\"/g, '"').replace(/\\\//g, '/');

  const liRe = /<li\b([^>]*?)data-url="([^"]+\.(?:srt|vtt|ass))"[^>]*>\s*<p[^>]*>([^<]*)<\/p>/gi;
  const seen = new Set();
  const subs = [];
  let m;
  while ((m = liRe.exec(html))) {
    const [, attrs, url, rawName] = m;
    if (seen.has(url)) continue;
    seen.add(url);
    const language = (attrs.match(/data-language="([^"]*)"/) || [])[1] || '';
    const lang = (attrs.match(/data-lang="([^"]*)"/) || [])[1] || '';
    subs.push({ url, language, lang, fileName: rawName.trim() });
  }
  return subs;
}

// Only proxy subtitle files from FebBox's CDN (SSRF guard).
function isAllowedSubHost(rawUrl) {
  try {
    const { hostname } = new URL(rawUrl);
    return hostname === 'images.febbox.com' || hostname.endsWith('.febbox.com');
  } catch {
    return false;
  }
}

// Minimal SRT -> WebVTT. Browsers' <track> needs VTT; the only structural change
// is the timestamp decimal separator (comma -> dot) plus the WEBVTT header.
function srtToVtt(srt) {
  const body = srt
    .replace(/^﻿/, '')
    .replace(/\r\n/g, '\n')
    .replace(/(\d{2}:\d{2}:\d{2}),(\d{3})/g, '$1.$2');
  return `WEBVTT\n\n${body}`;
}

export async function handleSubtitles(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const fid = url.searchParams.get('fid');

  if (!fid) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing fid' }));
    return;
  }

  try {
    const all = await getFebboxSubtitles(fid);

    // FebBox's language labels are user-supplied and sometimes wrong (e.g. a
    // ".kor.srt" tagged "English"), so lean on the filename. Keep English-labelled
    // subs, drop ones whose filename carries an explicit foreign-language code, and
    // rank genuine English markers first so the default track is really English.
    const ENGLISH_MARK = /(?:^|[^a-z])(?:english|eng|sdh)(?:[^a-z]|$)/i;
    const FOREIGN_MARK = /\.(kor|chi|chs|cht|zho|spa|esp|fre|fra|ger|deu|ara|rus|ita|por|jpn|jap|tur|dut|nld|pol|swe|dan|fin|nor|gre|ell|heb|hin|tha|vie|ind|may|ron|rum|hun|cze|ces|slo|srp|hrv|bul|ukr|per|fas|urd|ben|tam|tel|mal)\.(?:srt|vtt|ass)$/i;

    const subtitles = all
      .filter((s) => (/^en/i.test(s.lang) || s.language === 'English'))
      .map((s) => ({ ...s, _eng: ENGLISH_MARK.test(s.fileName), _foreign: FOREIGN_MARK.test(s.fileName) }))
      .filter((s) => s._eng || !s._foreign) // drop clearly-foreign files
      .sort((a, b) => Number(b._eng) - Number(a._eng))
      .map((s, i) => ({
        id: String(i + 1),
        lang: 'eng',
        langName: s.fileName || `English ${i + 1}`,
        url: `/api/subtitle?url=${encodeURIComponent(s.url)}`,
      }));

    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ subtitles }));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

export async function handleSubtitleFile(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const subUrl = url.searchParams.get('url');

  if (!subUrl || !isAllowedSubHost(subUrl)) {
    res.writeHead(400, { 'Content-Type': 'text/plain' });
    res.end('Invalid subtitle url');
    return;
  }

  try {
    const subRes = await retryFetch(subUrl, {
      headers: { 'User-Agent': 'Mozilla/5.0', 'Accept-Charset': 'utf-8' },
    });
    const buffer = Buffer.from(await subRes.arrayBuffer());

    // FebBox serves plain SRT, but gunzip defensively if a source ever sends gzip
    // (magic bytes 0x1f 0x8b).
    const isGzip = buffer[0] === 0x1f && buffer[1] === 0x8b;
    const raw = isGzip ? zlib.gunzipSync(buffer) : buffer;

    const contentType = subRes.headers.get('content-type') || '';
    const charset = contentType.includes('charset=')
      ? contentType.split('charset=')[1].trim().toLowerCase()
      : 'utf-8';
    const srt = new TextDecoder(charset).decode(raw);

    res.writeHead(200, {
      'Content-Type': 'text/vtt; charset=utf-8',
      'Cache-Control': 'public, max-age=86400',
    });
    res.end(srtToVtt(srt));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'text/plain' });
    res.end(`Error: ${err.message}`);
  }
}
