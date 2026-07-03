import 'dart:async';
import 'package:flutter/material.dart';
import '../api/tmdb.dart' as api;
import '../components/hero.dart' as ui;
import '../components/rail.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

const _heroRotateMs = 7000;

class Home extends StatefulWidget {
  const Home({super.key});

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

  Future<void> _load() async {
    try {
      final data = await api.fetchHomeRails();
      if (!mounted) return;
      setState(() {
        _rails = data;
        // Feature trending items that actually have a backdrop to show.
        _featured = (data.isNotEmpty ? data[0].items : <api.Media>[])
            .where((m) => m.backdropPath != null)
            .take(6)
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
      _pageController.animateTo(0,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
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
      body: FocusScopeProvider(
        controller: _focus,
        child: Focus(
          focusNode: _keyboardNode,
          autofocus: true,
          onKeyEvent: (_, event) => _focus.handleKey(
            event,
            () => debugPrint('BACK pressed'),
            _releaseToTop,
          ),
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
              ui.Hero(
                media: _featured.isNotEmpty ? _featured[_heroIndex] : null,
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
                          onSelect: (m) => debugPrint('SELECT ${m.title}'),
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
