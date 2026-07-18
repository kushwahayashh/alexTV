import 'dart:async';
import 'package:flutter/material.dart';
import '../api/tmdb.dart' as api;
import '../components/header_button.dart';
import '../components/hero.dart' as ui;
import '../components/rail.dart';
import '../components/update_button.dart';
import '../focus/focus_engine.dart';
import '../main.dart' show openDetails, openSearch, routeObserver;
import '../theme.dart';

const _heroRotateMs = 10000;

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with RouteAware {
  final _focus = FocusController();
  final _pageController = ScrollController();
  final _keyboardNode = FocusNode();

  List<api.Rail> _rails = [];
  List<api.Media> _featured = [];
  int _heroIndex = 0;
  Timer? _rotateTimer;
  _Status _status = _Status.loading;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe once the route is available (can't in initState — ModalRoute
    // needs a context that has access to the Navigator). Re-subscribing is
    // idempotent; routeObserver dedupes the subscription.
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  Future<void> _load() async {
    try {
      final data = await api.fetchHomeRails();
      if (!mounted) return;
      setState(() {
        _rails = data;
        // Feature trending items that actually have a backdrop to show.
        _featured = (data.isNotEmpty ? data[0].items : <api.Media>[])
            .where((m) => m.backdropPath != null)
            .take(10)
            .toList();
        _status = _Status.ready;
      });
      _startRotation();
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _status = _Status.error);
    }
  }

  // Hero cycles on its own, independent of card focus.
  void _startRotation() {
    if (_featured.length < 2) return;
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(
      const Duration(milliseconds: _heroRotateMs),
      (_) => setState(() => _heroIndex = (_heroIndex + 1) % _featured.length),
    );
  }

  void _stopRotation() {
    _rotateTimer?.cancel();
    _rotateTimer = null;
  }

  // RouteAware: pause the hero timer while another route (Details, Search,
  // Player) is on top of Home. Home stays mounted underneath, so without this
  // the timer keeps firing setState + remounting FadeImage, loading more
  // original-size backdrops into the image cache while the user can't see it.
  @override
  void didPushNext() => _stopRotation();

  @override
  void didPopNext() => _startRotation();

  void _releaseToTop() {
    if (_pageController.hasClients) {
      _pageController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _stopRotation();
    _pageController.dispose();
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // No PopScope here — Home is the root route, so hardware Back falls
      // through to the system and exits to the launcher. When Details/Search
      // are pushed on top, the Navigator disables Home's focus scope, so this
      // key handler simply stops receiving events until they pop.
      body: FocusScopeProvider(
        controller: _focus,
        child: Focus(
          focusNode: _keyboardNode,
          autofocus: true,
          onKeyEvent: (_, event) =>
              _focus.handleKey(event, null, _releaseToTop),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.loading:
        return const _ScreenMsg('Loading…');
      case _Status.error:
        return const _ScreenMsg('Failed to load. Check the network / API key.');
      case _Status.ready:
        return SingleChildScrollView(
          controller: _pageController,
          physics: const ClampingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero with header buttons overlaid: Search + Library on the
              // top-left, Update on the top-right. Keeping them inside the
              // scroll content means they scroll away with the hero.
              Stack(
                children: [
                  ui.Hero(
                    media: _featured.isNotEmpty ? _featured[_heroIndex] : null,
                  ),
                  Positioned(
                    top: 24,
                    left: AppSizes.pagePadding,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HeaderButton(label: 'Home', onFocused: _releaseToTop),
                        const SizedBox(width: 12),
                        HeaderButton(
                          label: 'Search',
                          onFocused: _releaseToTop,
                          onSelect: () => openSearch(context),
                        ),
                        const SizedBox(width: 12),
                        HeaderButton(
                          label: 'Library',
                          onFocused: _releaseToTop,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 24,
                    right: AppSizes.pagePadding,
                    child: UpdateButton(onFocused: _releaseToTop),
                  ),
                ],
              ),
              // Pull the rails up into the base of the hero (margin-top: -80).
              Transform.translate(
                offset: const Offset(0, -AppSizes.railsOverlap),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 64),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final rail in _rails) ...[
                        Rail(
                          rail: rail,
                          pageController: _pageController,
                          onSelect: (m) => openDetails(context, m),
                        ),
                        const SizedBox(height: AppSizes.railGap),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }
}

enum _Status { loading, ready, error }

class _ScreenMsg extends StatelessWidget {
  final String text;
  const _ScreenMsg(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: AppColors.muted, fontSize: 20),
        ),
      ),
    );
  }
}
