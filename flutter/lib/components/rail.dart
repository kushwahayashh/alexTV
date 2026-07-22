import 'package:flutter/material.dart';
import '../api/tmdb.dart' as api;
import '../theme.dart';
import 'poster_card.dart';

/// A titled horizontal row of posters, ported from Rail.tsx. Owns its own
/// horizontal ScrollController so focused posters can center themselves.
class Rail extends StatefulWidget {
  final api.Rail rail;
  final ScrollController pageController;
  final void Function(api.Media) onSelect;

  const Rail({
    super.key,
    required this.rail,
    required this.pageController,
    required this.onSelect,
  });

  @override
  State<Rail> createState() => _RailState();
}

class _RailState extends State<Rail> {
  final _railController = ScrollController();

  @override
  void dispose() {
    _railController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSizes.pagePadding,
            bottom: 28,
          ),
          child: Text(
            widget.rail.title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ),
        // Row is exactly poster-height (matches the web, where the track's
        // vertical padding is cancelled by a negative margin). Clip.none lets
        // the focused poster's scale-up overflow without being clipped.
        //
        // ShaderMask fades posters out as they scroll under the collapsed
        // sidebar instead of getting sliced at a hard vertical cut. The fade
        // must be fully opaque by the collapsed sidebar's right edge so a
        // resting/focused first poster is never washed: the rail track starts
        // at screen x=44 (sidebarContentPad 92 − pagePadding 48) and the
        // collapsed sidebar ends at screen x=76, so in rail-local coordinates
        // the opaque point lands at 76 − 44 = 32px. BlendMode.dstIn uses the
        // shader's alpha as the child's alpha — transparent areas hide it.
        SizedBox(
          height: AppSizes.posterH,
          child: ShaderMask(
            shaderCallback: (bounds) {
              const fadeEnd =
                  AppSizes.sidebarCollapsedWidth -
                  (AppSizes.sidebarContentPad - AppSizes.pagePadding);
              final fade = fadeEnd / bounds.width;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.transparent, Colors.black, Colors.black],
                stops: [0.0, fade, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            // Clip the ListView's horizontal overflow to the rail viewport
            // (mirrors CSS `overflow-x: auto` on `.rail__track`) while leaving
            // the vertical axis open (`overflow-y: visible`) so a focused
            // poster's scale-up and drop shadow are never sliced. Without this,
            // Clip.none leaves the horizontal overflow unclipped, so the region
            // the ShaderMask composites changes frame-to-frame as posters
            // scroll — which makes the left-edge fade flicker.
            child: ClipRect(
              clipper: const _RailHClip(),
              child: ListView.separated(
                controller: _railController,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.pagePadding,
                ),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.rail.items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSizes.posterGap),
                itemBuilder: (context, i) {
                  final media = widget.rail.items[i];
                  return PosterCard(
                    media: media,
                    pageController: widget.pageController,
                    railController: _railController,
                    onSelect: widget.onSelect,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Clips only the horizontal axis to the rail viewport, leaving the vertical
/// axis effectively unclipped. Mirrors `.rail__track { overflow-x: auto;
/// overflow-y: visible }`: posters that scroll off the sides are clipped so the
/// ShaderMask fade stays stable, but a focused poster's scale-up and drop
/// shadow can still overflow above/below without being sliced.
class _RailHClip extends CustomClipper<Rect> {
  const _RailHClip();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height, size.width, size.height * 2);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
