  Here's the end-to-end movie playback workflow in the AlexStream Android TV app:

   Browse -> Resolve -> Stream chain

   1. Browse / search (TMDB)
   The web UI (bundled in assets/) pulls discovery data from TMDB client-side and caches it. Each title only carries TMDB metadata at this point, no playable URL.

   2. User clicks a title -> resolve to ShowBox id
   •  Web UI calls GET /api/resolve?title=&year=&type= on the Node backend (configured base URL via BackendConfig.kt / native-bridge.js).
   •  Backend bridges the TMDB title to a ShowBox id. ShowBox requests are signed (Triple-DES + MD5) the way the MovieBox Android app does it.

   3. ShowBox id -> FebBox share key
   •  GET /api/share-key?id=&type= returns a FebBox share key.

   4. List files in the share
   •  GET /api/files?shareKey=&parentId= lists the files/folders inside that share.

   5. Get playable stream links
   •  GET /api/links?fid= returns quality-tagged stream URLs (HLS .m3u8 or MP4) for the chosen file. FebBox is reached through a Cloudflare Worker proxy.

   Quality picker -> playback

   6. Quality modal (player.js openQualityModal(fid, title))
   Fetches /api/links?fid=... and shows a Netflix-style list of quality/size/speed options.

   7. Hand to native ExoPlayer (player.js playStream)

   js
     if (window.__hasNativeBridge && typeof window.__nativePlay === 'function') {
       if (window.__nativePlay(url, ext, title, fid)) return;  // -> Kotlin
     }

   Inside the Android WebView, native-bridge.js calls AndroidBridge.play(url, ext, title, fid) (exposed by MainActivity), which launches PlayerActivity with the extras EXTRA_STREAM_URL, 
   EXTRA_STREAM_EXT, EXTRA_TITLE, EXTRA_FID.

   8. ExoPlayer plays the URL (PlayerActivity.kt -> PlayerScreen.kt)
   •  Playback starts immediately using the proxied stream URL.
   •  In parallel, LaunchedEffect(fid) calls /api/subtitles?fid=... to fetch English subtitle tracks for the exact file; the list is sideloaded into ExoPlayer as soon as it resolves.
   •  If running outside the Android shell, player.js falls back to an HTML5 <video> element, using hls.js for .m3u8 and adding <track> elements from /api/subtitles?fid=....

   Summary diagram

     TMDB browse ──click──▶ /api/resolve ──▶ ShowBox id
                                                   │
                               /api/share-key ◀────┘
                                     │
                               /api/files  (FebBox, via CF Worker proxy)
                                     │
                               /api/links  ──▶ quality modal
                                                     │  selected
                                                     ▼
                               AndroidBridge.play(url, ext, title, fid)
                                                     │
                               PlayerActivity + ExoPlayer
                                                     │  async
                               /api/subtitles?fid=  ─▶ sideload tracks

   The native ExoPlayer path is preferred on Android TV (smooth D-pad controls), with an HTML5/HLS.js fallback for non-WebView environments.

   okay so the url which is given to exoplayer to play , is it proxied or what ?                                                                                                                           

   Read 1 file
    ↳ .../alexstream/backend/server.js

   Read 1 file
    ↳ .../alexstream/backend/config.js

⛬  Yes, the URL given to ExoPlayer is proxied through a Cloudflare Worker.

   In server.js handleLinks:

   js
     const withProxy = links.map((l) => ({ ...l, proxiedUrl: proxyUrl(l.url) }));

   where proxyUrl() wraps the raw FebBox URL with:

   js
     return `${FEBBOX.proxyBase}${encodeURIComponent(url)}`;

   So the player receives proxiedUrl, not the raw FebBox link. FEBBOX.proxyBase defaults to https://lunaissohot.lunastar0003.workers.dev/?destination= (overridable via PROXY_BASE).

   So the final URL ExoPlayer fetches is something like:

     https://lunaissohot.lunastar0003.workers.dev/?destination=<url-encoded FebBox stream URL>

   The proxy exists because FebBox typically requires a ui cookie / referer and would otherwise reject direct requests from the player. The Cloudflare Worker forwards the request to FebBox with the 
   proper headers so ExoPlayer can play the stream without needing to handle FebBox auth itself. The raw url field is still returned alongside proxiedUrl, but player.js only ever passes l.proxiedUrl 
   into playStream.
