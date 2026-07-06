package com.example.alextv

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.delay

// Design tokens from the web CSS :root
private val BgColor = Color(0xFF08080A)
private val TextColor = Color(0xFFF2F5F8)
private val FocusColor = Color.White
private val UnfocusedBg = Color.White.copy(alpha = 0.18f)

/**
 * Full-screen player activity with a Jetpack Compose controls overlay.
 *
 * Replaces the old media3 PlayerView built-in controls with a custom Compose UI
 * that mirrors the web player's design: gradient top/bottom bars, pill-shaped
 * focusable buttons with scale animations, and a seek bar with a knob that
 * appears on focus.
 *
 * Video surface is a media3 PlayerView (controller disabled) wrapped in
 * AndroidView; Compose controls float on top.
 */
class PlayerActivity : ComponentActivity() {

    private companion object {
        const val BROWSER_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

        const val EXTRA_URL = "url"
        const val EXTRA_EXT = "ext"
        const val EXTRA_TITLE = "title"
    }

    private var player: ExoPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val url = intent.getStringExtra(EXTRA_URL)
        val ext = intent.getStringExtra(EXTRA_EXT)?.lowercase() ?: ""
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""

        if (url.isNullOrEmpty()) {
            finish()
            return
        }

        val exo = createPlayer(url, ext, title)
        player = exo

        setContent {
            PlayerScreen(
                player = exo,
                title = title,
                onClose = { finish() },
            )
        }
    }

    private fun createPlayer(url: String, ext: String, title: String): ExoPlayer {
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

        return exo
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

// ----------------------------------------------------------------
// Compose UI
// ----------------------------------------------------------------

@Composable
private fun PlayerScreen(player: ExoPlayer, title: String, onClose: () -> Unit) {
    var controlsVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(player.isPlaying) }
    var position by remember { mutableStateOf(player.currentPosition) }
    var duration by remember { mutableStateOf(player.duration.coerceAtLeast(0L)) }

    val rootFocusRequester = remember { FocusRequester() }
    val playFocusRequester = remember { FocusRequester() }
    val seekFocusRequester = remember { FocusRequester() }
    val subFocusRequester = remember { FocusRequester() }
    val audioFocusRequester = remember { FocusRequester() }

    // Track player state
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    // Poll position for the seek bar
    LaunchedEffect(player) {
        while (true) {
            position = player.currentPosition
            duration = player.duration.coerceAtLeast(0L)
            delay(500)
        }
    }

    // Auto-hide controls after 3.5s during playback
    LaunchedEffect(controlsVisible, isPlaying) {
        if (controlsVisible && isPlaying) {
            delay(3500)
            controlsVisible = false
        }
    }

    // Manage focus: root when hidden, play button when visible
    LaunchedEffect(controlsVisible) {
        if (controlsVisible) {
            playFocusRequester.requestFocus()
        } else {
            rootFocusRequester.requestFocus()
        }
    }

    BackHandler { onClose() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(rootFocusRequester)
            .onFocusChanged { }
            .focusable()
            .onKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && !controlsVisible) {
                    controlsVisible = true
                    true
                } else {
                    false
                }
            }
    ) {
        // Video surface — PlayerView with built-in controller disabled
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    setKeepContentOnPlayerReset(true)
                    this.player = player
                }
            },
            update = { it.player = player },
            modifier = Modifier.fillMaxSize()
        )

        // Controls overlay
        AnimatedVisibility(
            visible = controlsVisible,
            enter = fadeIn(animationSpec = tween(160)),
            exit = fadeOut(animationSpec = tween(160)),
            modifier = Modifier.fillMaxSize()
        ) {
            ControlsOverlay(
                title = title,
                isPlaying = isPlaying,
                position = position,
                duration = duration,
                playFocusRequester = playFocusRequester,
                seekFocusRequester = seekFocusRequester,
                subFocusRequester = subFocusRequester,
                audioFocusRequester = audioFocusRequester,
                onPlayPause = {
                    if (isPlaying) player.pause() else player.play()
                },
                onSeek = { deltaMs ->
                    val newPos = (position + deltaMs).coerceIn(0L, duration)
                    player.seekTo(newPos)
                    position = newPos
                },
            )
        }
    }
}

