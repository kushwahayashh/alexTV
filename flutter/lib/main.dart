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
        // DM Sans applied app-wide. Inline TextStyles leave fontFamily unset,
        // so they inherit DM Sans from this text theme.
        textTheme: GoogleFonts.dmSansTextTheme(base.textTheme),
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
        final scale = constraints.maxWidth / AppSizes.designWidth;
        // Give descendants a MediaQuery whose logical size matches the design
        // canvas, so height-relative layout (e.g. the 94vh hero) stays correct.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            size: Size(
              AppSizes.designWidth,
              constraints.maxHeight / scale,
            ),
          ),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: AppSizes.designWidth,
              height: constraints.maxHeight / scale,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
