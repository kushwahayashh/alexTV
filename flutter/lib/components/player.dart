import 'dart:ui';
import 'package:flutter/material.dart';
import '../api/stream.dart';
import '../api/tmdb.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

enum _Phase { loading, files, links, playing, error }

/// Three-step playback modal (video player not yet implemented):
///   1. Resolve movie → list video files
///   2. Pick a file → fetch stream links (quality options)
///   3. Pick a link → (TODO: play in video player)
///
/// Creates its own FocusController so D-pad keys are swallowed here and never
/// reach the Details page's key handler while the modal is open. Back/Escape
/// navigates within the player (links→files) or closes it.
class Player extends StatefulWidget {
  final Media media;
  final VoidCallback onClose;

  const Player({super.key, required this.media, required this.onClose});

  @override
  State<Player> createState() => _PlayerState();
}

class _PlayerState extends State<Player> {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  _Phase _phase = _Phase.loading;
  List<VideoFile> _files = [];
  List<StreamLink> _links = [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _resolve();
    // Take primary focus from Details so our key handler runs first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardNode.requestFocus();
    });
  }

  Future<void> _resolve() async {
    try {
      final files = await resolveMovie(widget.media.title, widget.media.year);
      if (!mounted) return;
      setState(() {
        _files = files;
        _phase = files.isNotEmpty ? _Phase.files : _Phase.error;
        if (files.isEmpty) _error = 'No video files found.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  void _handleBack() {
    if (_phase == _Phase.links) {
      setState(() => _phase = _Phase.files);
    } else {
      widget.onClose();
    }
  }

  void _pickFile(VideoFile file) async {
    setState(() => _phase = _Phase.loading);
    try {
      final links = await getLinks(file.fid);
      if (!mounted) return;
      setState(() {
        _links = links;
        _phase = links.isNotEmpty ? _Phase.links : _Phase.error;
        if (links.isEmpty) _error = 'No stream links for this file.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  void _pickLink(StreamLink link) {
    // TODO: wire up the video player.
    debugPrint('PLAY LINK: ${link.proxiedUrl}');
    setState(() => _phase = _Phase.playing);
  }

  @override
  void dispose() {
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
        onKeyEvent: (_, event) =>
            _focus.handleKey(event, _handleBack, null),
        child: Stack(
  children: [
          // Dim + blur overlay.
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.black.withValues(alpha: 0.6)),
            ),
          ),
          Center(child: _buildModal()),
        ],
      ),
    ),
    );
  }

  Widget _buildModal() {
    return switch (_phase) {
      _Phase.loading => const _LoadingModal(),
      _Phase.files => _PickerModal(
          key: const ValueKey('files'),
          items: [
            for (final f in _files)
              _PickerData(
                label: f.fileName,
                meta: '${f.resLabel} · ${f.fileSize}',
                onSelect: () => _pickFile(f),
              ),
          ],
        ),
      _Phase.links => _PickerModal(
          key: const ValueKey('links'),
          items: [
            for (final l in _links)
              _PickerData(
                label: l.quality,
                meta: '${l.ext} · ${l.speed}',
                onSelect: () => _pickLink(l),
              ),
          ],
        ),
      _Phase.playing => _PlayingPlaceholder(onClose: widget.onClose),
      _Phase.error => _ErrorModal(error: _error, onClose: widget.onClose),
    };
  }
}

/* ---------- Data holder for picker items ---------- */
class _PickerData {
  final String label;
  final String meta;
  final VoidCallback onSelect;
  const _PickerData(
      {required this.label, required this.meta, required this.onSelect});
}

/* ---------- Focusable list item ---------- */
class _PlayerItem extends StatefulWidget {
  final String label;
  final String meta;
  final VoidCallback onSelect;
  final bool autoFocus;

  const _PlayerItem({
    required this.label,
    required this.meta,
    required this.onSelect,
    this.autoFocus = false,
  });

  @override
  State<_PlayerItem> createState() => _PlayerItemState();
}

class _PlayerItemState extends State<_PlayerItem> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(onSelect: widget.onSelect);
      _registered = true;
      if (widget.autoFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _controller.requestFocus(_id);
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.unregister(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(_id);

    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: AnimatedScale(
        scale: focused ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.focus
                : Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: focused ? AppColors.bg : AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                widget.meta,
                style: TextStyle(
                  fontSize: 13.6, // 0.85rem
                  fontWeight: FontWeight.w600,
                  color: focused
                      ? AppColors.bg.withValues(alpha: 0.7)
                      : AppColors.text.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- Modal shell (blurred glass card) ---------- */
Widget _modalShell(BuildContext context, {required Widget child}) {
  return ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: 620,
      maxHeight: MediaQuery.of(context).size.height * 0.8,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 36),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

/* ---------- Loading modal (skeleton) ---------- */
class _LoadingModal extends StatelessWidget {
  const _LoadingModal();

  @override
  Widget build(BuildContext context) {
    return _modalShell(context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: const _SkeletonPill(),
            ),
        ],
      ),
    );
  }
}

class _SkeletonPill extends StatefulWidget {
  const _SkeletonPill();

  @override
  State<_SkeletonPill> createState() => _SkeletonPillState();
}

class _SkeletonPillState extends State<_SkeletonPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        // Shimmer sweep: 0 → 1 across the pill width.
        final t = _ctrl.value;
        return Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(0 + t * 2, 0),
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.06),
              ],
            ),
          ),
        );
      },
    );
  }
}

/* ---------- Picker modal (files / quality) ---------- */
class _PickerModal extends StatelessWidget {
  final List<_PickerData> items;
  const _PickerModal({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return _modalShell(context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: _PlayerItem(
                label: items[i].label,
                meta: items[i].meta,
                onSelect: items[i].onSelect,
                autoFocus: i == 0,
              ),
            ),
        ],
      ),
    );
  }
}

/* ---------- Error modal ---------- */
class _ErrorModal extends StatefulWidget {
  final String error;
  final VoidCallback onClose;
  const _ErrorModal({required this.error, required this.onClose});

  @override
  State<_ErrorModal> createState() => _ErrorModalState();
}

class _ErrorModalState extends State<_ErrorModal> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(onSelect: widget.onClose);
      _registered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.requestFocus(_id);
      });
    }
  }

  @override
  void dispose() {
    _controller.unregister(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(_id);

    return _modalShell(context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              widget.error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ),
          KeyedSubtree(
            key: _controller.keyOf(_id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? AppColors.focus
                    : Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Back',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: focused ? AppColors.bg : AppColors.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ---------- Playing placeholder (video player not yet implemented) ---------- */
class _PlayingPlaceholder extends StatelessWidget {
  final VoidCallback onClose;
  const _PlayingPlaceholder({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return _modalShell(context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Video player not implemented yet.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onClose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.focus,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Back',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.bg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
