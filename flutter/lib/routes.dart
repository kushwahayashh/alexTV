import 'package:flutter/material.dart';

/// Shared page transition for the app's pushed routes (Details, Search, Player).
///
/// Replaces the hand-rolled cross-fade the app shell used to drive with an
/// [AnimationController]. Using a real [PageRoute] means hardware Back pops
/// exactly one route via the framework — no flag coordination, no racing
/// PopScopes.
///
/// [opaque] must be false for overlay routes that need the route beneath them
/// to keep painting (e.g. the Player modal, which blurs the Details page behind
/// it). Fully-covering screens (Details, Search) stay opaque so the framework
/// can stop painting routes underneath once the transition settles.
Route<T> fadeRoute<T>(Widget page, {bool opaque = true}) {
  return PageRouteBuilder<T>(
    opaque: opaque,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: child,
    ),
  );
}

/// Push [route], but only if the caller's own route is still the topmost one.
///
/// D-pad Select has no natural debounce: a quick double-press (or a held key
/// that slips a repeat through) fires the same `onSelect` twice, and two bare
/// `Navigator.push` calls stack two identical routes — the user then has to
/// press Back twice and sees a double transition. Once the first push starts,
/// the origin route is no longer `isCurrent`, so the second call is dropped
/// here. Returns the route's pop result, or null if the push was suppressed.
Future<T?> pushGuarded<T>(BuildContext context, Route<T> route) {
  final origin = ModalRoute.of(context);
  if (origin != null && !origin.isCurrent) return Future<T?>.value(null);
  return Navigator.of(context).push(route);
}
