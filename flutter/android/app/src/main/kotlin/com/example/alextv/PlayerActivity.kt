package com.example.alextv

import android.os.Bundle
import android.net.Uri
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.core.content.res.ResourcesCompat
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ErrorOutline
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
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.Density
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.vector.PathParser
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
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.delay

// ----------------------------------------------------------------
// Design tokens — ported 1:1 from the old Dart theme (AppColors).
// ----------------------------------------------------------------
private val BgColor = Color(0xFF08080A)
private val TextColor = Color(0xFFF2F5F8)
private val MutedColor = Color(0xFF8B8B94)
private val FocusColor = Color(0xFFFFFFFF)

/* ---------- Apple-style activity spinner ----------
 * Ring of 12 tapered spokes; the whole ring steps around in 12 discrete jumps
 * so the bright leader hands off spoke-to-spoke with a trailing fade — the
 * classic Cupertino look. Ported 1:1 from the web prototype's Spinner.tsx /
 * Flutter's CupertinoActivityIndicator so every surface shows the same loader.
 */
private const val SPINNER_SPOKES = 12

@Composable
private fun AppleSpinner(
    modifier: Modifier = Modifier,
    size: androidx.compose.ui.unit.Dp = 36.dp,
    color: Color = MutedColor,
) {
    val transition = rememberInfiniteTransition(label = "spinner")
    // Stepped rotation: 12 discrete jumps per second (matches CSS steps(12)).
    val step by transition.animateFloat(
        initialValue = 0f,
        targetValue = SPINNER_SPOKES.toFloat(),
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 1000, easing = LinearEasing),
        ),
        label = "step",
    )
    Canvas(modifier = modifier.size(size)) {
        val leader = step.toInt() % SPINNER_SPOKES
        val cx = this.size.width / 2f
        val cy = this.size.height / 2f
        val spokeW = this.size.width * 0.08f
        val spokeLen = this.size.height * 0.26f
        val radius = this.size.width / 2f - spokeLen / 2f
        for (i in 0 until SPINNER_SPOKES) {
            // Trailing fade: the leader is brightest, each older spoke dimmer.
            val dist = ((leader - i) + SPINNER_SPOKES) % SPINNER_SPOKES
            val alpha = (SPINNER_SPOKES - dist).toFloat() / SPINNER_SPOKES
            val angle = Math.toRadians((i * (360.0 / SPINNER_SPOKES)) - 90.0)
            val ex = cx + (radius * Math.cos(angle)).toFloat()
            val ey = cy + (radius * Math.sin(angle)).toFloat()
            val half = spokeLen / 2f
            val ux = Math.cos(angle).toFloat()
            val uy = Math.sin(angle).toFloat()
            drawLine(
                color = color.copy(alpha = alpha),
                start = Offset(ex - ux * half, ey - uy * half),
                end = Offset(ex + ux * half, ey + uy * half),
                strokeWidth = spokeW,
                cap = StrokeCap.Round,
            )
        }
    }
}

// Varela Round, bundled at res/font/varela_round.ttf. Applied to every Text so
// typography matches the old Flutter/Dart player exactly.
private val VarelaRound = FontFamily(Font(R.font.varela_round))

private const val SUBTITLE_TEXT_SIZE_FRACTION = 0.045f

private fun PlayerView.applyVarelaRoundSubtitleStyle() {
    val subtitleTypeface = ResourcesCompat.getFont(context, R.font.varela_round)
    subtitleView?.apply {
        setStyle(
            CaptionStyleCompat(
                android.graphics.Color.WHITE,
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
                CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                android.graphics.Color.BLACK,
                subtitleTypeface,
            ),
        )
        setFractionalTextSize(SUBTITLE_TEXT_SIZE_FRACTION)
    }
}

private const val SEEK_STEP_MS = 10_000L // base seek step per Left/Right press
private const val HIDE_DELAY_MS = 4_000L
// Max gap between key-repeat events still counted as "holding". A slower gap
// resets the accel ramp so a fresh tap always starts at the base step.
private const val ACCEL_WINDOW_MS = 300L

// Fixed design canvas width, mirroring Flutter's AppSizes.designWidth (1260) and
// its _DesignScaler. TVs report a wide range of logical densities, so laying the
// overlay out in raw dp makes it render zoomed-in on some sets and correct on
// others. Instead we pin every dp/sp to a 1260-unit-wide canvas and uniformly
// scale it to fill the real screen — so proportions match the rest of the app
// (and the React player-ui) regardless of the TV's reported densityDpi.
private const val DESIGN_WIDTH = 1260f

