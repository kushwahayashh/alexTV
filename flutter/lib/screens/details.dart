import 'package:flutter/material.dart';
import '../api/tmdb.dart';
import '../components/hero.dart' show FadeIn, Scrim;
import '../components/fade_image.dart';
import '../components/player.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

/// Fullscreen movie/series details page. Mirrors the hero aesthetic (backdrop,
/// scrim, left-aligned content) and adds Play + Watch Later action buttons
/// styled like the navbar pills. Focus seeds on the Play button on mount so
/// the user can immediately press Enter to play.
class Details extends StatefulWidget {
  final Media media;
  final VoidCallback onBack;

  const Details({super.key, required this.media, required this.onBack});

  @override
  State<Details> createState() => _DetailsState();
}

class _DetailsState extends State<Details> {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  bool _showPlayer = false;
  late final int _playId;
  late final int _watchLaterId;

  @override
  void initState() {
    super.initState();
    _playId = _focus.register(onSelect: _openPlayer);
    _watchLaterId = _focus.register(
      onSelect: () => debugPrint('WATCH LATER ${widget.media.title}'),
    );
    // Seed focus on the Play button after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus(_playId);
    });
  }

  @override
  void dispose() {
    _focus.unregister(_playId);
    _focus.unregister(_watchLaterId);
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openPlayer() => setState(() => _showPlayer = true);

  void _closePlayer() {
    setState(() => _showPlayer = false);
    // Restore focus to the Play button after the player unmounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardNode.requestFocus();
      _focus.requestFocus(_playId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onBack();
        },
        child: FocusScopeProvider(
          controller: _focus,
          child: Focus(
            focusNode: _keyboardNode,
            autofocus: true,
            onKeyEvent: (_, event) =>
                _focus.handleKey(event, widget.onBack, null),
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Backdrop — keyed so it remounts per title, replaying the fade-in.
                  if (media.backdropPath != null)
                    FadeImage(
                      key: ValueKey('bg-${media.id}'),
                      src: Img.backdrop(media.backdropPath),
                      alignment: const Alignment(0, -0.64),
                    ),
                  // Scrim: same gradient stack as the hero.
                  const Scrim(),
                  // Content, also fade-in per title.
                  Positioned(
                    left: AppSizes.pagePadding,
                    bottom: 120,
                    width: MediaQuery.of(context).size.width * 0.50,
                    child: FadeIn(
                      key: ValueKey('content-${media.id}'),
                      child: _DetailsContent(
                        media: media,
                        playId: _playId,
                        watchLaterId: _watchLaterId,
                      ),
                    ),
                  ),
                  // Player overlay.
                  if (_showPlayer) Player(media: media, onClose: _closePlayer),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Content column (title, facts, overview, action buttons). StatelessWidget —
/// registration is handled by the parent [_DetailsState].
class _DetailsContent extends StatelessWidget {
  final Media media;
  final int playId;
  final int watchLaterId;

  const _DetailsContent({
    required this.media,
    required this.playId,
    required this.watchLaterId,
  });

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          media.title,
          style: const TextStyle(
            fontSize: 57.6, // 3.6rem
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            shadows: [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 18,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DefaultTextStyle.merge(
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(media.mediaType == 'tv' ? 'Series' : 'Movie'),
              if (media.year.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(media.year),
              ],
              const SizedBox(width: 16),
              Text('★ ${media.rating == 0 ? '—' : media.rating}'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          media.overview,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFD7DEE5),
            fontSize: 16.3,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailsButton(
              label: 'Play',
              id: playId,
              focused: controller.isFocused(playId),
            ),
            const SizedBox(width: 14),
            _DetailsButton(
              label: 'Watch Later',
              id: watchLaterId,
              focused: controller.isFocused(watchLaterId),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pill-shaped action button — same styling as HeaderButton but not a header
/// focusable (reached via normal D-pad traversal, not the Up-from-hero path).
class _DetailsButton extends StatelessWidget {
  final String label;
  final int id;
  final bool focused;

  const _DetailsButton({
    required this.label,
    required this.id,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    return KeyedSubtree(
      key: controller.keyOf(id),
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
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: focused ? AppColors.bg : AppColors.text,
          ),
        ),
      ),
    );
  }
}
