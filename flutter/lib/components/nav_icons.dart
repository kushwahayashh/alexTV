import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Sidebar nav icons ported 1:1 from `src/components/icons.tsx`. Each entry is
/// the exact React SVG markup (24x24, stroke-based, `fill="none"`) so the
/// Flutter rail renders the same glyphs as the web prototype. `currentColor`
/// on the strokes is resolved via a `srcIn` color filter at render time, the
/// Flutter equivalent of the CSS `color` inheritance the React icons rely on.

const String _home = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M3 11.5L12 4l9 7.5" />
  <path d="M5 10v10h14V10" />
</svg>''';

const String _search = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="11" cy="11" r="7" />
  <path d="M21 21l-4.3-4.3" />
</svg>''';

const String _library = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M4 4h4v16H4z" />
  <path d="M10 4h4v16h-4z" />
  <path d="M17 5l3 .8-3 14.2-3-.8z" />
</svg>''';

const String _film = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="3" y="4" width="18" height="16" rx="2" />
  <path d="M7 4v16M17 4v16M3 9h4M17 9h4M3 15h4M17 15h4" />
</svg>''';

const String _tv = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <rect x="3" y="7" width="18" height="13" rx="2" />
  <path d="M8 3l4 4 4-4" />
</svg>''';

const String _settings = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <circle cx="12" cy="12" r="3" />
  <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
</svg>''';

const String _update = '''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="M12 3v12" />
  <path d="M7 10l5 5 5-5" />
  <path d="M5 21h14" />
</svg>''';

/// Raw SVG markup for each sidebar glyph.
class NavIcons {
  static const String home = _home;
  static const String search = _search;
  static const String library = _library;
  static const String film = _film;
  static const String tv = _tv;
  static const String settings = _settings;
  static const String update = _update;
}

/// Renders a sidebar nav glyph from its raw SVG markup, tinting the strokes to
/// [color] and sizing it to [size] (26px to match `.sidebar__icon svg` in CSS).
class NavIcon extends StatelessWidget {
  final String svg;
  final Color color;
  final double size;
  const NavIcon({
    super.key,
    required this.svg,
    required this.color,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
