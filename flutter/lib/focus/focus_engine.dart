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
  // Sidebar item: the vertical left rail (Netflix/Hotstar-style). It is NOT a
  // header — it has its own id set (`_sidebarIds`) and its own nav semantics:
  // Up/Down walks the rail, Right drops into the content, Left is a no-op, and
  // Left from the leftmost content column reaches it. Like headers, sidebar
  // items are excluded from the content grid, but they are kept out of
  // `_headerIds` so the header Left/Right walk never lands on a rail item.
  final bool isSidebar;
  final bool isInput;
  bool active;
  _Entry(
    this.id,
    this.key,
    this.onSelect,
    this.onFocused,
    this.isHeader,
    this.isSidebar,
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
  final _headerIds = <int>{}; // plain top-bar headers (NOT sidebar items)
  final _sidebarIds = <int>{}; // all sidebar rail focusables
  int _counter = 0;

  // Rate-limit held-key (auto-repeat) navigation. A discrete press always moves
  // immediately; while the D-pad is held, moves are capped to one per
  // [_repeatIntervalMs] so a long list doesn't fly past under the cursor and so
  // each repeat doesn't trigger an unbounded live-geometry scan every frame.
  final Stopwatch _navClock = Stopwatch()..start();
  int _lastRepeatMs = 0;
  static const int _repeatIntervalMs = 90;

  int? get focusId => _focusId;
  bool isFocused(int id) => _focusId == id;

  int register({
    VoidCallback? onSelect,
    VoidCallback? onFocused,
    bool isHeader = false,
    bool isSidebar = false,
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
      isSidebar,
      isInput,
      active,
    );
    if (isHeader) _headerIds.add(id);
    if (isSidebar) _sidebarIds.add(id);
    return id;
  }

  GlobalKey keyOf(int id) => _entries[id]!.key;

  void setActive(int id, bool active) {
    final entry = _entries[id];
    if (entry == null || entry.active == active) return;
    entry.active = active;
    // If the entry that just went inactive held focus, hand focus to the
    // nearest still-active neighbor instead of leaving nothing focused (a
    // dead-end until the next key press).
    if (!active && _focusId == id) _focusId = _nearestActive(id);
    notifyListeners();
  }

  void unregister(int id) {
    _entries.remove(id);
    _headerIds.remove(id);
    _sidebarIds.remove(id);
    // The focused entry is being torn down (e.g. a Library folder change or a
    // season switch disposes the old rows). Clear the dangling id so a removed
    // entry never stays "focused". No notifyListeners here: unregister runs
    // during dispose, where notifying listeners mid-teardown can fire setState
    // on a defunct tree. The replacing content requests focus itself (or the
    // next direction key self-heals via the !curAlive path).
    if (_focusId == id) _focusId = null;
  }

  /// Nearest active entry to [id] by center distance — used to relocate focus
  /// when the focused entry is disabled.
  int? _nearestActive(int id) {
    final from = _entries[id]?.rect;
    if (from == null) return null;
    final fc = from.center;
    int? bestId;
    double bestDist = double.infinity;
    for (final e in _entries.values) {
      if (e.id == id || !e.active) continue;
      final r = e.rect;
      if (r == null || r.isEmpty) continue;
      final d = (r.center - fc).distanceSquared;
      if (d < bestDist) {
        bestDist = d;
        bestId = e.id;
      }
    }
    return bestId;
  }

  void _setFocus(int id) {
    final entry = _entries[id];
    if (entry == null || !entry.active) return;
    _focusId = id;
    notifyListeners();
    // Sidebar items live in a fixed-position rail that never scrolls, so
    // scrolling would instead walk up to the nearest scroll container
    // (Home/Library) and yank the content vertically — causing the hero/
    // rails to jump when the rail expands. Skip scrolling for rail items.
    if (entry.isSidebar) return;
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

  /// Focus the first content-grid item, if any. Used to re-seat focus after a
  /// screen swaps its content out from under the cursor (e.g. a Library folder
  /// change disposes the focused row): without this the listing shows no focus
  /// ring until the next direction key self-heals via the `!curAlive` path.
  /// No-op when the grid is empty, so an empty folder simply shows nothing
  /// focused rather than grabbing a header/sidebar item.
  void focusFirstContent() {
    final first = _firstInOrder();
    if (first != null) _setFocus(first);
  }

  /// First focusable in visual order (topmost, then leftmost) — where focus
  /// enters when nothing is focused yet (e.g. pressing Down on the hero) or
  /// when a header releases into the content grid. Skips headers and inputs:
  /// the search text field is the topmost entry but Down from the header pills
  /// should land on the first result, not the field.
  int? _firstInOrder() {
    _Entry? best;
    Rect? bestR;
    for (final e in _entries.values) {
      if (e.isHeader) continue; // header isn't part of the content grid
      if (e.isSidebar) continue; // rail is reached via Left / _firstSidebar
      if (e.isInput) continue; // reached via its own field focus, not the grid
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

  /// Leftmost plain header in document order — where focus enters when pressing
  /// Up toward the top chrome. Falls back to the sidebar rail when a screen has
  /// no plain top-bar headers (Home/Library), where the sidebar *is* the top
  /// chrome. This preserves the old behavior from when sidebar items were also
  /// tagged `isHeader`, without the flag overload.
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
    return best?.id ?? _firstSidebar();
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

  /// First sidebar item in document order — where focus enters when content
  /// reaches sideways for the rail (Left from the leftmost column). "Document
  /// order" here is registration order, which matches the visual top-to-bottom
  /// order of the rail.
  int? _firstSidebar() {
    for (final id in _sidebarIds) {
      final e = _entries[id];
      if (e == null || !e.active) continue;
      final r = e.rect;
      if (r == null || r.isEmpty) continue;
      return id;
    }
    return null;
  }

  /// Next sidebar item above/below the current one in the vertical rail.
  int? _nextSidebar(int currentId, Direction dir) {
    final current = _entries[currentId];
    final from = current?.rect;
    if (from == null) return null;
    final fc = from.center;

    int? bestId;
    double bestCost = double.infinity;
    for (final id in _sidebarIds) {
      if (id == currentId) continue;
      final e = _entries[id];
      if (e == null || !e.active) continue;
      final to = e.rect;
      if (to == null || to.isEmpty) continue;
      final dy = to.center.dy - fc.dy;
      if (dir == Direction.up ? dy >= -1 : dy <= 1) continue;
      final cost = dy.abs();
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
      // Top-bar headers and the sidebar rail are not part of the content grid;
      // they're reached via their own explicit paths (Up-from-top, Left-to-rail)
      // and navigated by _nextHeader / _nextSidebar.
      if (e.isHeader || e.isSidebar) continue;
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
      // A held D-pad key emits a burst of KeyRepeatEvents (one per frame on
      // some TV firmwares). Each move below runs an O(n) live-geometry scan, so
      // acting on every repeat both hammers layout and races the cursor past
      // its target. A discrete press (KeyDownEvent) always moves; repeats are
      // capped to one move per [_repeatIntervalMs]. Extra repeats are consumed
      // (handled) so they don't fall through to other handlers.
      if (event is KeyRepeatEvent) {
        final now = _navClock.elapsedMilliseconds;
        if (now - _lastRepeatMs < _repeatIntervalMs) {
          return KeyEventResult.handled;
        }
        _lastRepeatMs = now;
      }

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

      // Sidebar item focused: Up/Down walks the vertical rail, Right drops
      // into the content (hero first if there is one), Left is a no-op.
      // _sidebarIds and _headerIds are disjoint sets (sidebar items are no
      // longer registered as headers), so this branch and the header branch
      // below never contend for the same entry.
      if (curAlive && cur != null && _sidebarIds.contains(cur)) {
        if (dir == Direction.up || dir == Direction.down) {
          final next = _nextSidebar(cur, dir);
          if (next != null) _setFocus(next);
        } else if (dir == Direction.right) {
          if (onReleaseTop != null) {
            clearFocus();
            onReleaseTop.call();
          } else {
            final first = _firstInOrder();
            if (first != null) _setFocus(first);
          }
        }
        return KeyEventResult.handled;
      }
      // Header focused: left/right moves between headers. Down drops into the
      // hero when there is one (onReleaseTop set); otherwise — on hero-less
      // screens like Library/Search — straight into the content grid, so it's
      // a single press instead of wasting one on an empty release.
      if (curAlive && cur != null && _headerIds.contains(cur)) {
        if (dir == Direction.down) {
          if (onReleaseTop != null) {
            clearFocus();
            onReleaseTop.call();
          } else {
            final first = _firstInOrder();
            if (first != null) _setFocus(first);
          }
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
        // Nothing above the top row. With a hero (onReleaseTop set), release
        // focus up to reveal it — a second Up then reaches the header. Without
        // one, jump straight to the header so it's a single press.
        if (onReleaseTop != null) {
          clearFocus();
          onReleaseTop.call();
        } else {
          final first = _firstHeader();
          if (first != null) _setFocus(first);
        }
      } else if (dir == Direction.left) {
        // Nothing to the left of the first column. If a sidebar rail is
        // present, jump into it (Hotstar/Netflix-style left rail).
        final sb = _firstSidebar();
        if (sb != null) _setFocus(sb);
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
    final element =
        context.getElementForInheritedWidgetOfExactType<FocusScopeProvider>();
    assert(
      element != null,
      'No FocusScopeProvider found in context. A focusable widget must be '
      'built beneath the screen\'s FocusScopeProvider.',
    );
    return (element!.widget as FocusScopeProvider).notifier!;
  }
}
