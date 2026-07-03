import 'package:flutter/material.dart';

/// Design tokens ported 1:1 from the React prototype's CSS `:root` variables.
class AppColors {
  static const bg = Color(0xFF08080A);
  static const surface = Color(0xFF16161A);
  static const text = Color(0xFFF2F5F8);
  static const muted = Color(0xFF8B8B94);
  static const accent = Color(0xFFE50914);
  static const focus = Color(0xFFFFFFFF);
}

class AppSizes {
  // Fixed logical width the whole UI is laid out at, then scaled to fill the
  // real screen. Keeps the look consistent across the browser dev window and
  // actual TVs (which report a narrow logical canvas at a high pixel ratio,
  // making fixed-size widgets look zoomed in). Smaller value => elements
  // render larger => more zoomed in.
  static const designWidth = 1260.0;

  static const radius = 10.0;
  static const pagePadding = 48.0;

  // Poster
  static const posterW = 158.0;
  static const posterH = 237.0;
  static const posterGap = 16.0;
  static const posterFocusScale = 1.12;

  // Layout
  static const railGap = 34.0;
  static const railsOverlap = 80.0; // rails pull up into the hero
  static const heroHeightFactor = 0.94; // 94vh
  static const scrollPaddingTop = 360.0; // lift target for a focused row
}
