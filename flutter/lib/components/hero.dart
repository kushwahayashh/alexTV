import 'package:flutter/material.dart';
import '../api/tmdb.dart';
import '../theme.dart';

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
            colors: [Color(0xFF1A2430), AppColors.bg],
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
          _FadeIn(
            key: ValueKey('bg-${m.id}'),
            child: m.backdropPath != null
                ? SizedBox.expand(
                    child: Image.network(
                      Img.backdrop(m.backdropPath),
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.64),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          // Scrim: left-to-right + bottom-up fade to the page background.
          const _Scrim(),
          // Content, also fade-in per title.
          Positioned(
            left: AppSizes.pagePadding,
            bottom: 112,
            width: MediaQuery.of(context).size.width * 0.46,
            child: _FadeIn(
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
class _FadeIn extends StatelessWidget {
  final Widget child;
  const _FadeIn({super.key, required this.child});

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

class _Scrim extends StatelessWidget {
  const _Scrim();

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
              Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 2)),
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
