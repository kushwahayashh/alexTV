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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
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

// ----------------------------------------------------------------
// Mock Audio / Subtitles menu data — ported 1:1 from the React
// player-ui (player-ui/src/VideoPlayer.tsx). Both menus render with the same
// modal UI as the main app's quality picker.
// ----------------------------------------------------------------

private data class Track(val id: String, val label: String, val meta: String)
private data class MenuSection(val heading: String, val tracks: List<Track>)
private enum class MenuKind { AUDIO, SUBTITLES }

private val AUDIO_TRACKS = listOf(
    Track("en-51", "English", "5.1 · AC3"),
    Track("en-stereo", "English", "Stereo · AAC"),
    Track("es-stereo", "Spanish", "Stereo · AAC"),
)

private val SUBTITLE_ORG = listOf(
    Track("org-en", "English", "Embedded"),
    Track("org-en-sdh", "English (SDH)", "Embedded"),
    Track("org-es", "Spanish", "Embedded"),
)

private val SUBTITLE_WEB = listOf(
    Track("web-en", "English", "SRT"),
    Track("web-es", "Spanish", "SRT"),
    Track("web-fr", "French", "SRT"),
    Track("web-de", "German", "SRT"),
    Track("web-it", "Italian", "SRT"),
    Track("web-pt", "Portuguese", "SRT"),
    Track("web-ja", "Japanese", "SRT"),
    Track("web-ko", "Korean", "SRT"),
    Track("web-ar", "Arabic", "SRT"),
)

// Per-menu config: an ordered list of sections (each with its own heading).
// D-pad navigation flows through every section as one continuous index; the
// headings only divide the list visually.
private fun menuSections(kind: MenuKind): List<MenuSection> = when (kind) {
    MenuKind.AUDIO -> listOf(MenuSection("Audio Tracks", AUDIO_TRACKS))
    MenuKind.SUBTITLES -> listOf(
        MenuSection("ORG subs", SUBTITLE_ORG),
        MenuSection("WebSubs", SUBTITLE_WEB),
    )
}

private fun menuTracks(kind: MenuKind): List<Track> =
    menuSections(kind).flatMap { it.tracks }

