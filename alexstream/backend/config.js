import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Load .env into process.env if present (native, no dependency on Node >= 20.6).
const envPath = path.join(__dirname, '.env');
if (fs.existsSync(envPath)) {
  process.loadEnvFile(envPath);
}

function required(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name} (see .env.example)`);
  }
  return value;
}

export const SHOWBOX = {
  baseUrl: process.env.SHOWBOX_BASE_URL || 'https://mbpapi.shegu.net/api/api_client/index/',
  appKey: process.env.SHOWBOX_APP_KEY || 'moviebox',
  iv: required('SHOWBOX_IV'),
  key: required('SHOWBOX_KEY'),
  defaults: {
    childmode: '0', app_version: '11.5', appid: '27', lang: 'en',
    platform: 'android', channel: 'Website', version: '129', medium: 'Website',
  },
};

export const FEBBOX = {
  baseUrl: process.env.FEBBOX_BASE_URL || 'https://www.febbox.com',
  cookie: required('FEBBOX_COOKIE'),
  // Share-link resolution (showbox.media) goes through the Cloudflare worker:
  // showbox.media blocks direct/datacenter IPs but allows Cloudflare.
  proxyBase: process.env.PROXY_BASE || 'https://lunaissohot.lunastar0003.workers.dev/?destination=',
  // Playback streams (shegu.net CDN) go through the Modal proxy: shegu blocks
  // Cloudflare egress (502/522) but not Modal's AWS IPs.
  streamProxyBase: process.env.STREAM_PROXY_BASE || 'https://alexhasitbig--alexstream-proxy-proxy.modal.run/?destination=',
};

export const TMDB = {
  baseUrl: process.env.TMDB_BASE_URL || 'https://api.themoviedb.org/3',
  apiKey: process.env.TMDB_API_KEY || '8bd45cfb804f84ce85fa6accd833d6a1',
};

export const PORT = process.env.PORT || 3000;
