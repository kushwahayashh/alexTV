import 'package:flutter/material.dart';

/// Image that stays invisible until fully loaded, then fades in smoothly.
/// Mirrors the React FadeImage component — avoids the "half-loaded" flash.
class FadeImage extends StatelessWidget {
  final String src;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? errorWidget;

  const FadeImage({
    super.key,
    required this.src,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      src,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, _, _) =>
          errorWidget ?? const SizedBox.shrink(),
      // frameBuilder is Flutter's official API for image fade-in. `frame`
      // is null while loading, non-null when decoded and ready to paint.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame != null ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}
