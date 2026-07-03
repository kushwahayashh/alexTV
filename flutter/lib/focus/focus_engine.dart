/// Spatial D-pad focus engine — Dart port of the React prototype's FocusEngine.
///
/// Every focusable registers a GlobalKey here. On an arrow key we read the live
/// geometry of each registered node (RenderBox global rect) and pick the best
/// candidate in the pressed direction using a distance + alignment cost. This
/// mirrors the web engine 1:1 so behavior (and the mental model) is identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum Direction { up, down, left, right }

class _Entry {
  final int id;
  final GlobalKey key;
  final VoidCallback? onSelect;
  final VoidCallback? onFocused; // scrolls itself into view, like scrollIntoView
  _Entry(this.id, this.key, this.onSelect, this.onFocused);

  Rect? get rect {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final tl = box.localToGlobal(Offset.zero);
    return tl & box.size;
  }
}

class FocusController extends ChangeNotifier {
  final _entries = <int, _Entry>{};
  int? _focusId;
  int _counter = 0;

  int? get focusId => _focusId;
  bool isFocused(int id) => _focusId == id;

  int register({VoidCallback? onSelect, VoidCallback? onFocused}) {
    final id = _counter++;
    _entries[id] = _Entry(id, GlobalKey(), onSelect, onFocused);
    return id;
  }

  GlobalKey keyOf(int id) => _entries[id]!.key;
  void unregister(int id) => _entries.remove(id);

  void _setFocus(int id) {
    if (!_entries.containsKey(id)) return;
    _focusId = id;
    notifyListeners();
    // Defer so the newly-focused widget has laid out before it scrolls itself in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entries[id]?.onFocused?.call();
    });
  }

  /// Clear selection (used when releasing focus back up to the hero).
  void clearFocus() {
    if (_focusId == null) return;
    _focusId = null;
    notifyListeners();
  }

  /// First focusable in visual order (topmost, then leftmost) — where focus
  /// enters when nothing is focused yet (e.g. pressing Down on the hero).
  int? _firstInOrder() {
    _Entry? best;
    Rect? bestR;
    for (final e in _entries.values) {
      final r = e.rect;
      if (r == null) continue;
      if (bestR == null ||
          r.top < bestR.top - 1 ||
          (r.top < bestR.top + 1 && r.left < bestR.left)) {
        best = e;
        bestR = r;
      }
    }
    return best?.id;
  }

  int? _findNext(int currentId, Direction dir) {
    final current = _entries[currentId];
    final from = current?.rect;
    if (from == null) return null;
    final fc = from.center;

    int? bestId;
    double bestCost = double.infinity;

    for (final e in _entries.values) {
      if (e.id == currentId) continue;
      final to = e.rect;
      if (to == null) continue;
      final tc = to.center;
      final dx = tc.dx - fc.dx;
      final dy = tc.dy - fc.dy;

      final inDirection = switch (dir) {
        Direction.left => dx < -1,
        Direction.right => dx > 1,
        Direction.up => dy < -1,
        Direction.down => dy > 1,
      };
      if (!inDirection) continue;

      // Primary axis = travel in pressed direction; cross axis = misalignment,
      // weighted x3 so straight-line neighbors win.
      final horizontal = dir == Direction.left || dir == Direction.right;
      final primary = horizontal ? dx.abs() : dy.abs();
      final cross = horizontal ? dy.abs() : dx.abs();
      final cost = primary + cross * 3;

      if (cost < bestCost) {
        bestCost = cost;
        bestId = e.id;
      }
    }
    return bestId;
  }

  /// Handle a raw key event at the app root. Returns true if consumed.
  KeyEventResult handleKey(KeyEvent event, VoidCallback? onBack,
      VoidCallback? onReleaseTop) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final dir = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => Direction.up,
      LogicalKeyboardKey.arrowDown => Direction.down,
      LogicalKeyboardKey.arrowLeft => Direction.left,
      LogicalKeyboardKey.arrowRight => Direction.right,
      _ => null,
    };
    if (dir != null) {
      final cur = _focusId;
      // Nothing focused yet (hero showing) — enter the grid at the first card.
      if (cur == null) {
        final first = _firstInOrder();
        if (first != null) _setFocus(first);
        return KeyEventResult.handled;
      }
      final next = _findNext(cur, dir);
      if (next != null) {
        _setFocus(next);
      } else if (dir == Direction.up) {
        // Nothing above the top row — release focus back up to the hero.
        clearFocus();
        onReleaseTop?.call();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.select) {
      final cur = _focusId;
      if (cur != null) _entries[cur]?.onSelect?.call();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      onBack?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}

/// Exposes the [FocusController] to the widget tree (like the React context).
class FocusScopeProvider extends InheritedNotifier<FocusController> {
  const FocusScopeProvider({
    super.key,
    required FocusController controller,
    required super.child,
  }) : super(notifier: controller);

  static FocusController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<FocusScopeProvider>();
    assert(scope != null, 'No FocusScopeProvider found in context');
    return scope!.notifier!;
  }

  /// Non-subscribing lookup — use in initState/didChangeDependencies for
  /// one-time registration where you don't want to rebuild on focus changes.
  static FocusController read(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<FocusScopeProvider>()!
        .widget as FocusScopeProvider;
    return scope.notifier!;
  }
}