@Composable
private fun ControlsOverlay(
    title: String,
    isPlaying: Boolean,
    position: Long,
    duration: Long,
    playFocusRequester: FocusRequester,
    seekFocusRequester: FocusRequester,
    subFocusRequester: FocusRequester,
    audioFocusRequester: FocusRequester,
    onPlayPause: () -> Unit,
    onSeek: (Long) -> Unit,
) {
    Box(Modifier.fillMaxSize()) {
        // ---- Top bar: title with gradient ----
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Black.copy(alpha = 0.7f), Color.Transparent)
                    )
                )
                .padding(horizontal = 40.dp, vertical = 24.dp)
        ) {
            Text(
                text = title,
                color = TextColor,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        // ---- Bottom bar: seek + controls ----
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f))
                    )
                )
                .padding(bottom = 32.dp, start = 40.dp, end = 40.dp, top = 28.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                // Seek bar
                SeekBar(
                    position = position,
                    duration = duration,
                    focusRequester = seekFocusRequester,
                    onSeek = onSeek,
                )

                // Controls row: Play | spacer | Subtitles | Audio
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircleButton(
                        isPlaying = isPlaying,
                        focusRequester = playFocusRequester,
                        onClick = onPlayPause,
                    )
                    Spacer(Modifier.weight(1f))
                    PillButton(
                        label = "Subtitles",
                        focusRequester = subFocusRequester,
                        onClick = { },
                    )
                    PillButton(
                        label = "Audio",
                        focusRequester = audioFocusRequester,
                        onClick = { },
                    )
                }
            }
        }
    }
}

// ----------------------------------------------------------------
// Seek bar — focusable, left/right seeks instead of moving focus
// ----------------------------------------------------------------

@Composable
private fun SeekBar(
    position: Long,
    duration: Long,
    focusRequester: FocusRequester,
    onSeek: (Long) -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    val progress = if (duration > 0) (position.toFloat() / duration) else 0f
    val seekStep = if (duration > 0) (duration * 0.05).toLong() else 10_000L

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .onKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown) {
                    when (e.key) {
                        Key.DirectionLeft -> {
                            onSeek(-seekStep)
                            true
                        }
                        Key.DirectionRight -> {
                            onSeek(seekStep)
                            true
                        }
                        else -> false
                    }
                } else false
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Current time
        Text(
            text = fmtTime(position),
            color = Color.White.copy(alpha = 0.85f),
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.width(56.dp),
            textAlign = TextAlign.Center,
        )

        // Bar
        Box(
            modifier = Modifier
                .weight(1f)
                .height(10.dp)
                .background(
                    if (focused) Color.White.copy(alpha = 0.35f) else Color.White.copy(alpha = 0.22f),
                    RoundedCornerShape(50),
                )
        ) {
            // Fill wrapper — takes up `progress` fraction of the bar
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progress)
            ) {
                // Fill bar
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.White.copy(alpha = 0.85f), RoundedCornerShape(50))
                )
                // Knob — centered on the right edge of the fill wrapper
                androidx.compose.animation.AnimatedVisibility(
                    visible = focused,
                    enter = fadeIn(tween(160)),
                    exit = fadeOut(tween(160)),
                    modifier = Modifier.align(Alignment.CenterEnd)
                ) {
                    Box(
                        modifier = Modifier
                            .size(18.dp)
                            .clip(CircleShape)
                            .background(Color.White)
                    )
                }
            }
        }

        // Duration
        Text(
            text = fmtTime(duration),
            color = Color.White.copy(alpha = 0.85f),
            fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.width(56.dp),
            textAlign = TextAlign.Center,
        )
    }
}

// ----------------------------------------------------------------
// Circular play/pause button
// ----------------------------------------------------------------

@Composable
private fun CircleButton(
    isPlaying: Boolean,
    focusRequester: FocusRequester,
    onClick: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (focused) 1.08f else 1f,
        animationSpec = tween(160, easing = FastOutSlowInEasing),
        label = "circleScale"
    )

    Box(
        modifier = Modifier
            .size(52.dp)
            .scale(scale)
            .clip(CircleShape)
            .background(if (focused) FocusColor else UnfocusedBg)
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .onKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && (e.key == Key.Enter || e.key == Key.DirectionCenter)) {
                    onClick()
                    true
                } else false
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
            contentDescription = if (isPlaying) "Pause" else "Play",
            tint = if (focused) BgColor else TextColor,
            modifier = Modifier.size(24.dp)
        )
    }
}

// ----------------------------------------------------------------
// Pill-shaped button (Subtitles, Audio)
// ----------------------------------------------------------------

@Composable
private fun PillButton(
    label: String,
    focusRequester: FocusRequester,
    onClick: () -> Unit,
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (focused) 1.05f else 1f,
        animationSpec = tween(160, easing = FastOutSlowInEasing),
        label = "pillScale"
    )

    Box(
        modifier = Modifier
            .scale(scale)
            .clip(RoundedCornerShape(50))
            .background(if (focused) FocusColor else UnfocusedBg)
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .onKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && (e.key == Key.Enter || e.key == Key.DirectionCenter)) {
                    onClick()
                    true
                } else false
            }
            .padding(horizontal = 24.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (focused) BgColor else TextColor,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
        )
    }
}

// ----------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------

private fun fmtTime(ms: Long): String {
    val totalSec = ms / 1000
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) {
        "$h:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}"
    } else {
        "$m:${s.toString().padStart(2, '0')}"
    }
}
