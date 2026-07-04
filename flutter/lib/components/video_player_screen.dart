import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

/// Fullscreen video player with custom TV controls overlay:
///   - Top bar: video title
///   - Bottom bar: focusable seekbar (left/right seeks when focused),
///     Play/Pause pill (left), Subtitles + Audio pills (right, mock)
///
/// Uses ExoPlayer on Android via the video_player package.
/// Creates its own FocusController so D-pad keys are handled here.
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback onClose;

  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.title,
    required this.onClose,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final FocusController _focus;
  final _keyboardNode = FocusNode();
  VideoPlayerController? _vpc;
  bool _initialized = false;
  bool _isPlaying = false;
  String? _error;

  // Focusable IDs
  late final int _seekId;
  late final int _playId;
  late final int _subId;
  late final int _audioId;

  static const _seekStep = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _focus = FocusController();
    _registerFocusables();
    _initVideo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardNode.requestFocus();
    });
  }

  void _initVideo() {
    final url = widget.url;
    debugPrint('[VideoPlayer] initializing with URL: $url');
    _vpc = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    _vpc!.initialize().then((_) {
      if (!mounted) return;
      debugPrint('[VideoPlayer] initialized, size=${_vpc!.value.size}');
      _vpc!.addListener(_onVideoUpdate);
      _vpc!.play();
      setState(() => _initialized = true);
    }).catchError((e) {
      if (!mounted) return;
      debugPrint('[VideoPlayer] init error: $e');
      setState(() => _error = 'Failed to load video: $e');
    });
  }

  void _registerFocusables() {
    _seekId = _focus.register(onSelect: () {});
    _playId = _focus.register(onSelect: _togglePlay);
    _subId = _focus.register(onSelect: () {});
    _audioId = _focus.register(onSelect: () {});
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final playing = _vpc?.value.isPlaying ?? false;
    if (playing != _isPlaying) {
      setState(() => _isPlaying = playing);
    }
  }

  void _togglePlay() {
    final v = _vpc;
    if (v == null || !v.value.isInitialized) return;
    if (v.value.isPlaying) {
      v.pause();
    } else {
      v.play();
    }
  }

  void _seekBy(Duration delta) {
    final v = _vpc;
    if (v == null || !v.value.isInitialized) return;
    final pos = v.value.position + delta;
    final dur = v.value.duration;
    final clamped = pos < Duration.zero
        ? Duration.zero
        : pos > dur
            ? dur
            : pos;
    v.seekTo(clamped);
  }

  /// Intercept arrow keys when the seekbar is focused so left/right seeks
  /// instead of moving focus to another control.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // If seekbar is focused, intercept left/right to seek.
    final focused = _focus.focusId;
    if (focused == _seekId && (event is KeyDownEvent || event is KeyRepeatEvent)) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _seekBy(-_seekStep);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _seekBy(_seekStep);
        return KeyEventResult.handled;
      }
    }
    return _focus.handleKey(event, widget.onClose, null);
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _vpc?.removeListener(_onVideoUpdate);
    _vpc?.dispose();
    _focus.unregister(_seekId);
    _focus.unregister(_playId);
    _focus.unregister(_subId);
    _focus.unregister(_audioId);
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScopeProvider(
      controller: _focus,
      child: Focus(
        focusNode: _keyboardNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: _error != null
                ? _buildError()
                : _initialized && _vpc != null && _vpc!.value.isInitialized
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _vpc!.value.size.width,
                              height: _vpc!.value.size.height,
                              child: VideoPlayer(_vpc!),
                            ),
                          ),
                          // Controls overlay
                          Builder(builder: _buildControls),
                        ],
                      )
                    // Loading
                    : const Center(
                        child: CircularProgressIndicator(color: AppColors.text),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.muted),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Press Back to return',
            style: TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final pos = _vpc?.value.position ?? Duration.zero;
    final dur = _vpc?.value.duration ?? Duration.zero;
    final progress = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final seekFocused = controller.isFocused(_seekId);

    return IgnorePointer(
      ignoring: false, // allow focus engine to work
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top bar: title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),
          // Bottom bar: seek + controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(progress, pos, dur, seekFocused, controller),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xB3000000), Colors.transparent],
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            shadows: [
              Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    double progress,
    Duration pos,
    Duration dur,
    bool seekFocused,
    FocusController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xBF000000), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar row
          Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  _fmtDuration(pos),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xD9FFFFFF),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildSeekBar(progress, seekFocused, controller)),
              const SizedBox(width: 16),
              SizedBox(
                width: 56,
                child: Text(
                  _fmtDuration(dur),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.2,
                    fontWeight: FontWeight.w600,
                    color: Color(0xD9FFFFFF),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Controls row
          Row(
            children: [
              _buildPillButton('Play', _playId, controller),
              const Spacer(),
              _buildPillButton('Subtitles', _subId, controller),
              const SizedBox(width: 14),
              _buildPillButton('Audio', _audioId, controller),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeekBar(double progress, bool focused, FocusController controller) {
    final pct = (progress * 100).clamp(0.0, 100.0);
    return KeyedSubtree(
      key: controller.keyOf(_seekId),
      child: GestureDetector(
        onTap: () => _focus.requestFocus(_seekId),
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: focused
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.22),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Fill
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              // Knob (only when focused)
              if (focused)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: pct / 100,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.focus,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x80000000),
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPillButton(String label, int id, FocusController controller) {
    final focused = controller.isFocused(id);
    return KeyedSubtree(
      key: controller.keyOf(id),
      child: AnimatedScale(
        scale: focused ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.focus
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: focused ? AppColors.bg : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
