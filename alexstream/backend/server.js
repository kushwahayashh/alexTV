#!/usr/bin/env node
import http from 'node:http';
import CryptoJS from 'crypto-js';
import { customAlphabet } from 'nanoid';
import fetch from 'node-fetch';
import { SHOWBOX, FEBBOX, TMDB, PORT } from './config.js';
import { retryFetch } from './fetch-utils.js';
import { handleSubtitles, handleSubtitleFile } from './subtitles.js';

const nanoid = customAlphabet('1234567890abcdef', 32);

function encrypt(data) {
  return CryptoJS.TripleDES.encrypt(
    data,
    CryptoJS.enc.Utf8.parse(SHOWBOX.key),
    { iv: CryptoJS.enc.Utf8.parse(SHOWBOX.iv) }
  ).toString();
}

function verify(encryptedData) {
  return CryptoJS.MD5(CryptoJS.MD5(SHOWBOX.appKey).toString() + SHOWBOX.key + encryptedData).toString();
}

function expiry() {
  return Math.floor(Date.now() / 1000 + 60 * 60 * 12).toString();
}

async function showboxRequest(module, params = {}) {
  const requestData = { ...SHOWBOX.defaults, expired_date: expiry(), module, ...params };
  const encryptedData = encrypt(JSON.stringify(requestData));
  const body = JSON.stringify({
    app_key: CryptoJS.MD5(SHOWBOX.appKey).toString(),
    verify: verify(encryptedData),
    encrypt_data: encryptedData,
  });
  const formData = new URLSearchParams({
    data: Buffer.from(body).toString('base64'),
    appid: SHOWBOX.defaults.appid,
    platform: SHOWBOX.defaults.platform,
    version: SHOWBOX.defaults.version,
    medium: SHOWBOX.defaults.medium,
    token: nanoid(32),
  });
  const response = await fetch(SHOWBOX.baseUrl, {
    method: 'POST',
    headers: {
      Platform: SHOWBOX.defaults.platform,
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'okhttp/3.2.0',
    },
    body: formData.toString(),
  });
  return response.json();
}

async function getShareKey(id, type = 1) {
  const shareLinkUrl = `https://www.showbox.media/index/share_link?id=${id}&type=${type}`;
  const proxyUrl = `${FEBBOX.proxyBase}${encodeURIComponent(shareLinkUrl)}`;
  const response = await retryFetch(proxyUrl, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  });
  const text = await response.text();
  if (!text.trim().startsWith('{')) return null;
  const data = JSON.parse(text);
  const link = data?.data?.link || '';
  return link ? link.split('/').pop() : null;
}

async function febboxJson(url) {
  const res = await retryFetch(url, {
    headers: {
      cookie: `ui=${FEBBOX.cookie}`,
      referer: FEBBOX.baseUrl,
      'x-requested-with': 'XMLHttpRequest',
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

import { load as cheerioLoad } from 'cheerio';

async function getLinks(fid) {
  const url = `${FEBBOX.baseUrl}/console/video_quality_list?fid=${fid}`;
  const data = await febboxJson(url);
  const html = data.html || '';
  const $ = cheerioLoad(html);
  const links = [];
  $('.file_quality').each((_, el) => {
    const $el = $(el);
    const url = $el.attr('data-url');
    const ext = (url?.match(/\.(mp4|mkv|avi|m3u8)/i)?.[1] || 'm3u8').toLowerCase();
    links.push({
      url,
      quality: $el.attr('data-quality'),
      speed: $el.find('.speed span').text().trim(),
      size: $el.find('.size').text().trim(),
      ext,
    });
  });
  return links;
}

function proxyUrl(url) {
  return `${FEBBOX.streamProxyBase}${encodeURIComponent(url)}`;
}

function parseEpisode(fileName = '') {
  const patterns = [
    /s(\d{1,2})[\s._-]*e(\d{1,3})/i,
    /(?:^|\D)(\d{1,2})x(\d{1,3})(?:\D|$)/i,
  ];

  for (const pattern of patterns) {
    const m = fileName.match(pattern);
    if (m) return { season: Number(m[1]), episode: Number(m[2]) };
  }

  return { season: null, episode: null };
}

function parseResolution(fileName = '') {
  const m = fileName.match(/(\d{3,4})p/i);
  return m ? `${m[1]}p` : null;
}

function mapSearchItem(item, mediaType) {
  return {
    id: item.id,
    media_type: mediaType,
    title: item.title,
    year: item.year,
    poster: item.poster || null,
    poster_min: item.poster_min || null,
    poster_org: item.poster_org || null,
    imdb_rating: item.imdb_rating || null,
    description: item.description || null,
    runtime: item.runtime || null,
    cats: item.cats || null,
    actors: item.actors || null,
  };
}

async function searchType(query, type, mediaType) {
  const data = await showboxRequest('Search5', { type, keyword: query, page: '1', pagelimit: '20' });
  return (data.data || []).map((item) => mapSearchItem(item, mediaType));
}

async function handleSearch(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const query = url.searchParams.get('q') || '';

  if (!query.trim()) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing search query' }));
    return;
  }

  try {
    const [movies, series] = await Promise.all([
      searchType(query, 'movie', 'movie'),
      searchType(query, 'tv', 'tv'),
    ]);
    const results = [...movies, ...series];
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ results }));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

async function handleShareKey(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const id = url.searchParams.get('id');
  const type = url.searchParams.get('type') || '1';

  if (!id) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing id' }));
    return;
  }

  try {
    const shareKey = await getShareKey(id, Number(type));
    if (!shareKey) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'No share key found' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ shareKey }));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

