import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home.dart';
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
      home: const _DesignScaler(child: Home()),
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
