import 'package:flutter/material.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';
import '../update/updater.dart';

/// A text button in the top-right corner. Registered as the focus "header": it
/// isn't part of the poster grid; you reach it by pressing Up from the hero and
/// leave it by pressing Down. Selecting it downloads the latest release APK and
/// launches the system installer. While downloading, its label reads
/// "Downloading…" and it ignores further presses.
class UpdateButton extends StatefulWidget {
  /// Called when the button gains focus — used to scroll the hero back into
  /// view so the button (which lives on the hero) is actually visible.
  final VoidCallback? onFocused;

  const UpdateButton({super.key, this.onFocused});

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;
  bool _downloading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: _update,
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

  Future<void> _update() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await Updater.downloadAndInstall();
    } catch (e) {
      debugPrint('Update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update failed. Check the connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(_id);

    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: GestureDetector(
        onTap: _update,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: focused
                ? AppColors.focus
                : Colors.white.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _downloading ? 'Downloading…' : 'Update',
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
