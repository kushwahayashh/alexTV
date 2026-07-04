import 'package:flutter/material.dart';

/// Image that stays invisible until fully loaded, then fades in smoothly.
/// Mirrors the React FadeImage component — avoids the "half-loaded" flash.
class FadeImage extends StatefulWidget {
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
  State<FadeImage> createState() => _FadeImageState();
}

class _FadeImageState extends State<FadeImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.src,
      fit: widget.fit,
      alignment: widget.alignment,
      errorBuilder: (_, _, _) =>
          widget.errorWidget ?? const SizedBox.shrink(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          // Image is fully loaded.
          if (!_loaded) {
            _loaded = true;
            _controller.forward();
          }
          return FadeTransition(opacity: _controller, child: child);
        }
        // Still loading — show nothing.
        return const SizedBox.shrink();
      },
    );
  }
}
