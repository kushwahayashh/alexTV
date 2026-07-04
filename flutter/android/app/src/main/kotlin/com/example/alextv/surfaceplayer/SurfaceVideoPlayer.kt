package com.example.alextv.surfaceplayer

import android.content.Context
import android.net.Uri
import android.view.SurfaceView
import android.view.ViewGroup
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * ExoPlayer wrapper that renders to a SurfaceView (not TextureView).
 *
 * Why: Flutter's video_player uses TextureView, which forces an extra GPU
 * composition pass. Some Android TV hardware decoders (MediaTek/Amlogic) fail
 * when rendering to a SurfaceTexture but work fine with a direct SurfaceView.
 *
 * Uses DefaultRenderersFactory with decoder fallback enabled so if the
 * hardware decoder still fails, software decoding kicks in as a last resort.
 */
class SurfaceVideoPlayer(
    context: Context,
    private val args: Map<String, Any>,
    private val methodChannel: MethodChannel,
) : PlatformView, Player.Listener {

    private val exoPlayer: ExoPlayer
    private val surfaceView: SurfaceView

    init {
        surfaceView = SurfaceView(context)
        surfaceView.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )

        val renderersFactory = DefaultRenderersFactory(context)
            .setEnableDecoderFallback(true)

        exoPlayer = ExoPlayer.Builder(context)
            .setRenderersFactory(renderersFactory)
            .build()
        exoPlayer.addListener(this)
        exoPlayer.setVideoSurfaceView(surfaceView)

        val url = args["url"] as? String
        val ext = (args["ext"] as? String)?.lowercase() ?: ""
        if (url != null) {
            val mimeType = when {
                ext == "m3u8" -> MimeTypes.APPLICATION_M3U8
                url.contains(".m3u8", ignoreCase = true) -> MimeTypes.APPLICATION_M3U8
                else -> null
            }
            val mediaItem = MediaItem.Builder()
                .setUri(url)
                .apply { mimeType?.let { setMimeType(it) } }
                .build()
            exoPlayer.setMediaItem(mediaItem)
            exoPlayer.prepare()
            if (args["autoPlay"] as? Boolean == true) {
                exoPlayer.playWhenReady = true
            }
        }

        methodChannel.setMethodCallHandler(::handleMethod)
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "play" -> {
                    exoPlayer.play()
                    result.success(null)
                }
                "pause" -> {
                    exoPlayer.pause()
                    result.success(null)
                }
                "seekTo" -> {
                    val pos = (call.argument<Number>("position") ?: 0).toLong()
                    exoPlayer.seekTo(pos)
                    result.success(null)
                }
                "setVolume" -> {
                    val vol = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    exoPlayer.volume = vol
                    result.success(null)
                }
                "dispose" -> {
                    exoPlayer.release()
                    result.success(null)
                }
                "getPosition" -> {
                    result.success(exoPlayer.currentPosition)
                }
                "getDuration" -> {
                    result.success(exoPlayer.duration)
                }
                "isPlaying" -> {
                    result.success(exoPlayer.isPlaying)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("error", e.message, null)
        }
    }

    // --- Player.Listener ---

    override fun onPlaybackStateChanged(state: Int) {
        val stateName = when (state) {
            Player.STATE_IDLE -> "idle"
            Player.STATE_BUFFERING -> "buffering"
            Player.STATE_READY -> "ready"
            Player.STATE_ENDED -> "ended"
            else -> "unknown"
        }
        methodChannel.invokeMethod("onStateChanged", mapOf("state" to stateName))
        if (state == Player.STATE_READY) {
            methodChannel.invokeMethod("onReady", mapOf(
                "duration" to exoPlayer.duration,
                "width" to exoPlayer.videoSize.width,
                "height" to exoPlayer.videoSize.height,
            ))
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        methodChannel.invokeMethod("onPlayingChanged", mapOf("isPlaying" to isPlaying))
    }

    override fun onPlayerError(error: PlaybackException) {
        methodChannel.invokeMethod("onError", mapOf("message" to error.message))
    }

    // --- PlatformView ---

    override fun getView(): SurfaceView = surfaceView

    override fun dispose() {
        exoPlayer.release()
    }
}
