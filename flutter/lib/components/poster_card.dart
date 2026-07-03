import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../api/tmdb.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

/// A focusable poster. On focus it scales up with a white outline and scrolls
/// itself into view: centered horizontally in its rail and lifted vertically to
/// [AppSizes.scrollPaddingTop] from the top — mirroring the web scrollIntoView
/// (inline:'center') + scroll-padding-top behavior.
class PosterCard extends StatefulWidget {
  final Media media;
  final ScrollController pageController; // outer vertical scroll
  final ScrollController railController; // this rail's horizontal scroll
  final void Function(Media) onSelect;

  const PosterCard({
    super.key,
    required this.media,
    required this.pageController,
    required this.railController,
    required this.onSelect,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: () => widget.onSelect(widget.media),
        onFocused: _scrollIntoView,
      );
      _registered = true;
    }
  }

  @override
  void dispose() {
    _controller.unregister(_id);
    super.dispose();
  }

  void _scrollIntoView() {
    final ctx = _controller.keyOf(_id).currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    const dur = Duration(milliseconds: 320);
    const curve = Curves.easeOut;

    // Ask each enclosing viewport directly how far to scroll to reveal this
    // poster. getOffsetToReveal works in the viewport's OWN coordinate space,
    // so it stays correct even though the whole app is scaled by the FittedBox
    // in _DesignScaler. (The old approach mixed localToGlobal screen pixels —
    // scaled by that FittedBox — with unscaled scroll offsets, which happened
    // to match on the ~1:1 browser window but broke on the TV, where the scale
    // differs, leaving rows under-lifted and clipped.)

    // Nearest viewport = this rail's horizontal list. Center the poster in it
    // (mirrors the web's scrollIntoView inline:'center').
    final rail = widget.railController;
    final railViewport = RenderAbstractViewport.maybeOf(box);
    if (rail.hasClients && railViewport != null) {
      final target = railViewport
          .getOffsetToReveal(box, 0.5) // 0.5 => centered on the main axis
          .offset
          .clamp(rail.position.minScrollExtent, rail.position.maxScrollExtent);
      rail.animateTo(target, duration: dur, curve: curve);
    }

    // Outer viewport = the vertical page. Lift the poster's top to
    // scrollPaddingTop from the top (web: block:'start' + scroll-padding-top).
    final page = widget.pageController;
    final pageViewport = railViewport == null
        ? null
        : RenderAbstractViewport.maybeOf(railViewport.parent);
    if (page.hasClients && pageViewport != null) {
      final revealTop = pageViewport.getOffsetToReveal(box, 0.0).offset;
      final target = (revealTop - AppSizes.scrollPaddingTop)
          .clamp(page.position.minScrollExtent, page.position.maxScrollExtent);
      page.animateTo(target, duration: dur, curve: curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Depend on the controller so this rebuilds when focus changes.
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(_id);
    final media = widget.media;

    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: GestureDetector(
        onTap: () => widget.onSelect(media),
        child: AnimatedScale(
          scale: focused ? AppSizes.posterFocusScale : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Container(
            width: AppSizes.posterW,
            height: AppSizes.posterH,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: focused
                  ? const [
                      BoxShadow(
                        color: Color(0xB3000000), // rgba(0,0,0,0.7)
                        blurRadius: 34,
                        offset: Offset(0, 12),
                      ),
                    ]
                  : const [],
            ),
            // foregroundDecoration draws the outline on top without insetting
            // the image (avoids a layout jump on focus).
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              border: Border.all(
                color: focused ? AppColors.focus : Colors.transparent,
                width: 3,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: media.posterPath != null
                ? Image.network(
                    Img.poster(media.posterPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _placeholder(media.title),
                  )
                : _placeholder(media.title),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(String title) => Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ),
      );
}
