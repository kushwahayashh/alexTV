import 'dart:async';
import 'package:flutter/material.dart';
import '../api/tmdb.dart' as api;
import '../components/header_button.dart';
import '../components/hero.dart' as ui;
import '../components/rail.dart';
import '../components/update_button.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

const _heroRotateMs = 10000;

class Home extends StatefulWidget {
  final void Function(api.Media) onSelect;
  final VoidCallback onOpenSearch;

  /// False while Details is on top. Home stays mounted (so its data, scroll and
  /// focused card survive) but must not hold keyboard focus or react to keys.
  final bool active;
  const Home({
    super.key,
    required this.onSelect,
    required this.onOpenSearch,
    this.active = true,
  });

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
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
  void didUpdateWidget(Home old) {
    super.didUpdateWidget(old);
    // Returning from Details: reclaim keyboard focus so D-pad keys route here
    // again. The FocusController still holds the previously-focused card, so
    // the visual highlight and scroll position are already intact.
    if (widget.active && !old.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keyboardNode.requestFocus();
      });
    } else if (!widget.active && old.active) {
      // Going behind Details: release focus so Details' handler gets the keys.
      _keyboardNode.unfocus();
    }
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
    _rotateTimer?.cancel();
    _pageController.dispose();
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      // No PopScope here — the app shell owns the Home-level Back so it isn't
      // double-handled while Details is mounted on top.
      body: FocusScopeProvider(
        controller: _focus,
        child: Focus(
          focusNode: _keyboardNode,
          autofocus: true,
          canRequestFocus: widget.active,
          onKeyEvent: (_, event) => widget.active
              ? _focus.handleKey(
                  event,
                  () => debugPrint('BACK pressed'),
                  _releaseToTop,
                )
              : KeyEventResult.ignored,
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
                          onSelect: widget.onOpenSearch,
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
                          onSelect: widget.onSelect,
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
