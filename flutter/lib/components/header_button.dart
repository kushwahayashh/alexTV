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
            widget.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: focused ? AppColors.bg : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
