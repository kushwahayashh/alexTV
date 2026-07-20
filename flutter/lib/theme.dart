import 'package:flutter/material.dart';

/// Design tokens ported 1:1 from the React prototype's CSS `:root` variables.
class AppColors {
  static const bg = Color(0xFF090909);
  static const surface = Color(0xFF171717);
  static const text = Color(0xFFF4F4F5);
  static const muted = Color(0xFF8B8B8B);
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

  // Sidebar (Netflix/Hotstar-style left rail). Collapsed shows icons only;
  // it widens to reveal labels when any item holds focus. The content left
  // padding is `sidebarCollapsedWidth + 16px` gutter so rails/hero clear it.
  static const sidebarCollapsedWidth = 76.0;
  static const sidebarExpandedWidth = 460.0; // includes the right-side fade room
  static const sidebarItemWidth = 224.0; // items stay compact; rest is fade room
  static const sidebarContentPad = 92.0; // sidebarCollapsedWidth + 16 gutter
  static const sidebarFadeWidth = 96.0; // left-edge mask span (matches CSS)

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

  // Focused-row scroll lift: how far below the viewport top a newly focused
  // row/card is seated after it scrolls itself into view. Screen-specific
  // because each screen has a different header height above its scroll area.
  static const episodeRowScrollLift = 286.0; // Details episode list
  static const libraryRowScrollLift = 150.0; // Library file rows
  static const searchResultScrollLift = 130.0; // Search result grid
}
