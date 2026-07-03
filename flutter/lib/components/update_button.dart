import 'package:flutter/material.dart';
import '../focus/focus_engine.dart';
import 'header_button.dart';
import '../update/updater.dart';

/// Update header button. Uses [HeaderButton] for the UI and wires up the
/// real update flow (download APK + launch installer). While downloading,
/// its label reads "Downloading…" and it ignores further presses.
class UpdateButton extends StatefulWidget {
  final VoidCallback? onFocused;

  const UpdateButton({super.key, this.onFocused});

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  bool _downloading = false;

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
    return HeaderButton(
      label: _downloading ? 'Downloading…' : 'Update',
      onFocused: widget.onFocused,
      onSelect: _update,
    );
  }
}