// ----------------------------------------------------------------
// Menu data models.
//
// Subtitles are still mock (ported 1:1 from the React player-ui). Audio is now
// REAL: built from ExoPlayer's parsed tracks at runtime (see audioOptions()).
// Both render with the same modal UI as the main app's quality picker.
// ----------------------------------------------------------------

private data class Track(val id: String, val label: String, val meta: String)
private data class MenuSection(val heading: String, val tracks: List<Track>)
private enum class MenuKind { AUDIO, SUBTITLES }

/**
 * A real audio track from ExoPlayer. [group]/[trackIndex] locate it inside
 * [Tracks] so a [TrackSelectionOverride] can select it. [track] is the
 * display row (label + meta) shown in the menu.
 */
private data class AudioTrackOption(
    val group: TrackGroup,
    val trackIndex: Int,
    val track: Track,
    val selected: Boolean,
)

/**
 * A real text track from ExoPlayer. Same shape as [AudioTrackOption] —
 * [group]/[trackIndex] locate it for a [TrackSelectionOverride]; [selected]
 * marks the one currently showing. [isWeb] distinguishes a sideloaded FebBox
 * (WebSubs) track from an embedded (ORG) one.
 */
private data class TextTrackOption(
    val group: TrackGroup,
    val trackIndex: Int,
    val track: Track,
    val selected: Boolean,
    val isWeb: Boolean,
)

// Both subtitle sections are now real: ORG = embedded text tracks, WebSubs =
// sideloaded FebBox tracks. See textOptions() and the Subtitles menu block.

// ---- Real audio track extraction from ExoPlayer ----

// Human label for an audio track: explicit format label -> language display
// name (en -> "English") -> a numbered fallback.
private fun audioLabel(format: Format, ordinal: Int): String {
    format.label?.takeIf { it.isNotBlank() }?.let { return it }
    val lang = format.language
    if (!lang.isNullOrBlank() && lang != C.LANGUAGE_UNDETERMINED) {
        val loc = java.util.Locale.forLanguageTag(lang)
        val display = loc.displayLanguage
        if (display.isNotBlank()) return display.replaceFirstChar { it.uppercase() }
    }
    return "Audio ${ordinal + 1}"
}

// Meta line: channel layout + codec, e.g. "5.1 · AC3". Either part may be
// omitted if unknown.
private fun audioMeta(format: Format): String {
    val channels = when (format.channelCount) {
        1 -> "Mono"
        2 -> "Stereo"
        6 -> "5.1"
        7 -> "6.1"
        8 -> "7.1"
        Format.NO_VALUE, 0 -> null
        else -> "${format.channelCount}ch"
    }
    val codec = when (format.sampleMimeType) {
        MimeTypes.AUDIO_AAC -> "AAC"
        MimeTypes.AUDIO_AC3 -> "AC3"
        MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC -> "EAC3"
        MimeTypes.AUDIO_AC4 -> "AC4"
        MimeTypes.AUDIO_DTS -> "DTS"
        MimeTypes.AUDIO_DTS_HD -> "DTS-HD"
        MimeTypes.AUDIO_TRUEHD -> "TrueHD"
        MimeTypes.AUDIO_OPUS -> "Opus"
        MimeTypes.AUDIO_VORBIS -> "Vorbis"
        MimeTypes.AUDIO_FLAC -> "FLAC"
        MimeTypes.AUDIO_MPEG, MimeTypes.AUDIO_MPEG_L2 -> "MP3"
        else -> format.sampleMimeType?.substringAfter('/')?.uppercase()
    }
    return listOfNotNull(channels, codec).joinToString(" · ")
}

// Read the current audio tracks from the player. Only selectable (supported)
// tracks are included; `selected` marks the one ExoPlayer is currently playing.
private fun audioOptions(tracks: Tracks): List<AudioTrackOption> {
    val out = ArrayList<AudioTrackOption>()
    var ordinal = 0
    for (group in tracks.groups) {
        if (group.type != C.TRACK_TYPE_AUDIO) continue
        for (i in 0 until group.length) {
            if (!group.isTrackSupported(i)) continue
            val format = group.getTrackFormat(i)
            out.add(
                AudioTrackOption(
                    group = group.mediaTrackGroup,
                    trackIndex = i,
                    track = Track(
                        id = "audio-$ordinal",
                        label = audioLabel(format, ordinal),
                        meta = audioMeta(format),
                    ),
                    selected = group.isTrackSelected(i),
                ),
            )
            ordinal++
        }
    }
    return out
}

// ---- Real embedded (ORG) text track extraction from ExoPlayer ----

