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
        // ShaderMask replicates the CSS `mask-image: linear-gradient(to right,
        // transparent 0, #000 96px)` on `.rail__track`: the left 96px fade from
        // transparent to opaque so posters dissolve as they scroll under the
        // collapsed sidebar instead of getting sliced at a hard vertical cut.
        // BlendMode.dstIn uses the shader's alpha as the child's alpha —
        // transparent areas of the gradient make the child invisible.
        SizedBox(
          height: AppSizes.posterH,
          child: ShaderMask(
            shaderCallback: (bounds) {
              final fade = AppSizes.sidebarFadeWidth / bounds.width;
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.transparent, Colors.black, Colors.black],
                stops: [0.0, fade, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
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
      ],
    );
  }
}
