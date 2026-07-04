package com.example.alextv

import android.app.Activity
import android.os.Bundle
import android.view.WindowManager
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

/**
 * Full-screen native ExoPlayer activity.
 *
 * Launched via intent from Flutter (see MainActivity's method channel). Running
 * playback in its own Activity — instead of a Flutter platform view — takes
 * Flutter out of the render path entirely: no hybrid composition, no per-frame
 * SurfaceView<->Flutter sync, which is what caused the control-UI freezes on
 * weak TV hardware. While this Activity is on top, the Flutter engine is paused.
 *
 * Uses media3's built-in PlayerView controls (D-pad, seek, buffering spinner)
 * which are designed for TV out of the box.
 */
class PlayerActivity : Activity() {

    private companion object {
        const val BROWSER_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        const val EXTRA_URL = "url"
        const val EXTRA_EXT = "ext"
        const val EXTRA_TITLE = "title"
    }

    private var player: ExoPlayer? = null
    private lateinit var playerView: PlayerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        playerView = PlayerView(this).apply {
            setKeepContentOnPlayerReset(true)
            controllerShowTimeoutMs = 3500
            setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)
        }
        setContentView(playerView)

        val url = intent.getStringExtra(EXTRA_URL)
        val ext = intent.getStringExtra(EXTRA_EXT)?.lowercase() ?: ""
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""

        if (url.isNullOrEmpty()) {
            finish()
            return
        }

        initPlayer(url, ext, title)
    }

    private fun initPlayer(url: String, ext: String, title: String) {
        // Browser-like HTTP source: the shegu.net CDN redirects to regional
        // nodes (sometimes https -> http) and expects a browser User-Agent.
        // ExoPlayer's default source refuses cross-protocol redirects and sends
        // a Dalvik UA — a browser <video> element never does, so match it.
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(BROWSER_UA)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(15_000)

        val renderersFactory = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)

        val exo = ExoPlayer.Builder(this)
            .setRenderersFactory(renderersFactory)
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpDataSourceFactory))
            .build()

        // Explicit container hint: the stream URLs carry a query string
        // (…?sign=…&quality=4K) instead of a clean extension, so ExoPlayer's
        // extension-based inference misfires and throws a source error.
        val mimeType = when {
            ext == "m3u8" || url.contains(".m3u8", ignoreCase = true) ->
                MimeTypes.APPLICATION_M3U8
            ext == "mp4" -> MimeTypes.VIDEO_MP4
            ext == "mkv" -> MimeTypes.VIDEO_MATROSKA
            ext == "webm" -> MimeTypes.VIDEO_WEBM
            else -> null
        }

        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .apply { mimeType?.let { setMimeType(it) } }
            .setMediaMetadata(
                androidx.media3.common.MediaMetadata.Builder()
                    .setTitle(title)
                    .build()
            )
            .build()

        exo.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                // Surface the failure instead of a silent black screen, then
                // close back to Flutter.
                android.widget.Toast.makeText(
                    this@PlayerActivity,
                    "Playback error: ${error.errorCodeName}",
                    android.widget.Toast.LENGTH_LONG,
                ).show()
                finish()
            }
        })

        exo.setMediaItem(mediaItem)
        exo.prepare()
        exo.playWhenReady = true

        player = exo
        playerView.player = exo
    }

    override fun onStop() {
        super.onStop()
        player?.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        player?.release()
        player = null
    }
}