// Human label for a text track: explicit format label -> language display name
// (en -> "English") -> a numbered fallback.
private fun textLabel(format: Format, ordinal: Int): String {
    format.label?.takeIf { it.isNotBlank() }?.let { return it }
    val lang = format.language
    if (!lang.isNullOrBlank() && lang != C.LANGUAGE_UNDETERMINED) {
        val loc = java.util.Locale.forLanguageTag(lang)
        val display = loc.displayLanguage
        if (display.isNotBlank()) return display.replaceFirstChar { it.uppercase() }
    }
    return "Track ${ordinal + 1}"
}

// Read the current text tracks. Only selectable (supported) tracks are
// included; `selected` marks the one currently showing (if any). A track whose
// label is in [webLabels] is a sideloaded FebBox subtitle (WebSubs); everything
// else is embedded (ORG).
private fun textOptions(tracks: Tracks, webLabels: Set<String>): List<TextTrackOption> {
    val out = ArrayList<TextTrackOption>()
    var ordinal = 0
    for (group in tracks.groups) {
        if (group.type != C.TRACK_TYPE_TEXT) continue
        for (i in 0 until group.length) {
            if (!group.isTrackSupported(i)) continue
            val format = group.getTrackFormat(i)
            // Skip embedded caption channels that carry no real track (CEA-608/708
            // are always advertised even when empty); they'd show as blank rows.
            if (format.sampleMimeType == MimeTypes.APPLICATION_CEA608 ||
                format.sampleMimeType == MimeTypes.APPLICATION_CEA708
            ) continue
            val fmtLabel = format.label
            val isWeb = fmtLabel != null && webLabels.contains(fmtLabel)
            out.add(
                TextTrackOption(
                    group = group.mediaTrackGroup,
                    trackIndex = i,
                    track = Track(
                        id = "sub-$ordinal",
                        label = if (isWeb) (fmtLabel ?: "English") else textLabel(format, ordinal),
                        meta = if (isWeb) "Web" else "Embedded",
                    ),
                    selected = group.isTrackSelected(i),
                    isWeb = isWeb,
                ),
            )
            ordinal++
        }
    }
    return out
}


/**
 * Full-screen player activity.
 *
 * The Compose overlay mirrors the React player-ui (player-ui/) 1:1:
 *
 *   Top bar:    [title]
 *   Bottom bar:                      [Subtitles] [Audio]
 *               [seekbar]
 *               [current time            total time]
 *
 * Focus model (D-pad):
 *   Row 0: [subtitles] [audio]   Row 1: [seek]
 *   - Up/Down moves between rows (icon buttons are above the seekbar).
 *   - Left/Right on the seekbar seeks +-10s (intercepted, no focus move).
 *   - Left/Right on the icon row moves between the two buttons.
 *   - Enter on the seekbar toggles play/pause.
 *   - Enter on an icon opens its menu (Subtitles / Audio) — a modal picker with
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
        const val EXTRA_MEDIA_PATH = "mediaPath"
        const val EXTRA_SUB_LABELS = "subLabels"
        const val EXTRA_SUB_URLS = "subUrls"
    }

    private var player: ExoPlayer? = null

    // Stable backend path for the file being played; the key watch-progress is
    // stored under. Blank for TMDB/Details playback (no stable path), which
    // disables tracking (see PlaybackProgressStore).
    private var mediaPath: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val url = intent.getStringExtra(EXTRA_URL)
        val ext = intent.getStringExtra(EXTRA_EXT)?.lowercase() ?: ""
        val title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        mediaPath = intent.getStringExtra(EXTRA_MEDIA_PATH) ?: ""

        if (url.isNullOrEmpty()) {
            finish()
            return
        }

        // Resume from the last saved position if this file was partly watched
        // (0L when untracked, too early, or effectively finished).
        val resumePositionMs = PlaybackProgressStore.getResumePositionMs(this, mediaPath)

        // Web (FebBox) subtitles resolved by Dart: parallel label/URL lists. We
        // attach each as an external VTT text track and remember the labels so
        // the menu can tell web subs apart from embedded (ORG) ones.
        val subLabels = intent.getStringArrayListExtra(EXTRA_SUB_LABELS) ?: arrayListOf()
        val subUrls = intent.getStringArrayListExtra(EXTRA_SUB_URLS) ?: arrayListOf()
        val webSubs = subLabels.zip(subUrls)
        val webSubLabels = subLabels.toSet()

        val exo = createPlayer(url, ext, title, webSubs, resumePositionMs)
        player = exo

        setContent {
            PlayerScreen(
                player = exo,
                title = title,
                mediaPath = mediaPath,
                webSubLabels = webSubLabels,
                onClose = { finish() },
            )
        }
    }

    private fun createPlayer(
        url: String,
        ext: String,
        title: String,
        webSubs: List<Pair<String, String>>,
        resumePositionMs: Long,
    ): ExoPlayer {
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

        // Sideloaded web subtitles. The backend always serves WebVTT, so the MIME
        // is fixed. Not marked default — the user opts in via the menu. The label
        // survives onto the track Format so the menu can group it under WebSubs.
        val subConfigs = webSubs.map { (label, u) ->
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(u))
                .setMimeType(MimeTypes.TEXT_VTT)
                .setLanguage("en")
                .setLabel(label)
                .build()
        }

        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .apply { mimeType?.let { setMimeType(it) } }
            .setSubtitleConfigurations(subConfigs)
            .setMediaMetadata(
                androidx.media3.common.MediaMetadata.Builder()
                    .setTitle(title)
                    .build()
            )
            .build()

        exo.setMediaItem(mediaItem)
        exo.prepare()
        // Resume where we left off before starting playback (0L = start fresh).
        if (resumePositionMs > 0L) exo.seekTo(resumePositionMs)
        exo.playWhenReady = true

        return exo
    }

    /**
     * Persist the current position under [mediaPath] so the Library can resume
     * and draw a progress bar. No-op for untracked playback (blank path). The
     * store itself drops entries that are too early or effectively finished.
     */
    private fun persistProgress() {
        val p = player ?: return
        if (mediaPath.isBlank()) return
        val dur = p.duration.takeIf { it > 0L && it != C.TIME_UNSET } ?: 0L
        PlaybackProgressStore.saveProgress(
            context = this,
            mediaPath = mediaPath,
            title = intent.getStringExtra(EXTRA_TITLE) ?: "",
            positionMs = p.currentPosition,
            durationMs = dur,
        )
    }

    // Persist on pause — this runs BEFORE the returning Library activity's
    // onResume, so its progress refresh reads the position we just wrote.
    // (onStop lands too late: MainActivity resumes and re-reads the store
    // before onStop fires, so the bar would show the stale position.)
    override fun onPause() {
        super.onPause()
        persistProgress()
    }

    override fun onStop() {
        super.onStop()
        persistProgress()
        player?.pause()
    }

    override fun onDestroy() {
        super.onDestroy()
        persistProgress()
        player?.release()
        player = null
    }
}

