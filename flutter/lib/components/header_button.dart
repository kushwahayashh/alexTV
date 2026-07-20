import 'package:flutter/material.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

/// D-pad navigable pill button for the hero header bar. Registered as a
/// focusable header item so it's reached by pressing Up from the hero.
/// Mock for now — selecting it does nothing.
class HeaderButton extends StatefulWidget {
  final String label;
  final VoidCallback? onFocused;
  final VoidCallback? onSelect;

  const HeaderButton({
    super.key,
    required this.label,
    this.onFocused,
    this.onSelect,
  });

  @override
  State<HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<HeaderButton> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: widget.onSelect,
        onFocused: widget.onFocused,
        isHeader: true,
      );
      _registered = true;
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
      child: GestureDetector(
        onTap: widget.onSelect,
        // No pill container — just an animated underline that scales in on
        // focus. Mirrors the React navbar style (an ::after underline sized to
        // the label width). A Stack sizes to the Text, and the Positioned
        // underline (left/right/bottom: 0) stretches to that width — the direct
        // analogue of React's `::after { left: 4px; right: 4px }`. This avoids
        // IntrinsicWidth, whose width is measured with the fallback font before
        // google_fonts loads; once the wider real font swaps in, the label no
        // longer fits the pre-measured box and wraps ("Sear\nch").
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Stack(
            children: [
              Padding(
                // Room for the 2px underline below the label.
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  scale: focused ? 1 : 0,
                  child: Container(height: 2, color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
