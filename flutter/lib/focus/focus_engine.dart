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
  final VoidCallback?
  onFocused; // scrolls itself into view, like scrollIntoView
  final bool isHeader; // top bar (e.g. Update button), reached by Up from hero
  final bool isInput;
  bool active;
  _Entry(
    this.id,
    this.key,
    this.onSelect,
    this.onFocused,
    this.isHeader,
    this.isInput,
    this.active,
  );

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
  final _headerIds = <int>{}; // all header focusables
  int _counter = 0;

  int? get focusId => _focusId;
  bool isFocused(int id) => _focusId == id;

  int register({
    VoidCallback? onSelect,
    VoidCallback? onFocused,
    bool isHeader = false,
    bool isInput = false,
    bool active = true,
  }) {
    final id = _counter++;
    _entries[id] = _Entry(
      id,
      GlobalKey(),
      onSelect,
      onFocused,
      isHeader,
      isInput,
      active,
    );
    if (isHeader) _headerIds.add(id);
    return id;
  }

  GlobalKey keyOf(int id) => _entries[id]!.key;

  void setActive(int id, bool active) {
    final entry = _entries[id];
    if (entry == null || entry.active == active) return;
    entry.active = active;
    if (!active && _focusId == id) _focusId = null;
    notifyListeners();
  }

  void unregister(int id) {
    _entries.remove(id);
    _headerIds.remove(id);
  }

  void _setFocus(int id) {
    final entry = _entries[id];
    if (entry == null || !entry.active) return;
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

  /// Programmatically focus a registered entry (mirrors the React `focusSelf`).
  void requestFocus(int id) => _setFocus(id);

  /// First focusable in visual order (topmost, then leftmost) — where focus
  /// enters when nothing is focused yet (e.g. pressing Down on the hero).
  int? _firstInOrder() {
    _Entry? best;
    Rect? bestR;
    for (final e in _entries.values) {
      if (e.isHeader) continue; // header isn't part of the content grid
      if (!e.active) continue;
      final r = e.rect;
      if (r == null || r.isEmpty) continue;
      if (bestR == null ||
          r.top < bestR.top - 1 ||
          (r.top < bestR.top + 1 && r.left < bestR.left)) {
        best = e;
        bestR = r;
      }
    }
    return best?.id;
  }

  /// Leftmost header in document order — where focus enters when pressing Up
  /// from the hero.
  int? _firstHeader() {
    _Entry? best;
    Rect? bestR;
    for (final id in _headerIds) {
      final e = _entries[id];
      if (e == null) continue;
      if (!e.active) continue;
      final r = e.rect;
      if (r == null || r.isEmpty) continue;
      if (bestR == null || r.left < bestR.left) {
        best = e;
        bestR = r;
      }
    }
    return best?.id;
  }

  /// Next header in the pressed horizontal direction, or null if none.
  int? _nextHeader(int currentId, Direction dir) {
    final current = _entries[currentId];
    final from = current?.rect;
    if (from == null) return null;
    final fc = from.center;

    int? bestId;
    double bestCost = double.infinity;
    for (final id in _headerIds) {
      if (id == currentId) continue;
      final e = _entries[id];
      if (e == null || !e.active) continue;
      final to = e.rect;
      if (to == null || to.isEmpty) continue;
      final dx = to.center.dx - fc.dx;
      if (dir == Direction.left ? dx >= -1 : dx <= 1) continue;
      final cost = dx.abs();
      if (cost < bestCost) {
        bestCost = cost;
        bestId = id;
      }
    }
    return bestId;
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
      if (e.isHeader) {
        continue; // reached only via the explicit Up-from-top path
      }
      if (!e.active) continue;
      final to = e.rect;
      if (to == null || to.isEmpty) continue;
      final tc = to.center;
      final dx = tc.dx - fc.dx;
      final dy = tc.dy - fc.dy;

      final inDirection = switch (dir) {
        Direction.left => dx < -1 && dy.abs() < from.height / 2,
        Direction.right => dx > 1 && dy.abs() < from.height / 2,
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
  KeyEventResult handleKey(
    KeyEvent event,
    VoidCallback? onBack,
    VoidCallback? onReleaseTop,
  ) {
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
      final curEntry = cur == null ? null : _entries[cur];
      final curAlive = curEntry != null && curEntry.active;

      if (curAlive && curEntry.isInput) {
        if (dir == Direction.left || dir == Direction.right) {
          return KeyEventResult.ignored;
        }
        if (dir == Direction.up) {
          final first = _firstHeader();
          if (first != null) _setFocus(first);
        } else {
          final next = _findNext(cur!, Direction.down);
          if (next != null) _setFocus(next);
        }
        return KeyEventResult.handled;
      }

      // Header focused: left/right moves between headers, down drops to hero.
      if (curAlive && cur != null && _headerIds.contains(cur)) {
        if (dir == Direction.down) {
          clearFocus();
          onReleaseTop?.call();
        } else if (dir == Direction.left || dir == Direction.right) {
          final next = _nextHeader(cur, dir);
          if (next != null) _setFocus(next);
        }
        return KeyEventResult.handled;
      }
      // Nothing focused yet (hero showing). Up reaches the first header; any
      // other direction enters the content grid at the first card.
      if (cur == null || !curAlive) {
        if (dir == Direction.up) {
          final first = _firstHeader();
          if (first != null) _setFocus(first);
          return KeyEventResult.handled;
        }
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

    if (event is KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.select) {
      final cur = _focusId;
      final curEntry = cur == null ? null : _entries[cur];
      if (curEntry?.isInput == true &&
          event.logicalKey == LogicalKeyboardKey.space) {
        return KeyEventResult.ignored;
      }
      if (curEntry != null) curEntry.onSelect?.call();
      return KeyEventResult.handled;
    }

    // NOTE: `goBack` (Android KEYCODE_BACK) is deliberately NOT handled here.
    // On Android TV the hardware Back button is dispatched by the framework's
    // Navigator/PopScope back-button observer, which pops exactly one route.
    // If we also consumed it here and called onBack (which pops), a single
    // press would tear down two levels — the intermittent "Back jumps to Home"
    // bug. Escape/Backspace remain for desktop dev, where there's no system
    // back dispatcher.
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      final cur = _focusId;
      final curEntry = cur == null ? null : _entries[cur];
      if (curEntry?.isInput == true &&
          event.logicalKey == LogicalKeyboardKey.backspace) {
        return KeyEventResult.ignored;
      }
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
    final scope = context
        .dependOnInheritedWidgetOfExactType<FocusScopeProvider>();
    assert(scope != null, 'No FocusScopeProvider found in context');
    return scope!.notifier!;
  }

  /// Non-subscribing lookup — use in initState/didChangeDependencies for
  /// one-time registration where you don't want to rebuild on focus changes.
  static FocusController read(BuildContext context) {
    final scope =
        context
                .getElementForInheritedWidgetOfExactType<FocusScopeProvider>()!
                .widget
            as FocusScopeProvider;
    return scope.notifier!;
  }
}