async function handleFiles(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const shareKey = url.searchParams.get('shareKey');
  const parentId = url.searchParams.get('parentId') || '0';

  if (!shareKey) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing shareKey' }));
    return;
  }

  try {
    const apiUrl = `${FEBBOX.baseUrl}/file/file_share_list?share_key=${shareKey}&pwd=&parent_id=${parentId}&is_html=0`;
    const data = await febboxJson(apiUrl);
    const files = data.data?.file_list || [];
    const folders = files
      .filter((f) => f.is_dir === 1)
      .map((f) => ({
        fid: f.fid,
        file_name: f.file_name,
        is_dir: f.is_dir,
      }));
    const videoFiles = files
      .filter((f) => f.is_dir === 0 && /\.(mp4|mkv|avi|m3u8)$/i.test(f.file_name))
      .map((f) => ({ ...f, ...parseEpisode(f.file_name), resLabel: parseResolution(f.file_name) }));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ files, folders, videoFiles }));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

async function handleLinks(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const fid = url.searchParams.get('fid');

  if (!fid) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing fid' }));
    return;
  }

  try {
    const links = await getLinks(Number(fid));
    const withProxy = links.map((l) => ({ ...l, proxiedUrl: proxyUrl(l.url) }));
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ links: withProxy }));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

// Normalize a title for fuzzy matching: lowercase, strip punctuation/articles noise.
function normalizeTitle(s = '') {
  return s
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/['’`:!?.,_\-–—()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// Map a TMDB title (which we browse against) to a streamable ShowBox id by
// searching ShowBox and picking the best title+year match. TMDB and ShowBox use
// unrelated internal ids, so this lookup is the bridge between the two.
async function handleResolve(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const title = (url.searchParams.get('title') || '').trim();
  const year = url.searchParams.get('year') || '';
  const mediaType = url.searchParams.get('type') === 'tv' ? 'tv' : 'movie';

  if (!title) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Missing title' }));
    return;
  }

  try {
    const data = await showboxRequest('Search5', { type: mediaType, keyword: title, page: '1', pagelimit: '20' });
    const items = data.data || [];
    const want = normalizeTitle(title);
    const wantYear = Number(year) || null;

    const scored = items.map((it) => {
      const t = normalizeTitle(it.title);
      const yearDiff = wantYear && it.year ? Math.abs(Number(it.year) - wantYear) : 99;
      return {
        it,
        exact: t === want,
        starts: t.startsWith(want) || want.startsWith(t),
        yearDiff,
      };
    });
    scored.sort((a, b) =>
      Number(b.exact) - Number(a.exact) ||
      a.yearDiff - b.yearDiff ||
      Number(b.starts) - Number(a.starts));

    const best =
      scored.find((s) => s.exact && s.yearDiff <= 1) ||
      scored.find((s) => s.exact) ||
      scored.find((s) => s.starts && s.yearDiff <= 1) ||
      scored[0];

    if (!best) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'No match found on ShowBox' }));
      return;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ id: best.it.id, title: best.it.title, year: best.it.year }));
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

// Proxy TMDB browse/discovery through our own origin so the app talks to a
// single backend. The api_key is injected server-side. Path comes in as
// /api/tmdb/<tmdb-path>, e.g. /api/tmdb/trending/all/week.
async function handleTmdb(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const tmdbPath = url.pathname.replace(/^\/api\/tmdb/, '') || '/';
  const params = new URLSearchParams(url.search);
  params.set('api_key', TMDB.apiKey);

  try {
    const target = `${TMDB.baseUrl}${tmdbPath}?${params.toString()}`;
    const upstream = await retryFetch(target, {
      headers: { accept: 'application/json' },
    });
    const body = await upstream.text();
    res.writeHead(upstream.status, { 'Content-Type': 'application/json' });
    res.end(body);
  } catch (err) {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: err.message }));
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  // CORS: the Android WebView serves bundled assets from an https app origin,
  // so cross-origin calls to this backend need permissive headers.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  if (url.pathname.startsWith('/api/tmdb') && req.method === 'GET') {
    return handleTmdb(req, res);
  }
  if (url.pathname === '/api/search' && req.method === 'GET') {
    return handleSearch(req, res);
  }
  if (url.pathname === '/api/share-key' && req.method === 'GET') {
    return handleShareKey(req, res);
  }
  if (url.pathname === '/api/files' && req.method === 'GET') {
    return handleFiles(req, res);
  }
  if (url.pathname === '/api/links' && req.method === 'GET') {
    return handleLinks(req, res);
  }
  if (url.pathname === '/api/resolve' && req.method === 'GET') {
    return handleResolve(req, res);
  }
  if (url.pathname === '/api/subtitles' && req.method === 'GET') {
    return handleSubtitles(req, res);
  }
  if (url.pathname === '/api/subtitle' && req.method === 'GET') {
    return handleSubtitleFile(req, res);
  }

  // Health check / root.
  if (url.pathname === '/' || url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, service: 'alexstream-api' }));
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not found' }));
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