// ----------------------------------------------------------------
// Compose UI
// ----------------------------------------------------------------

/**
 * Compose equivalent of Flutter's `_DesignScaler`: pins [content] to a fixed
 * [DESIGN_WIDTH]-wide canvas and uniformly scales it to fill the screen by
 * overriding [LocalDensity]. Every `.dp`/`.sp` below is then interpreted so
 * that DESIGN_WIDTH design units span the full width — making the overlay
 * canvas-independent (identical proportions on any TV, matching the main app
 * and the React player-ui). fontScale is reset to 1 so the TV's system font
 * scaling can't distort the design.
 */
@Composable
private fun DesignScaler(content: @Composable () -> Unit) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // constraints.maxWidth is the real screen width in physical px.
        val scaledDensity = constraints.maxWidth / DESIGN_WIDTH
        CompositionLocalProvider(
            LocalDensity provides Density(density = scaledDensity, fontScale = 1f),
        ) {
            content()
        }
    }
}

@Composable
private fun PlayerScreen(
    player: ExoPlayer,
    title: String,
    mediaPath: String,
    webSubLabels: Set<String>,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    var controlsVisible by remember { mutableStateOf(true) }
    var isPlaying by remember { mutableStateOf(player.isPlaying) }
    var initialized by remember { mutableStateOf(false) }
    var buffering by remember { mutableStateOf(false) }
    var errorText by remember { mutableStateOf<String?>(null) }
    var position by remember { mutableLongStateOf(0L) }
    var duration by remember { mutableLongStateOf(0L) }

    // Audio / Subtitles menu state. `menuKind` is null when no menu is open.
    // Track selection (audio + subtitles) is read from the player, not stored
    // here. `menuReturnFocus` is the pill to restore focus to when a menu closes.
    var menuKind by remember { mutableStateOf<MenuKind?>(null) }
    var menuReturnFocus by remember { mutableStateOf<FocusRequester?>(null) }

    // Live audio tracks parsed by ExoPlayer; refreshed on every tracks change so
    // the Audio menu (and its current-selection check) stays in sync.
    var currentTracks by remember { mutableStateOf(player.currentTracks) }

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
                // Re-buffering mid-playback (once past the initial load) shows
                // the same spinner over the controls.
                buffering = state == Player.STATE_BUFFERING
                // Finished playback: drop any saved progress so the Library
                // stops showing a resume bar for this file.
                if (state == Player.STATE_ENDED) {
                    PlaybackProgressStore.clearProgress(context, mediaPath)
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                currentTracks = tracks
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

    fun bump() { activityTick++ }

    fun dismissMenu() {
        bump()
        controlsVisible = true
        menuKind = null
    }

    // Back: close an open menu first; else if controls are visible just hide
    // them; only Back with controls already hidden closes the player.
    BackHandler {
        when {
            menuKind != null -> dismissMenu()
            controlsVisible -> controlsVisible = false
            else -> onClose()
        }
    }

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
            // the focused child so navigation/seek keep working. Back is
            // excluded so BackHandler can tell whether the controls were
            // already visible (Back hides them first, then closes).
            .onPreviewKeyEvent { e ->
                if (e.type == KeyEventType.KeyDown && e.key != Key.Back) bump()
                false
            }
    ) {
        // Video surface — PlayerView with the built-in controller disabled.
        // NOT wrapped in the design scaler: it must fill the real screen at true
        // resolution. fillMaxSize resolves against parent pixel constraints, so
        // the density override wouldn't distort it either — but keeping it here
        // makes the intent explicit.
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    setKeepContentOnPlayerReset(true)
                    applyVarelaRoundSubtitleStyle()
                    this.player = player
                }
            },
            update = { it.player = player },
            modifier = Modifier.fillMaxSize()
        )

        // Overlay UI — scaled to the fixed design canvas so its proportions are
        // identical on every TV regardless of reported density.
        DesignScaler {
          Box(Modifier.fillMaxSize()) {
            when {
                errorText != null -> ErrorView(errorText!!)

                !initialized -> AppleSpinner(
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

                    // Mid-playback re-buffering: same spinner, centred over the
                    // video on top of the controls.
                    if (buffering) {
                        AppleSpinner(
                            modifier = Modifier.align(Alignment.Center),
                        )
                    }
                }
            }

            // Audio / Subtitles menu — drawn above the controls with a scrim.
            menuKind?.let { kind ->
                if (kind == MenuKind.AUDIO) {
                    // Real audio tracks from ExoPlayer. Selecting one applies a
                    // TrackSelectionOverride so playback actually switches.
                    val options = remember(currentTracks) { audioOptions(currentTracks) }
                    val sections = remember(options) {
                        val rows = if (options.isEmpty()) {
                            listOf(Track("audio-none", "Default", ""))
                        } else {
                            options.map { it.track }
                        }
                        listOf(MenuSection("Audio Tracks", rows))
                    }
                    val selectedIdx = options.indexOfFirst { it.selected }.coerceAtLeast(0)
                    MenuOverlay(
                        sections = sections,
                        selectedIndex = selectedIdx,
                        onSelect = { idx ->
                            options.getOrNull(idx)?.let { opt ->
                                player.trackSelectionParameters =
                                    player.trackSelectionParameters
                                        .buildUpon()
                                        .setOverrideForType(
                                            TrackSelectionOverride(opt.group, opt.trackIndex)
                                        )
                                        .build()
                            }
                        },
                        onDismiss = { dismissMenu() },
                    )
                } else {
                    // Subtitles menu. ORG subs = embedded text tracks (with a
                    // leading "Off" row); WebSubs = sideloaded FebBox tracks.
                    // Selecting either applies a TrackSelectionOverride (both are
                    // real text tracks); Off disables the text type. The flat menu
                    // index maps to: 0 = Off, then ORG tracks, then WebSubs tracks.
                    val textTracks = remember(currentTracks, webSubLabels) {
                        textOptions(currentTracks, webSubLabels)
                    }
                    val orgOpts = remember(textTracks) { textTracks.filter { !it.isWeb } }
                    val webOpts = remember(textTracks) { textTracks.filter { it.isWeb } }
                    // Selectable tracks in menu order (after the Off row).
                    val ordered = remember(orgOpts, webOpts) { orgOpts + webOpts }

                    val sections = remember(orgOpts, webOpts) {
                        val org = buildList {
                            add(Track("sub-off", "Off", ""))
                            addAll(orgOpts.map { it.track })
                        }
                        val web = if (webOpts.isEmpty()) {
                            listOf(Track("web-none", "None", ""))
                        } else {
                            webOpts.map { it.track }
                        }
                        listOf(MenuSection("ORG subs", org), MenuSection("WebSubs", web))
                    }

                    // Check follows real selection: an active track -> its row
                    // (offset by the Off row); otherwise Off (index 0).
                    val activeIdx = ordered.indexOfFirst { it.selected }
                    val selectedIdx = if (activeIdx >= 0) activeIdx + 1 else 0

                    fun applyOff() {
                        player.trackSelectionParameters =
                            player.trackSelectionParameters.buildUpon()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                                .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                                .build()
                    }
                    fun applyTrack(opt: TextTrackOption) {
                        player.trackSelectionParameters =
                            player.trackSelectionParameters.buildUpon()
                                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                                .setOverrideForType(
                                    TrackSelectionOverride(opt.group, opt.trackIndex)
                                )
                                .build()
                    }

                    MenuOverlay(
                        sections = sections,
                        selectedIndex = selectedIdx,
                        onSelect = { idx ->
                            when {
                                idx == 0 -> applyOff()
                                idx <= ordered.size -> applyTrack(ordered[idx - 1])
                                // "None" placeholder in an empty WebSubs section.
                                else -> Unit
                            }
                        },
                        onDismiss = { dismissMenu() },
                    )
                }
            }
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
        // ---- Top bar: title only (controls moved to bottom bar) ----
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
            // Icon controls, right-aligned above the seek bar.
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    icon = PlayerIcon.SUBTITLES,
                    contentDescription = "Subtitles",
                    focusRequester = subFocus,
                    onClick = { onOpenMenu(MenuKind.SUBTITLES) },
                    modifier = Modifier.focusProperties {
                        down = seekFocus
                        right = audioFocus
                    },
                )
                Spacer(Modifier.width(14.dp))
                IconButton(
                    icon = PlayerIcon.AUDIO,
                    contentDescription = "Audio",
                    focusRequester = audioFocus,
                    onClick = { onOpenMenu(MenuKind.AUDIO) },
                    modifier = Modifier.focusProperties {
                        down = seekFocus
                        left = subFocus
                    },
                )
            }

            Spacer(Modifier.height(20.dp))

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

    // Accelerated seeking: while Left/Right is held, each key repeat grows the
    // step so a long hold covers ground fast. accelCount is the run of
    // consecutive presses in one direction; accelDir is that direction (-1/+1);
    // accelLast is the timestamp of the last press (to detect release/pause).
    val accelCount = remember { mutableIntStateOf(0) }
    val accelDir = remember { mutableIntStateOf(0) }
    val accelLast = remember { mutableLongStateOf(0L) }

    fun accelSeek(dir: Int) {
        val now = System.currentTimeMillis()
        val held = accelDir.intValue == dir && now - accelLast.longValue <= ACCEL_WINDOW_MS
        accelCount.intValue = if (held) accelCount.intValue + 1 else 0
        accelDir.intValue = dir
        accelLast.longValue = now

        // Gentle tiered multiplier by how long the key has been held: holds at
        // the base step for a while, then eases up.
        val c = accelCount.intValue
        val mult = if (c < 8) 1 else if (c < 18) 2 else if (c < 30) 3 else 4
        onSeek(dir * SEEK_STEP_MS * mult)
    }

    fun resetAccel() {
        accelCount.intValue = 0
        accelDir.intValue = 0
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(16.dp)
            .focusRequester(focusRequester)
            .onFocusChanged { if (!it.isFocused) resetAccel(); focused = it.isFocused }
            .focusable()
            .onKeyEvent { e ->
                // Releasing Left/Right ends the hold so the next press starts
                // fresh at the base step.
                if (e.type == KeyEventType.KeyUp) {
                    if (e.key == Key.DirectionLeft || e.key == Key.DirectionRight) {
                        resetAccel()
                    }
                    return@onKeyEvent false
                }
                if (e.type != KeyEventType.KeyDown) return@onKeyEvent false
                when (e.key) {
                    Key.DirectionLeft -> { accelSeek(-1); true }
                    Key.DirectionRight -> { accelSeek(1); true }
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
            // Fill wrapper spans `progress` fraction of the track. Dull by
            // default, solid white when the bar is focused.
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(progress),
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(RoundedCornerShape(999.dp))
                        .background(
                            if (focused) FocusColor
                            else Color.White.copy(alpha = 0.45f)
                        )
                )
            }
        }
    }
}

