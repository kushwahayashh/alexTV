package com.example.alextv

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.Font
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

// ----------------------------------------------------------------
// Design tokens — ported 1:1 from the old Dart theme (AppColors).
// ----------------------------------------------------------------
private val BgColor = Color(0xFF08080A)
private val TextColor = Color(0xFFF2F5F8)
private val MutedColor = Color(0xFF8B8B94)
private val FocusColor = Color(0xFFFFFFFF)

// Varela Round, bundled at res/font/varela_round.ttf. Applied to every Text so
// typography matches the old Flutter/Dart player exactly.
private val VarelaRound = FontFamily(Font(R.font.varela_round))

private const val SEEK_STEP_MS = 10_000L
private const val HIDE_DELAY_MS = 4_000L

/**
 * Full-screen player activity.
 *
 * The Compose overlay is a faithful port of the old Flutter/Dart player
 * (`components/video_player_screen.dart`, removed in commit cdfe08f):
 *
 *   Top bar:    [title]
 *   Bottom bar: [seekbar]
 *               [current time            total time]
 *               [Subtitles] [Audio]   (centered)
 *
 * Focus model (D-pad):
 *   Row 0: [seek]      Row 1: [subtitles] [audio]
 *   - Up/Down moves between rows.
 *   - Left/Right on the seekbar seeks +-10s (intercepted, no focus move).
 *   - Left/Right on the pill row moves between the two pills.
 *   - Enter on the seekbar toggles play/pause (there is NO separate button;
 *     a centered play icon shows when paused).
 *   - Enter on a pill opens a mock menu (no-op).
 *   - Back closes the player.
 *   Controls auto-hide after 4s; any key resurfaces them.
 *
 * ExoPlayer setup (browser UA, decoder fallback, MIME sniffing) is unchanged;
 * only the overlay + input model were rewritten.
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
    var initialized by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }

    // Bumped on every key press; restarts the auto-hide timer (mirrors the old
    // Dart `_bumpActivity()`).
    var activityTick by remember { mutableIntStateOf(0) }

    val seekFocus = remember { FocusRequester() }
    val subFocus = remember { FocusRequester() }
    val audioFocus = remember { FocusRequester() }

    // Player state: READY -> initialized; errors surface the error UI.
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_READY && !initialized) {
                    initialized = true
                    duration = player.duration.coerceAtLeast(0L)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                errorText = "Failed to load video: ${error.errorCodeName}"
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    // Poll position every 500ms (matches the old Dart position timer).
    LaunchedEffect(player) {
        while (true) {
            position = player.currentPosition
            duration = player.duration.coerceAtLeast(0L)
            delay(500)
        }
    }

    // Auto-hide after 4s of inactivity; restarts whenever activityTick changes.
    LaunchedEffect(activityTick) {
        controlsVisible = true
        delay(HIDE_DELAY_MS)
        controlsVisible = false
    }

    // Initial focus lands on the seekbar once controls are up.
    LaunchedEffect(initialized) {
        if (initialized && errorText == null) {
            seekFocus.requestFocus()
        }
    }

    BackHandler { onClose() }

    fun bump() { activityTick++ }

    fun togglePlay() {
        if (player.isPlaying) player.pause() else player.play()
    }

    fun seekBy(deltaMs: Long) {
        val target = (player.currentPosition + deltaMs)
            .coerceIn(0L, duration.coerceAtLeast(0L))
        player.seekTo(target)
        position = target
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            // Any key press re-shows the controls; the event still flows on to
            // the focused child so navigation/seek keep working.
            .onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown) bump()
                false
            }
    ) {
        // Video surface — PlayerView with the built-in controller disabled.
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

        when {
            errorText != null -> ErrorView(errorText!!)

            !initialized -> CircularProgressIndicator(
                color = TextColor,
                modifier = Modifier.align(Alignment.Center),
            )

            else -> {
                // Centered play icon when paused.
                if (!isPlaying) PausedIndicator(Modifier.align(Alignment.Center))

                ControlsOverlay(
                    title = title,
                    visible = controlsVisible,
                    isPlaying = isPlaying,
                    position = position,
                    duration = duration,
                    seekFocus = seekFocus,
                    subFocus = subFocus,
                    audioFocus = audioFocus,
                    onTogglePlay = { togglePlay() },
                    onSeek = { seekBy(it) },
                )
            }
        }
    }
}

@Composable
private fun ControlsOverlay(
    title: String,
    visible: Boolean,
    isPlaying: Boolean,
    position: Long,
    duration: Long,
    seekFocus: FocusRequester,
    subFocus: FocusRequester,
    audioFocus: FocusRequester,
    onTogglePlay: () -> Unit,
    onSeek: (Long) -> Unit,
) {
    // Both bars fade together over 300ms (old Dart AnimatedOpacity). Kept
    // composed while hidden so focus requesters stay valid.
    val barsAlpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(300, easing = EaseOut),
        label = "barsAlpha",
    )

    Box(Modifier.fillMaxSize()) {
        // ---- Top bar: title, gradient top->bottom ----
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .alpha(barsAlpha)
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0xB3000000), Color.Transparent)
                    )
                )
                .padding(horizontal = 40.dp, vertical = 24.dp)
        ) {
            Text(
                text = title,
                color = TextColor,
                fontFamily = VarelaRound,
                fontSize = 24.sp,
                fontWeight = FontWeight.W700,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.CenterStart),
            )
        }

        // ---- Bottom bar: seek + timestamps + pills, gradient bottom->top ----
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .alpha(barsAlpha)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color(0xBF000000))
                    )
                )
                .padding(horizontal = 40.dp, vertical = 28.dp),
        ) {
            SeekBar(
                position = position,
                duration = duration,
                focusRequester = seekFocus,
                onTogglePlay = onTogglePlay,
                onSeek = onSeek,
                modifier = Modifier.focusProperties { down = subFocus },
            )

            Spacer(Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TimeText(fmtTime(position))
                TimeText(fmtTime(duration))
            }

            Spacer(Modifier.height(20.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
            ) {
                PillButton(
                    label = "Subtitles",
                    focusRequester = subFocus,
                    onClick = { },
                    modifier = Modifier.focusProperties {
                        up = seekFocus
                        right = audioFocus
                    },
                )
                Spacer(Modifier.width(14.dp))
                PillButton(
                    label = "Audio",
                    focusRequester = audioFocus,
                    onClick = { },
                    modifier = Modifier.focusProperties {
                        up = seekFocus
                        left = subFocus
                    },
                )
            }
        }
    }
}

// ----------------------------------------------------------------
// Seek bar — focusable; Left/Right seeks, Enter toggles play/pause.
// ----------------------------------------------------------------

@Composable
private fun SeekBar(
    position: Long,
    duration: Long,
    focusRequester: FocusRequester,
    onTogglePlay: () -> Unit,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    var focused by remember { mutableStateOf(false) }
    val progress = if (duration > 0) (position.toFloat() / duration).coerceIn(0f, 1f) else 0f
    val barHeight by animateDpAsState(
        targetValue = if (focused) 10.dp else 8.dp,
        animationSpec = tween(160, easing = EaseOut),
        label = "seekHeight",
    )

    // Outer row keeps the bar full-width; the playhead can overflow vertically.
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(16.dp)
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionLeft -> { onSeek(-SEEK_STEP_MS); true }
                    Key.DirectionRight -> { onSeek(SEEK_STEP_MS); true }
                    Key.Enter, Key.DirectionCenter, Key.NumPadEnter -> { onTogglePlay(); true }
                    else -> false
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        // Track
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(barHeight)
                .clip(RoundedCornerShape(999.dp))
                .background(
                    if (focused) Color.White.copy(alpha = 0.35f)
                    else Color.White.copy(alpha = 0.22f)
                ),
        ) {
            // Fill wrapper spans `progress` fraction of the track.
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progress),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(999.dp))
                        .background(Color.White.copy(alpha = 0.6f))
                )
            }
        }

        // Vertical playhead line at the right edge of the fill (focused only).
        if (focused) {
            Box(
                modifier = Modifier.fillMaxWidth(),
                contentAlignment = Alignment.CenterStart,
            ) {
                Box(
                    modifier = Modifier.fillMaxWidth(progress),
                    contentAlignment = Alignment.CenterEnd,
                ) {
                    Box(
                        modifier = Modifier
                            .width(6.dp)
                            .height(16.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(FocusColor)
                    )
                }
            }
        }
    }
}

// ----------------------------------------------------------------
// Pill-shaped button (Subtitles, Audio) — mock menus.
// ----------------------------------------------------------------

@Composable
private fun PillButton(
    label: String,
    focusRequester: FocusRequester,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (focused) 1.05f else 1f,
        animationSpec = tween(160, easing = FastOutSlowInEasing),
        label = "pillScale",
    )

    Box(
        modifier = modifier
            .scale(scale)
            .clip(RoundedCornerShape(999.dp))
            .background(if (focused) FocusColor else Color.White.copy(alpha = 0.18f))
            .focusRequester(focusRequester)
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .onKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown &&
                    (e.key == Key.Enter || e.key == Key.DirectionCenter || e.key == Key.NumPadEnter)
                ) {
                    onClick(); true
                } else false
            }
            .padding(horizontal = 24.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = label,
            color = if (focused) BgColor else TextColor,
            fontFamily = VarelaRound,
            fontSize = 16.sp,
            fontWeight = FontWeight.W700,
        )
    }
}

// ----------------------------------------------------------------
// Timestamp text (tabular figures via monospaced digits look-alike).
// ----------------------------------------------------------------

@Composable
private fun TimeText(text: String) {
    Text(
        text = text,
        color = Color(0xD9FFFFFF),
        fontFamily = VarelaRound,
        fontSize = 16.sp,
        fontWeight = FontWeight.W700,
    )
}

// ----------------------------------------------------------------
// Center paused indicator.
// ----------------------------------------------------------------

@Composable
private fun PausedIndicator(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(96.dp)
            .clip(CircleShape)
            .background(Color.Black.copy(alpha = 0.55f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.PlayArrow,
            contentDescription = "Paused",
            tint = TextColor,
            modifier = Modifier.size(48.dp),
        )
    }
}

// ----------------------------------------------------------------
// Error view.
// ----------------------------------------------------------------

@Composable
private fun ErrorView(message: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                imageVector = Icons.Outlined.ErrorOutline,
                contentDescription = null,
                tint = MutedColor,
                modifier = Modifier.size(48.dp),
            )
            Spacer(Modifier.height(16.dp))
            Text(
                text = message,
                color = TextColor.copy(alpha = 0.7f),
                fontFamily = VarelaRound,
                fontSize = 16.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = "Press Back to return",
                color = MutedColor,
                fontFamily = VarelaRound,
                fontSize = 14.sp,
            )
        }
    }
}

// ----------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------

private fun fmtTime(ms: Long): String {
    val totalSec = (ms / 1000).coerceAtLeast(0)
    val h = totalSec / 3600
    val m = (totalSec % 3600) / 60
    val s = totalSec % 60
    return if (h > 0) {
        "$h:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}"
    } else {
        "$m:${s.toString().padStart(2, '0')}"
    }
}
