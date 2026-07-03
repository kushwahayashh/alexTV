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
      home: const Home(),
    );
  }
}
