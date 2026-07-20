import 'package:flutter/material.dart';
import '../api/tmdb.dart';
import '../theme.dart';
import 'fade_image.dart';

/// Cinematic hero that auto-rotates through featured titles on its own.
/// Backdrop + content cross-fade on each change (no zoom/slide) — ported from
/// Hero.tsx. The [media] is swapped by the parent on a timer.
class Hero extends StatelessWidget {
  final Media? media;
  const Hero({super.key, required this.media});

  @override
  Widget build(BuildContext context) {
    final height =
        MediaQuery.of(context).size.height * AppSizes.heroHeightFactor;

    if (media == null) {
      return Container(
        height: height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surface, AppColors.bg],
          ),
        ),
      );
    }

    final m = media!;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop — keyed so it remounts per title, replaying the fade-in.
          if (m.backdropPath != null)
            FadeImage(
              key: ValueKey('bg-${m.id}'),
              src: Img.backdrop(m.backdropPath),
              alignment: const Alignment(0, -0.64),
            )
          else
            const SizedBox.shrink(),
          // Scrim: left-to-right + bottom-up fade to the page background.
          const Scrim(),
          // Content, also fade-in per title.
          // Content, also fade-in per title. Left edge clears the collapsed
          // sidebar (sidebarContentPad) so the title/poster never sits under
          // the rail — matches the web `left: 92px`.
          Positioned(
            left: AppSizes.sidebarContentPad,
            bottom: 112,
            width: MediaQuery.of(context).size.width * 0.46,
            child: FadeIn(
              key: ValueKey('content-${m.id}'),
              child: _HeroContent(media: m),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays a one-shot opacity 0 → 1 fade-in on mount, matching the React
/// heroFade CSS keyframes. The parent keys this widget so it remounts (and
/// replays the animation) each time the title changes.
class FadeIn extends StatelessWidget {
  final Widget child;
  const FadeIn({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: child,
    );
  }
}

class Scrim extends StatelessWidget {
  const Scrim({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppColors.bg.withValues(alpha: 0.95),
                AppColors.bg.withValues(alpha: 0.40),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [AppColors.bg, Colors.transparent],
              stops: [0.02, 0.45],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroContent extends StatelessWidget {
  final Media media;
  const _HeroContent({required this.media});

  @override
  Widget build(BuildContext context) {
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
            letterSpacing: 0.64,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(media.mediaType == 'tv' ? 'SERIES' : 'MOVIE'),
              if (media.year.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(media.year),
              ],
              const SizedBox(width: 16),
              // Split label and value into two Texts in a center-aligned row so
              // Varela Round's lining figures (cap-height) and the mixed-case
              // "Rating" optically align instead of sharing one baseline where
              // the number rides above the lowercase. Em dash dropped — it
              // floats at the em-box center in this font, not the baseline.
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('RATING'),
                  const SizedBox(width: 6),
                  Text(media.rating == 0 ? 'N/A' : '${media.rating}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          media.overview,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFD7DEE5),
            fontSize: 16.3,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}