// ----------------------------------------------------------------
// Circular icon button (Subtitles, Audio) — mock menus. Mirrors the
// React player-ui .player-circle-btn: 44dp circle, 22dp icon, inverts
// color on focus and scales up slightly.
// ----------------------------------------------------------------

private enum class PlayerIcon { SUBTITLES, AUDIO }

@Composable
private fun IconButton(
    icon: PlayerIcon,
    contentDescription: String,
    focusRequester: FocusRequester,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (focused) 1.08f else 1f,
        animationSpec = tween(160, easing = FastOutSlowInEasing),
        label = "iconScale",
    )
    val tint = if (focused) BgColor else TextColor

    Box(
        modifier = modifier
            .scale(scale)
            .size(44.dp)
            .clip(CircleShape)
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
            },
        contentAlignment = Alignment.Center,
    ) {
        when (icon) {
            PlayerIcon.SUBTITLES -> SubtitlesIcon(tint)
            PlayerIcon.AUDIO -> AudioIcon(tint)
        }
    }
}

// Subtitles icon — outlined CC box with two caption lines. Drawn on a 24-unit
// grid to match the React SVG viewBox, rendered at 22dp.
@Composable
private fun SubtitlesIcon(tint: Color) {
    Canvas(modifier = Modifier.size(22.dp)) {
        val u = size.width / 24f // one SVG unit in px
        // Outlined rounded box: x=3 y=5 w=18 h=14 rx=2.5, stroke 2.
        drawRoundRect(
            color = tint,
            topLeft = Offset(3f * u, 5f * u),
            size = Size(18f * u, 14f * u),
            cornerRadius = CornerRadius(2.5f * u, 2.5f * u),
            style = Stroke(width = 2f * u),
        )
        // Caption bars (rounded), matching the SVG's filled rects.
        fun bar(x: Float, y: Float, w: Float, h: Float) {
            drawRoundRect(
                color = tint,
                topLeft = Offset(x * u, y * u),
                size = Size(w * u, h * u),
                cornerRadius = CornerRadius(h / 2f * u, h / 2f * u),
            )
        }
        bar(6f, 9f, 8f, 2f)
        bar(16f, 9f, 2f, 2f)
        bar(6f, 13f, 5f, 2f)
        bar(13f, 13f, 5f, 2f)
    }
}

