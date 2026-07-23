import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'api/tmdb.dart' as api;
import 'routes.dart';
import 'screens/home.dart';
import 'screens/search.dart';
import 'screens/library.dart';
import 'screens/details.dart';
import 'theme.dart';
import 'update/updater.dart';

void main() {
  runApp(const AlexTvApp());
}

/// Single route observer shared across the Navigator. Screens that need to
/// react to being covered/uncovered (e.g. Home pausing its hero rotation when
/// Details/Search are pushed) subscribe to this via [RouteAware].
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

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
      // Wrap the whole Navigator (not just `home`) in the design scaler, so
      // pushed routes — Details, Search, Player — are scaled to the design
      // canvas too. Wrapping only `home` would leave them oversized on TV.
      builder: (context, child) => _DesignScaler(child: child!),
      navigatorObservers: [routeObserver],
      home: const Home(),
    );
  }
}

/// Pushes the Details screen for [media]. Home stays mounted beneath it (the
/// Navigator keeps routes below the top alive), so its rails, scroll position
/// and focused card all survive the round-trip — Back returns instantly with
/// no refetch. Fully replaces the old flag-based [_AppShell] cross-fade.
void openDetails(BuildContext context, api.Media media) {
  pushGuarded(context, fadeRoute(Details(media: media)));
}

/// Pushes the Search screen. Selecting a result from Search pushes Details on
/// top, so Back from Details returns to Search, then Back again to Home.
void openSearch(BuildContext context) {
  pushGuarded(context, fadeRoute(const Search()));
}

/// Pushes the Library (file-manager) screen. Drilling into folders happens
/// within the screen; Back climbs folders before popping back to Home.
void openLibrary(BuildContext context) {
  pushGuarded(context, fadeRoute(const Library()));
}

/// Runs the self-update flow behind the sidebar's Update item: downloads the
/// latest release APK and hands it to Android's installer. Shows a SnackBar
/// while downloading and another if it fails, so the user gets feedback even
/// though the rail item can't carry a "Downloading…" state of its own.
Future<void> runUpdate(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('Downloading update…')),
  );
  try {
    await Updater.downloadAndInstall();
  } catch (e) {
    debugPrint('Update failed: $e');
    messenger.showSnackBar(
      const SnackBar(content: Text('Update failed. Check the connection.')),
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
