import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api/tmdb.dart' as api;
import 'screens/home.dart';
import 'screens/search.dart';
import 'screens/details.dart';
import 'theme.dart';

void main() {
  runApp(const AlexTvApp());
}

class AlexTvApp extends StatelessWidget {
  const AlexTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bg,
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'AlexTV',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        // Varela Round applied app-wide. Inline TextStyles leave fontFamily unset,
        // so they inherit Varela Round from this text theme.
        textTheme: GoogleFonts.varelaRoundTextTheme(base.textTheme),
      ),
      home: const _DesignScaler(child: _AppShell()),
    );
  }
}

/// Routes between Home and Details, mirroring the React App.tsx `selected`
/// state. Home stays mounted (just hidden) while Details is on top, so its
/// rails data, scroll position and focused card all survive a round-trip —
/// pressing Back returns to Home instantly without a refetch.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell>
    with SingleTickerProviderStateMixin {
  api.Media? _selected;
  bool _showSearch = false;

  // Drives the Details fade: forward = fading in over Home, reverse = fading
  // out back to Home. Details stays mounted through the whole reverse so the
  // exit actually animates instead of cutting.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  // True only once Details has fully faded in — lets us Offstage Home to save
  // paint work while it's fully covered, but keep it visible during the
  // cross-fade so you see it through the fading Details.
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addStatusListener((status) {
      final covered = status == AnimationStatus.completed;
      if (covered != _covered) setState(() => _covered = covered);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onSelect(api.Media m) {
    setState(() => _selected = m);
    _ctrl.forward(from: 0);
  }

  void _openSearch() => setState(() => _showSearch = true);

  void _closeSearch() => setState(() => _showSearch = false);

  void _onBack() {
    // Fade Details out, then drop it. Home stays put underneath the whole time.
    // Guard on `dismissed` so a re-open that interrupts the reverse doesn't
    // then clear the freshly-selected media.
    _ctrl.reverse().whenComplete(() {
      if (mounted && _ctrl.status == AnimationStatus.dismissed) {
        setState(() => _selected = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasDetails = _selected != null;
    final homeCovered = _covered || (_showSearch && !hasDetails);
    // Single top-level PopScope. Because every PopScope on a route fires on a
    // back press, the child screens' own PopScopes handle Back when they're on
    // top. On Home (no overlay) we allow the pop so Back exits the app to the
    // launcher; while Search/Details/Player are shown we block it.
    return PopScope(
      canPop: !hasDetails && !_showSearch,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || hasDetails) return;
        if (_showSearch) _closeSearch();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Kept mounted underneath overlays so its state is preserved. Offstage
          // (not a conditional) is what stops it from unmounting/refetching;
          // it still lays Home out at full size, so scroll position survives.
          Offstage(
            offstage: homeCovered,
            child: TickerMode(
              enabled: !homeCovered,
              child: Home(
                active: !hasDetails && !_showSearch,
                onSelect: _onSelect,
                onOpenSearch: _openSearch,
              ),
            ),
          ),
          if (_showSearch)
            Offstage(
              offstage: hasDetails,
              child: TickerMode(
                enabled: !hasDetails,
                child: Search(
                  active: !hasDetails,
                  onSelect: _onSelect,
                  onGoHome: _closeSearch,
                ),
              ),
            ),
          if (hasDetails)
            FadeTransition(
              opacity: _fade,
              child: Details(media: _selected!, onBack: _onBack),
            ),
        ],
      ),
    );
  }
}

/// Lays the app out at a fixed [AppSizes.designWidth] and uniformly scales it
/// to fill the real screen. Without this, TVs (which report a narrow logical
/// canvas at a high device-pixel-ratio) render the fixed-size UI zoomed in,
/// while the wide browser dev window looks correct. Scaling a fixed design
/// canvas makes both look identical.
class _DesignScaler extends StatelessWidget {
  final Widget child;
  const _DesignScaler({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Height of the design canvas that preserves the real screen's aspect
        // ratio, so fitting the width also fits the height (uniform, no stretch).
        final designHeight =
            AppSizes.designWidth * constraints.maxHeight / constraints.maxWidth;
        final media = MediaQuery.of(context);
        // FittedBox lays the child out UNBOUNDED (so it's truly designWidth
        // wide, not clamped to the screen) then scales it to fill. A plain
        // Transform would leave the child clamped to the incoming constraints.
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: AppSizes.designWidth,
            height: designHeight,
            // Give descendants a MediaQuery matching the design canvas so
            // height-relative layout (e.g. the 94vh hero) stays correct.
            child: MediaQuery(
              data: media.copyWith(
                size: Size(AppSizes.designWidth, designHeight),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
