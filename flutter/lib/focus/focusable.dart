/// Shared wiring for single-id focusable items (the [FocusController] client
/// side). The engine lives in [focus_engine.dart]; this file removes the
/// register-once / unregister / focus-query boilerplate every focusable State
/// otherwise repeats, plus the vertical scroll-into-view logic that the list
/// rows share.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'focus_engine.dart';

/// Standard single-id focusable lifecycle. Mix into a [State] to get the
/// register-once / unregister / focus-query wiring; the subclass supplies just
/// its own [register] call via [registerFocusable].
///
/// Registration runs in [didChangeDependencies] (not [initState]) because it
/// needs the inherited [FocusScopeProvider], reachable only once dependencies
/// resolve. It runs exactly once, guarded internally.
mixin FocusableState<T extends StatefulWidget> on State<T> {
  late FocusController _focusController;
  late int _focusId;
  bool _registered = false;

  /// Build this widget's [FocusController.register] call and return the id.
  /// Called once, after the controller is resolved. Keeping the whole call in
  /// the subclass leaves all per-site variation (onSelect/onFocused/isHeader/
  /// active) local instead of fanning it out across overridable getters.
  int registerFocusable(FocusController controller);

  /// Runs once, immediately after registration. Override for post-register
  /// actions (e.g. a deferred [FocusController.requestFocus]). Default: no-op.
  void onRegistered() {}

  /// Non-subscribing controller — valid after [didChangeDependencies].
  FocusController get focusController => _focusController;
  int get focusId => _focusId;
  GlobalKey get focusKey => _focusController.keyOf(_focusId);

  /// Subscribing focus query — call from [build] so the widget rebuilds when
  /// focus moves. (Reads [FocusScopeProvider.of], which registers a dependency.)
  bool get isFocused => FocusScopeProvider.of(context).isFocused(_focusId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _focusController = FocusScopeProvider.read(context);
      _focusId = registerFocusable(_focusController);
      _registered = true;
      onRegistered();
    }
  }

  @override
  void dispose() {
    if (_registered) _focusController.unregister(_focusId);
    super.dispose();
  }
}

/// Scroll a single outer vertical viewport so the focusable identified by [key]
/// is lifted to [lift] px below the viewport top. Shared by the search /
/// library / episode rows, whose only difference was the [lift] constant.
///
/// The [ScrollPosition.hasContentDimensions] guard is kept for every caller:
/// [ScrollController.hasClients] can be true before the first layout sets the
/// scroll dimensions, at which point [ScrollController.animateTo] would read a
/// null minScrollExtent and crash.
void verticalScrollIntoView({
  required GlobalKey key,
  required ScrollController page,
  required double lift,
  Duration duration = const Duration(milliseconds: 320),
  Curve curve = Curves.easeOut,
}) {
  final ctx = key.currentContext;
  if (ctx == null) return;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return;

  final viewport = RenderAbstractViewport.maybeOf(box);
  if (!page.hasClients || viewport == null) return;
  if (!page.position.hasContentDimensions) return;

  final revealTop = viewport.getOffsetToReveal(box, 0.0).offset;
  final target = (revealTop - lift).clamp(
    page.position.minScrollExtent,
    page.position.maxScrollExtent,
  );
  page.animateTo(target, duration: duration, curve: curve);
}