/**
 * Full-screen player activity.
 *
 * The Compose overlay mirrors the React player-ui (player-ui/) 1:1:
 *
 *   Top bar:    [title]              [Subtitles] [Audio]
 *   Bottom bar: [seekbar]
 *               [current time            total time]
 *
 * Focus model (D-pad):
 *   Row 0: [subtitles] [audio]   Row 1: [seek]
 *   - Up/Down moves between rows (pills are above the seekbar).
 *   - Left/Right on the seekbar seeks +-10s (intercepted, no focus move).
 *   - Left/Right on the pill row moves between the two pills.
 *   - Enter on the seekbar toggles play/pause.
 *   - Enter on a pill opens its menu (Subtitles / Audio) — a modal picker with
 *     the same UI as the main app's quality picker, using mock tracks.
 *   - Back closes the open menu first, otherwise closes the player.
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

    // Audio / Subtitles menu state. `menuKind` is null when no menu is open;
    // the selected track index is remembered per menu. `menuReturnFocus` is the
    // pill to restore focus to when the menu closes.
    var menuKind by remember { mutableStateOf<MenuKind?>(null) }
    var selectedAudio by remember { mutableIntStateOf(0) }
    var selectedSubtitle by remember { mutableIntStateOf(0) }
    var menuReturnFocus by remember { mutableStateOf<FocusRequester?>(null) }

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

    // When a menu closes, restore focus to the pill that opened it.
    LaunchedEffect(menuKind) {
        if (menuKind == null) {
            menuReturnFocus?.let {
                it.requestFocus()
                menuReturnFocus = null
            }
        }
    }

    BackHandler { if (menuKind != null) menuKind = null else onClose() }

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
                    onOpenMenu = { kind ->
                        menuReturnFocus = if (kind == MenuKind.AUDIO) audioFocus else subFocus
                        menuKind = kind
                    },
                )
            }
        }

        // Audio / Subtitles menu — drawn above the controls with a scrim.
        menuKind?.let { kind ->
            MenuOverlay(
                kind = kind,
                selectedIndex = if (kind == MenuKind.AUDIO) selectedAudio else selectedSubtitle,
                onSelect = { idx ->
                    if (kind == MenuKind.AUDIO) selectedAudio = idx else selectedSubtitle = idx
                },
                onDismiss = { menuKind = null },
            )
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
    onOpenMenu: (MenuKind) -> Unit,
) {
    // Both bars fade together over 300ms (old Dart AnimatedOpacity). Kept
    // composed while hidden so focus requesters stay valid.
    val barsAlpha by animateFloatAsState(
        targetValue = if (visible) 1f else 0f,
        animationSpec = tween(300, easing = EaseOut),
        label = "barsAlpha",
    )

    Box(Modifier.fillMaxSize()) {
        // ---- Top bar: title (left) + Subtitles/Audio pills (right) ----
        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .alpha(barsAlpha)
                .background(
                    Brush.verticalGradient(
                        listOf(Color(0xB3000000), Color.Transparent)
                    )
                )
                .padding(horizontal = 40.dp, vertical = 24.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = title,
                color = TextColor,
                fontFamily = VarelaRound,
                fontSize = 24.sp,
                fontWeight = FontWeight.W700,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = TextStyle(
                    shadow = Shadow(
                        color = Color(0x99000000),
                        offset = Offset(0f, 2f),
                        blurRadius = 8f,
                    ),
                ),
                modifier = Modifier.weight(1f),
            )
            Spacer(Modifier.width(14.dp))
            PillButton(
                label = "Subtitles",
                focusRequester = subFocus,
                onClick = { onOpenMenu(MenuKind.SUBTITLES) },
                modifier = Modifier.focusProperties {
                    down = seekFocus
                    right = audioFocus
                },
            )
            Spacer(Modifier.width(14.dp))
            PillButton(
                label = "Audio",
                focusRequester = audioFocus,
                onClick = { onOpenMenu(MenuKind.AUDIO) },
                modifier = Modifier.focusProperties {
                    down = seekFocus
                    left = subFocus
                },
            )
        }

        // ---- Bottom bar: seek + timestamps, gradient bottom->top ----
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
                modifier = Modifier.focusProperties { up = subFocus },
            )

            Spacer(Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TimeText(fmtTime(position))
                TimeText(fmtTime(duration))
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
        style = TextStyle(
            fontFeatureSettings = "tnum",
            shadow = Shadow(color = Color(0x66000000), blurRadius = 4f),
        ),
    )
}

// ----------------------------------------------------------------
// Audio / Subtitles menu — same modal UI as the main app's quality picker,
// ported 1:1 from the React player-ui. A focusable scrim traps all D-pad
// input; navigation runs through one continuous index across sections.
// ----------------------------------------------------------------

// A rendered row: a section heading or a track item. `trackIndex` is the
// continuous 0-based index across all sections (used for focus + selection).
private sealed interface MenuRow {
    data class Header(val text: String) : MenuRow
    data class Item(val trackIndex: Int, val track: Track) : MenuRow
}

private fun buildMenuRows(sections: List<MenuSection>): List<MenuRow> {
    val rows = ArrayList<MenuRow>()
    var t = 0
    for (section in sections) {
        rows.add(MenuRow.Header(section.heading))
        for (track in section.tracks) {
            rows.add(MenuRow.Item(t, track))
            t++
        }
    }
    return rows
}

// Emulates the web's scrollIntoView(block:'nearest'): scroll the minimum needed
// to reveal `index` — align to top if it's above the viewport, nudge up if it's
// below, no-op if already visible.
private suspend fun bringNearest(state: LazyListState, index: Int) {
    val info = state.layoutInfo
    val item = info.visibleItemsInfo.firstOrNull { it.index == index }
    if (item == null) {
        state.animateScrollToItem(index)
        return
    }
    val start = info.viewportStartOffset
    val end = info.viewportEndOffset
    if (item.offset < start) {
        state.animateScrollToItem(index)
    } else if (item.offset + item.size > end) {
        state.animateScrollBy(((item.offset + item.size) - end).toFloat())
    }
}

@Composable
private fun MenuOverlay(
    kind: MenuKind,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val sections = remember(kind) { menuSections(kind) }
    val tracks = remember(kind) { menuTracks(kind) }
    val count = tracks.size
    val rows = remember(kind) { buildMenuRows(sections) }
    // trackIndex -> LazyColumn row index (rows include the section headers).
    val trackToRow = remember(kind) {
        IntArray(count).also { arr ->
            rows.forEachIndexed { i, r -> if (r is MenuRow.Item) arr[r.trackIndex] = i }
        }
    }

    var highlight by remember(kind) { mutableIntStateOf(selectedIndex.coerceIn(0, count - 1)) }
    var dir by remember(kind) { mutableIntStateOf(0) } // -1 up, +1 down, 0 on open
    val listState = rememberLazyListState()
    val focus = remember { FocusRequester() }

    // Target-scroll: keep a LEAD-row trail behind the highlight by revealing a
    // row LEAD ahead in the travel direction; snap the container fully to
    // top/bottom near the ends so the section heading / last row isn't clipped.
    LaunchedEffect(highlight) {
        val lead = 3
        when {
            highlight <= lead -> listState.animateScrollToItem(0)
            highlight >= count - 1 - lead -> listState.animateScrollToItem(rows.lastIndex)
            else -> {
                val leadTrack = (highlight + dir * lead).coerceIn(0, count - 1)
                bringNearest(listState, trackToRow[leadTrack])
            }
        }
    }

    LaunchedEffect(Unit) { focus.requestFocus() }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0x99000000)) // scrim (~0.6 black), matches the web overlay
            .focusRequester(focus)
            .focusable()
            .onKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionUp -> {
                        if (highlight > 0) { dir = -1; highlight-- }
                        true
                    }
                    Key.DirectionDown -> {
                        if (highlight < count - 1) { dir = 1; highlight++ }
                        true
                    }
                    // Trap Left/Right so focus can't escape to the pills behind.
                    Key.DirectionLeft, Key.DirectionRight -> true
                    Key.Enter, Key.DirectionCenter, Key.NumPadEnter -> {
                        onSelect(highlight)
                        onDismiss()
                        true
                    }
                    else -> false
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        LazyColumn(
            state = listState,
            modifier = Modifier
                .width(620.dp)
                .heightIn(max = 560.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(Color.White.copy(alpha = 0.22f)),
            contentPadding = PaddingValues(horizontal = 44.dp, vertical = 36.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(rows) { row ->
                when (row) {
                    is MenuRow.Header -> MenuSectionHeader(row.text)
                    is MenuRow.Item -> MenuItemRow(
                        track = row.track,
                        focused = row.trackIndex == highlight,
                        selected = row.trackIndex == selectedIndex,
                    )
                }
            }
        }
    }
}

@Composable
private fun MenuSectionHeader(text: String) {
    Text(
        text = text.uppercase(),
        color = MutedColor,
        fontFamily = VarelaRound,
        fontSize = 13.sp,
        fontWeight = FontWeight.W700,
        letterSpacing = 1.sp,
    )
}

@Composable
private fun MenuItemRow(track: Track, focused: Boolean, selected: Boolean) {
    val scale by animateFloatAsState(
        targetValue = if (focused) 1.02f else 1f,
        animationSpec = tween(160, easing = FastOutSlowInEasing),
        label = "menuItemScale",
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .scale(scale)
            .clip(RoundedCornerShape(999.dp))
            .background(if (focused) FocusColor else Color.White.copy(alpha = 0.22f))
            .padding(horizontal = 24.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (selected) "${track.label} ✔" else track.label,
            color = if (focused) BgColor else TextColor,
            fontFamily = VarelaRound,
            fontSize = 16.sp,
            fontWeight = FontWeight.W700,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(16.dp))
        Text(
            text = track.meta,
            color = (if (focused) BgColor else TextColor).copy(alpha = 0.7f),
            fontFamily = VarelaRound,
            fontSize = 13.sp,
            fontWeight = FontWeight.W600,
            maxLines = 1,
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
