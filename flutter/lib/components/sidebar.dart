import 'package:flutter/material.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

/// Netflix/Hotstar-style left sidebar. Ported 1:1 from `src/components/Sidebar.tsx`.
/// Collapsed by default (icon only), it expands to reveal the label when any of
/// its items holds focus. Each item is a focus engine sidebar entry, so D-pad
/// Up/Down walks the rail and Right drops into the content; Left from the
/// leftmost content column reaches it.
///
/// Items are mocks for now — onSelect is wired for Home/Search/Library/Update,
/// the rest are placeholders pending real screens.

enum NavId { home, search, library, movies, tv, settings, update }

class NavItem {
  final NavId id;
  final String label;
  final IconData icon;
  final VoidCallback? onSelect;
  const NavItem(
    this.id,
    this.label,
    this.icon, {
    this.onSelect,
  });
}

/// Canonical nav rail, shared by every screen that shows the sidebar. Screens
/// wire the handlers they can service via [withHandlers]; the rest stay
/// placeholders until their screens exist.
const List<NavItem> kNavItems = [
  NavItem(NavId.home, 'Home', Icons.home_rounded),
  NavItem(NavId.search, 'Search', Icons.search_rounded),
  NavItem(NavId.library, 'Library', Icons.video_library_rounded),
  NavItem(NavId.movies, 'Movies', Icons.movie_rounded),
  NavItem(NavId.tv, 'TV Shows', Icons.tv_rounded),
  NavItem(NavId.settings, 'Settings', Icons.settings_rounded),
  NavItem(NavId.update, 'Update', Icons.download_rounded),
];

/// Attach onSelect handlers to nav items by id; unmatched items stay as-is.
List<NavItem> withHandlers(Map<NavId, VoidCallback?> handlers) {
  return kNavItems
      .map(
        (it) => handlers[it.id] == null
            ? it
            : NavItem(it.id, it.label, it.icon, onSelect: handlers[it.id]),
      )
      .toList();
}

/// Fixed vertical rail overlaying the hero. The rail is always present in the
/// tree; it just reads focus state from the screen's [FocusController] and
/// expands when any of its items holds focus. Width animates so the expand
/// feels like a hover-out rather than a snap.
class Sidebar extends StatefulWidget {
  final List<NavItem> items;
  const Sidebar({super.key, required this.items});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  late FocusController _controller;
  final List<int> _ids = [];
  bool _registered = false;
  bool _expanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      for (var i = 0; i < widget.items.length; i++) {
        // Register a stable indirection, not item.onSelect directly. The engine
        // captures the onSelect closure once at register time, but the parent
        // screen (Home/Library) rebuilds withHandlers() — and thus fresh
        // NavItem.onSelect closures — every build. Reading widget.items[i] at
        // select time means D-pad Enter always runs the current handler.
        _ids.add(
          _controller.register(
            onSelect: () => _selectAt(i),
            // isSidebar only — NOT isHeader. Sidebar items have their own
            // directional branch (Up/Down walks the rail, Right drops into
            // content) and must stay out of _headerIds so _firstHeader /
            // _nextHeader — which drive the top-bar pill nav — never scan them.
            isSidebar: true,
          ),
        );
      }
      _registered = true;
    }
    _controller.addListener(_onFocusChanged);
    _onFocusChanged();
  }

  void _onFocusChanged() {
    final any = _ids.any(_controller.isFocused);
    if (any != _expanded) setState(() => _expanded = any);
  }

  /// Invoke the current handler for the item at [index]. Read live from
  /// `widget.items` (not captured at register time) so a rebuilt handler list
  /// always fires the latest closure. Guarded against a shrunk list.
  void _selectAt(int index) {
    if (index >= widget.items.length) return;
    widget.items[index].onSelect?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_onFocusChanged);
    for (final id in _ids) {
      _controller.unregister(id);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      // ClipRect clips the painted child to the AnimatedContainer's animated
      // width so labels (which always take their full text width via the
      // OverflowBox below) stay hidden when the rail is collapsed, instead of
      // being measured down to 76px and wrapping/truncating. Mirrors the CSS
      // `overflow: hidden` on `.sidebar`.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: _expanded
            ? AppSizes.sidebarExpandedWidth
            : AppSizes.sidebarCollapsedWidth,
        // Match the React gradient: a horizontal fade from near-opaque at the
        // left edge to transparent at the right, so the expanded rail dims the
        // content behind it without a hard vertical cut.
        decoration: BoxDecoration(
          gradient: _expanded ? _expandedGradient : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: OverflowBox(
          // Let the items column always be `sidebarItemWidth` wide regardless
          // of the (animated) rail width, so labels keep their natural size.
          // The ClipRect above paints only the visible slice.
          maxWidth: AppSizes.sidebarItemWidth,
          minWidth: AppSizes.sidebarItemWidth,
          maxHeight: double.infinity,
          alignment: Alignment.centerLeft,
          child: Padding(
            // `.sidebar__items { padding: 0 12px }` — gives the icon column some
            // breathing room from the rail's left edge so it sits roughly
            // centered in the collapsed 76px rail (icon center ≈ 39px).
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              // `align-items: stretch` — each item fills the 200px content width
              // so the icon+label row left-aligns within it, matching React.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.items.length; i++) ...[
                  _SidebarItemView(
                    item: widget.items[i],
                    id: _ids[i],
                    expanded: _expanded,
                  ),
                  if (i < widget.items.length - 1)
                    const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal fade used when the rail is expanded. Stops mirror the React
/// `linear-gradient(90deg, rgba(2,2,2,0.96) 0%, ..., transparent 100%)`.
const _expandedGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [
    Color(0xF5020202),
    Color(0xF0020202),
    Color(0xD9020202),
    Color(0xAD020202),
    Color(0x7A020202),
    Color(0x4D020202),
    Color(0x29020202),
    Color(0x12020202),
    Color(0x05020202),
    Color(0x00020202),
  ],
  stops: [
    0.0,
    0.28,
    0.42,
    0.55,
    0.67,
    0.78,
    0.87,
    0.94,
    0.98,
    1.0,
  ],
);

class _SidebarItemView extends StatelessWidget {
  final NavItem item;
  final int id;
  final bool expanded;
  const _SidebarItemView({
    required this.item,
    required this.id,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(id);
    final color = focused ? AppColors.text : AppColors.muted;

    return KeyedSubtree(
      key: controller.keyOf(id),
      child: GestureDetector(
        onTap: item.onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 26, color: color),
              const SizedBox(width: 16),
              // Label fades in only when the rail is expanded. An animated
              // underline (scaleX 0 → 1) marks the focused item, matching the
              // navbar buttons' ::after underline.
              _Label(
                label: item.label,
                color: color,
                expanded: expanded,
                focused: focused,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String label;
  final Color color;
  final bool expanded;
  final bool focused;
  const _Label({
    required this.label,
    required this.color,
    required this.expanded,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: expanded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: Stack(
        children: [
          Padding(
            // Room for the 2px underline below the label.
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
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
              child: Container(height: 2, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
