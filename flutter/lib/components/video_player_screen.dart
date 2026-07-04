import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../focus/focus_engine.dart';
import '../surface_video_player.dart';
import '../theme.dart';

/// Fullscreen video player with custom TV controls overlay.
///
/// Layout (mirrors the React player-ui 1:1):
///   Top bar:    [title]
///   Bottom bar: [seekbar]
///                [current time           total time]
///                [Subtitles] [Audio]  (centered)
///
/// Focus model (D-pad):
///   Row 0: [seek]
///   Row 1: [subtitles] [audio]
///
///   - Up/Down moves between rows (spatial engine).
///   - Left/Right on the seekbar seeks 10s (intercepted, no focus move).
///   - Left/Right on subtitles/audio moves between them.
///   - Enter on seekbar toggles play/pause.
///   - Enter on Subtitles/Audio opens a mock menu.
///   - Back/Escape closes an open menu first, then closes the player.
///
/// Controls auto-hide after 4s of inactivity; any key resurfaces them.
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
  SurfaceVideoPlayerController? _nativeController;
  bool _initialized = false;
  bool _isPlaying = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _stateSub;
  Timer? _positionTimer;

  // Auto-hide
  bool _controlsVisible = true;
  Timer? _hideTimer;
  static const _hideDelay = Duration(seconds: 4);

  // Mock menus
  bool _subtitlesOpen = false;
  bool _audioOpen = false;

  // Focusable IDs
  late final int _seekId;
  late final int _subId;
  late final int _audioId;

  Timer? _mockTimer;

  static const _seekStep = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    _focus = FocusController();
    _registerFocusables();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardNode.requestFocus();
        _focus.requestFocus(_seekId);
      }
    });
    _bumpActivity();

    if (kIsWeb) {
      // Web fallback: no ExoPlayer, mock playback so controls are visible.
      _duration = const Duration(seconds: 7695); // 2:08:15 placeholder
      _position = Duration.zero;
      _isPlaying = true;
      _initialized = true;
      _startMockTimer();
    }
  }

  void _startMockTimer() {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isPlaying) return;
      setState(() {
        _position = _position >= _duration ? _duration : _position + const Duration(seconds: 1);
      });
    });
  }

  void _registerFocusables() {
    _seekId = _focus.register(onSelect: _togglePlay);
    _subId = _focus.register(onSelect: () {
      setState(() {
        _subtitlesOpen = !_subtitlesOpen;
        _audioOpen = false;
      });
    });
    _audioId = _focus.register(onSelect: () {
      setState(() {
        _audioOpen = !_audioOpen;
        _subtitlesOpen = false;
      });
    });
  }

  void _bumpActivity() {
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) {
        setState(() {
          _controlsVisible = false;
          _subtitlesOpen = false;
          _audioOpen = false;
        });
      }
    });
  }

  void _onControllerCreated(SurfaceVideoPlayerController controller) {
    _nativeController = controller;

    controller.ready.then((_) {
      if (!mounted) return;
      _duration = controller.duration;
      _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        if (!mounted) {
          _positionTimer?.cancel();
          return;
        }
        _position = await controller.getPosition();
        setState(() {});
      });
      setState(() => _initialized = true);
    }).catchError((e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load video: $e');
    });

    _stateSub = controller.stateStream.listen((state) {
      if (!mounted) return;
      switch (state) {
        case PlayerState.playing:
          setState(() => _isPlaying = true);
        case PlayerState.paused:
          setState(() => _isPlaying = false);
        case PlayerState.error:
          setState(() => _error = controller.error ?? 'Playback error');
        default:
          break;
      }
    });
  }

  void _togglePlay() async {
    if (kIsWeb) {
      setState(() => _isPlaying = !_isPlaying);
      return;
    }
    final c = _nativeController;
    if (c == null || !_initialized) return;
    if (_isPlaying) {
      await c.pause();
    } else {
      await c.play();
    }
  }

  void _seekBy(Duration delta) async {
    if (kIsWeb) {
      final pos = _position + delta;
      setState(() {
        _position = pos < Duration.zero
            ? Duration.zero
            : pos > _duration
                ? _duration
                : pos;
      });
      return;
    }
    final c = _nativeController;
    if (c == null || !_initialized) return;
    final pos = (await c.getPosition()) + delta;
    final clamped = pos < Duration.zero
        ? Duration.zero
        : pos > _duration
            ? _duration
            : pos;
    await c.seekTo(clamped);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Any key bumps activity (resurfaces controls).
    _bumpActivity();

    final focused = _focus.focusId;

    // Seekbar intercepts left/right for seeking.
    if (focused == _seekId) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _seekBy(-_seekStep);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _seekBy(_seekStep);
        return KeyEventResult.handled;
      }
    }

    // Back/Escape: close open menu first, then close player.
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (_subtitlesOpen) {
        setState(() => _subtitlesOpen = false);
        return KeyEventResult.handled;
      }
      if (_audioOpen) {
        setState(() => _audioOpen = false);
        return KeyEventResult.handled;
      }
      widget.onClose();
      return KeyEventResult.handled;
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
    _hideTimer?.cancel();
    _mockTimer?.cancel();
    _positionTimer?.cancel();
    _stateSub?.cancel();
    _nativeController?.dispose();
    _focus.unregister(_seekId);
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
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // Native SurfaceView video player (Android only)
                      if (!kIsWeb)
                        SurfaceVideoPlayerController.view(
                          url: widget.url,
                          autoPlay: true,
                          onCreated: _onControllerCreated,
                        ),
                      // Center paused indicator
                      if (_initialized && !_isPlaying)
                        const Center(
                          child: _PausedIndicator(),
                        ),
                      // Controls overlay (only after initialized)
                      if (_initialized)
                        Builder(builder: _buildControls),
                      // Loading spinner
                      if (!_initialized)
                        const Center(
                          child: CircularProgressIndicator(color: AppColors.text),
                        ),
                    ],
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
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return IgnorePointer(
      ignoring: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top bar (title only)
          AnimatedPositioned(
            top: 0,
            left: 0,
            right: 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildTopBar(),
            ),
          ),
          // Bottom bar (seekbar + timestamps + subtitle/audio)
          AnimatedPositioned(
            bottom: 0,
            left: 0,
            right: 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: _buildBottomBar(progress, controller),
            ),
          ),
          // Subtitles menu (mock)
          if (_subtitlesOpen) _buildMenu('Subtitles', ['Off', 'English', 'Spanish', 'French']),
          // Audio menu (mock)
          if (_audioOpen) _buildMenu('Audio', ['English 5.1', 'English Stereo', 'Spanish', 'Director Commentary']),
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

  Widget _buildBottomBar(double progress, FocusController controller) {
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
          // Seekbar
          _buildSeekBar(progress, controller),
          const SizedBox(height: 8),
          // Timestamps below seekbar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _timeText(_fmtDuration(_position)),
              _timeText(_fmtDuration(_duration)),
            ],
          ),
          const SizedBox(height: 20),
          // Subtitles + Audio centered
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPillButton('Subtitles', _subId, controller),
              const SizedBox(width: 14),
              _buildPillButton('Audio', _audioId, controller),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xD9FFFFFF),
        fontFeatures: [FontFeature.tabularFigures()],
        shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
      ),
    );
  }

  Widget _buildSeekBar(double progress, FocusController controller) {
    final focused = controller.isFocused(_seekId);
    final pct = (progress * 100).clamp(0.0, 100.0);

    return KeyedSubtree(
      key: controller.keyOf(_seekId),
      child: GestureDetector(
        onTap: () => _focus.requestFocus(_seekId),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: focused ? 10 : 8,
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
              // Vertical playhead line (only when focused)
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
                          width: 6,
                          height: 16,
                          decoration: BoxDecoration(
                            color: AppColors.focus,
                            borderRadius: BorderRadius.circular(2),
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

  Widget _buildMenu(String title, List<String> items) {
    return Positioned(
      bottom: 140,
      right: 40,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 260,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xEB141418),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 40,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, bottom: 10),
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08 * 12.8,
                    color: AppColors.muted,
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              for (int i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      if (i == 0)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.check, size: 16, color: AppColors.accent),
                        ),
                      Text(
                        items[i],
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w600,
                          color: i == 0 ? AppColors.accent : AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Center play icon shown when paused.
class _PausedIndicator extends StatelessWidget {
  const _PausedIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(Icons.play_arrow, size: 48, color: AppColors.text),
      ),
    );
  }
}
