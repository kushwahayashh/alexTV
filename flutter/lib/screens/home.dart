import 'dart:async';
import 'package:flutter/material.dart';
import '../api/tmdb.dart' as api;
import '../components/hero.dart' as ui;
import '../components/rail.dart';
import '../components/sidebar.dart';
import '../components/spinner.dart';
import '../focus/focus_engine.dart';
import '../main.dart' show openDetails, openSearch, openLibrary, runUpdate, routeObserver;
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
  // Hero index lives in a ValueNotifier, not in State, so the 10s rotation only
  // rebuilds the Hero backdrop via a ValueListenableBuilder — not the whole
  // screen (rails + every poster viewport), which a setState here would.
  final _heroIndex = ValueNotifier<int>(0);
  Timer? _rotateTimer;
  LoadStatus _status = LoadStatus.loading;

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
        _status = LoadStatus.ready;
      });
      _heroIndex.value = 0;
      _startRotation();
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _status = LoadStatus.error);
    }
  }

  // Hero cycles on its own, independent of card focus.
  void _startRotation() {
    if (_featured.length < 2) return;
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(
      const Duration(milliseconds: _heroRotateMs),
      (_) => _heroIndex.value = (_heroIndex.value + 1) % _featured.length,
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
    _heroIndex.dispose();
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
      case LoadStatus.idle:
      case LoadStatus.loading:
        return const _ScreenLoader();
      case LoadStatus.error:
        return const _ScreenMsg('Failed to load. Check the network / API key.');
      case LoadStatus.ready:
        // Wire sidebar items to real handlers. Home is the active screen so
        // Home is a no-op; the rest are placeholders pending their own screens.
        final navItems = withHandlers({
          NavId.search: () => openSearch(context),
          NavId.library: () => openLibrary(context),
          NavId.update: () => runUpdate(context),
        });
        return Stack(
          children: [
            SingleChildScrollView(
              controller: _pageController,
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Only the backdrop rebuilds when the hero index rotates; the
                  // rails below stay put (they don't listen to _heroIndex).
                  ValueListenableBuilder<int>(
                    valueListenable: _heroIndex,
                    builder: (context, index, _) => ui.Hero(
                      media: _featured.isNotEmpty
                          ? _featured[index % _featured.length]
                          : null,
                    ),
                  ),
                  // Pull the rails up into the base of the hero (margin-top: -80).
                  // Inset the rails column by the sidebar gutter so the rail
                  // titles/first posters clear the collapsed sidebar (the rest
                  // of the row scrolls under it, like the web mask).
                  Transform.translate(
                    offset: const Offset(0, -AppSizes.railsOverlap),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        left: AppSizes.sidebarContentPad - AppSizes.pagePadding,
                        bottom: 64,
                      ),
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
            ),
            // Fixed left sidebar overlaying the hero. Lives inside the
            // FocusScopeProvider so its items register with Home's controller.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Sidebar(items: navItems, currentId: NavId.home),
            ),
          ],
        );
    }
  }
}

/// Full-screen loading state: the classic Apple activity spinner, centred.
/// [radius] is in design units — the app-wide DesignScaler upscales it to the
/// TV's real resolution like the rest of the UI.
class _ScreenLoader extends StatelessWidget {
  const _ScreenLoader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: const Center(
        child: AppleSpinner(),
      ),
    );
  }
}

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