// Audio icon — Tabler filled "brand-tiktok" path, ported verbatim from the
// React player-ui. Parsed from SVG path data on a 24-unit grid, at 22dp.
private val AudioIconPath: Path = PathParser().parsePathString(
    "M16.083 2h-4.083a1 1 0 0 0 -1 1v11.5a1.5 1.5 0 1 1 -2.519 -1.1l.12 -.1a1 1 0 0 0 " +
        ".399 -.8v-4.326a1 1 0 0 0 -1.23 -.974a7.5 7.5 0 0 0 1.73 14.8l.243 -.005a7.5 7.5 " +
        "0 0 0 7.257 -7.495v-2.7l.311 .153c1.122 .53 2.333 .868 3.59 .993a1 1 0 0 0 1.099 " +
        "-.996v-4.033a1 1 0 0 0 -.834 -.986a5.005 5.005 0 0 1 -4.097 -4.096a1 1 0 0 0 -.986 -.835z"
).toPath()

@Composable
private fun AudioIcon(tint: Color) {
    Canvas(modifier = Modifier.size(22.dp)) {
        scale(size.width / 24f, size.height / 24f, pivot = Offset.Zero) {
            drawPath(AudioIconPath, color = tint)
        }
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

// Fixed ease-in-out tween for menu auto-scroll, matching the browser's smooth
// scrollIntoView. Compose's default scroll animation is a spring (bouncy,
// variable speed); a tween gives the steady, React-like glide.
private val MenuScrollSpec: AnimationSpec<Float> =
    tween(durationMillis = 320, easing = FastOutSlowInEasing)

// Emulates the web's scrollIntoView(block:'nearest') "trail" — but driven off the
// HIGHLIGHT row, which is always laid out, instead of the LEAD row, which usually
// isn't. Compose's layoutInfo only knows about on-screen rows, so targeting an
// off-screen lead row forced a top-aligning animateScrollToItem that snapped the
// list to the end. Here we glide (same MenuScrollSpec tween) only once the
// highlight runs within `lead` rows of the travel edge; animateScrollBy clamps at
// the ends, so the top/bottom snap to 0 / scrollHeight falls out for free.
private suspend fun ensureTrail(state: LazyListState, row: Int, dir: Int, lead: Int) {
    val info = state.layoutInfo
    val vis = info.visibleItemsInfo
    // Highlight off-screen (rare — we keep a `lead`-row buffer ahead of it): a
    // smooth recenter is the safe fallback, and it targets the highlight itself
    // so it can never yank to the end the way the old lead-row lookup did.
    val hi = vis.firstOrNull { it.index == row } ?: run {
        state.animateScrollToItem(row)
        return
    }
    // Average row pitch (item height + gap) from the visible rows, to size the
    // margin we want to keep between the highlight and the travel edge.
    val pitch = if (vis.size >= 2)
        (vis.last().offset - vis.first().offset).toFloat() / (vis.last().index - vis.first().index)
    else hi.size.toFloat()
    val margin = lead * pitch
    val delta = if (dir < 0) (hi.offset - margin) - info.viewportStartOffset
    else (hi.offset + hi.size + margin) - info.viewportEndOffset
    // Only glide in the travel direction, and only once the margin is used up.
    if ((dir < 0 && delta < 0) || (dir >= 0 && delta > 0)) {
        state.animateScrollBy(delta, MenuScrollSpec)
    }
}

@Composable
private fun MenuOverlay(
    sections: List<MenuSection>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val tracks = remember(sections) { sections.flatMap { it.tracks } }
    val count = tracks.size
    val rows = remember(sections) { buildMenuRows(sections) }
    // trackIndex -> LazyColumn row index (rows include the section headers).
    val trackToRow = remember(sections) {
        IntArray(count).also { arr ->
            rows.forEachIndexed { i, r -> if (r is MenuRow.Item) arr[r.trackIndex] = i }
        }
    }

    var highlight by remember(sections) {
        mutableIntStateOf(selectedIndex.coerceIn(0, (count - 1).coerceAtLeast(0)))
    }
    var dir by remember(sections) { mutableIntStateOf(0) } // -1 up, +1 down, 0 on open
    val listState = rememberLazyListState()
    val focus = remember { FocusRequester() }

    // Target-scroll: keep a LEAD-row trail behind the highlight. We glide only
    // once the highlight comes within LEAD rows of the travel edge, driving the
    // scroll off the highlight's own (always laid-out) row. animateScrollBy
    // clamps at the ends, so near the top the first section heading glides to the
    // edge and near the bottom the last row lands without any snap-to-end.
    LaunchedEffect(highlight) {
        ensureTrail(listState, trackToRow[highlight], dir, lead = 3)
    }

    LaunchedEffect(Unit) { focus.requestFocus() }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0x99000000)) // scrim: 0.6 black, matches the web .player-overlay (its backdrop blur(8px) can't be applied over the video SurfaceView)
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
        // Panel frame: clips the scroll list and hosts the top/bottom edge fades
        // so rows dissolve into the panel instead of hard-clipping at the scroll
        // edges. Mirrors the React .player-modal (frame) / .player-modal__scroll
        // (list) split, with the fades ported from its ::before/::after gradients.
        Box(
            modifier = Modifier
                .width(620.dp)
                // max-height: 70vh.
                .heightIn(max = maxHeight * 0.7f)
                .clip(RoundedCornerShape(16.dp))
                // Solid dark panel on TV. The React .player-modal is translucent
                // frosted glass (rgba(255,255,255,0.22) + backdrop blur(12px)),
                // but Compose can't backdrop-blur the video (it's a SurfaceView),
                // so a translucent panel reads washed out here. Solid keeps text
                // crisp — the glass look stays in the React player-ui only.
                .background(Color(0xFF1A1A20)),
        ) {
            LazyColumn(
                state = listState,
                // Fill width but wrap height so a short menu (e.g. Audio's 3
                // tracks) stays compact; the wrapper Box's heightIn caps a long
                // menu at 70vh. fillMaxSize here would force every menu to 70vh.
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 44.dp, vertical = 36.dp),
                // 10dp base gap mirrors .player-list gap. Section headers carry
                // extra top/bottom padding to reproduce React's three-level spacing:
                // 18dp between sections, 12dp header-to-first-item, 10dp item-to-item.
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                itemsIndexed(rows) { index, row ->
                    when (row) {
                        is MenuRow.Header -> MenuSectionHeader(
                            text = row.text,
                            isFirst = index == 0,
                        )
                        is MenuRow.Item -> MenuItemRow(
                            track = row.track,
                            focused = row.trackIndex == highlight,
                            selected = row.trackIndex == selectedIndex,
                        )
                    }
                }
            }

            // 36dp fades from the panel colour to transparent at each edge, ported
            // 1:1 from the web .player-modal::before / ::after gradients.
            Box(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .height(36.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color(0xFF1A1A20), Color(0x001A1A20)),
                        ),
                    ),
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(36.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color(0x001A1A20), Color(0xFF1A1A20)),
                        ),
                    ),
            )
        }
    }
}

@Composable
private fun MenuSectionHeader(text: String, isFirst: Boolean) {
    // React spacing: sections are 18px apart (modal gap), a heading sits 12px
    // above its list (.player-menu-section gap), and items are 10px apart
    // (.player-list gap). The LazyColumn already applies a 10dp base gap, so:
    //  - top:    +8dp before non-first headers -> 10+8 = 18dp section gap
    //  - bottom: +2dp under every header       -> 10+2 = 12dp header-to-list
    Text(
        text = text.uppercase(),
        color = MutedColor,
        fontFamily = VarelaRound,
        fontSize = 13.sp,
        fontWeight = FontWeight.W700,
        letterSpacing = 1.sp,
        modifier = Modifier.padding(
            top = if (isFirst) 0.dp else 8.dp,
            bottom = 2.dp,
        ),
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
