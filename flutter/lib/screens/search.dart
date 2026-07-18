import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../api/tmdb.dart' as api;
import '../components/fade_image.dart';
import '../components/header_button.dart';
import '../focus/focus_engine.dart';
import '../main.dart' show openDetails;
import '../theme.dart';

const _debounceMs = 350;

enum _Status { idle, loading, ready }

class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

class _SearchState extends State<Search> {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  final _fieldNode = FocusNode();
  final _queryController = TextEditingController();
  final _pageController = ScrollController();

  late final int _fieldId;
  Timer? _debounce;
  List<api.Media> _results = [];
  _Status _status = _Status.idle;

  @override
  void initState() {
    super.initState();
    _fieldId = _focus.register(
      isInput: true,
      onFocused: () => _fieldNode.requestFocus(),
      onSelect: () => _fieldNode.requestFocus(),
    );
    _queryController.addListener(_onQueryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardNode.requestFocus();
      _focus.requestFocus(_fieldId);
      _fieldNode.requestFocus();
    });
  }

  void _onQueryChanged() {
    final q = _queryController.text.trim();
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _status = _Status.idle;
      });
      return;
    }

    setState(() => _status = _Status.loading);
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () async {
      try {
        final items = await api.searchMulti(q);
        if (!mounted || q != _queryController.text.trim()) return;
        setState(() {
          _results = items;
          _status = _Status.ready;
        });
      } catch (e) {
        debugPrint('$e');
        if (!mounted || q != _queryController.text.trim()) return;
        setState(() {
          _results = [];
          _status = _Status.ready;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.unregister(_fieldId);
    _pageController.dispose();
    _queryController.dispose();
    _fieldNode.dispose();
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    // Back/Escape pops Search off the Navigator, returning to Home.
    return _focus.handleKey(event, () => Navigator.of(context).maybePop(), null);
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
          onKeyEvent: _handleKey,
          child: SingleChildScrollView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.pagePadding,
                24,
                AppSizes.pagePadding,
                64,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    // Pin to the top so the pill buttons stay at y=24 like
                    // Home's navbar. The search field is taller than the pills,
                    // so centering (the Row default) would nudge the buttons
                    // down a few px and read as a jitter during the cross-fade
                    // transition from Home.
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HeaderButton(
                            label: 'Home',
                            onSelect: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 12),
                          const HeaderButton(label: 'Search'),
                          const SizedBox(width: 12),
                          const HeaderButton(label: 'Library'),
                        ],
                      ),
                      const SizedBox(width: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _SearchField(
                          fieldId: _fieldId,
                          controller: _queryController,
                          focusNode: _fieldNode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  _SearchBody(
                    status: _status,
                    results: _results,
                    query: _queryController.text.trim(),
                    pageController: _pageController,
                    onSelect: (m) => openDetails(context, m),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final int fieldId;
  final TextEditingController controller;
  final FocusNode focusNode;

  const _SearchField({
    required this.fieldId,
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final focus = FocusScopeProvider.of(context);
    return KeyedSubtree(
      key: focus.keyOf(fieldId),
      child: TextField(
        focusNode: focusNode,
        controller: controller,
        spellCheckConfiguration: SpellCheckConfiguration.disabled(),
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 16.8,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          hintText: 'Search movies & series…',
          hintStyle: const TextStyle(color: AppColors.muted),
          prefixIcon: const Icon(
            Icons.search,
            color: AppColors.muted,
            size: 20,
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 13,
          ),
        ),
      ),
    );
  }
}

class _SearchBody extends StatelessWidget {
  final _Status status;
  final List<api.Media> results;
  final String query;
  final ScrollController pageController;
  final void Function(api.Media) onSelect;

  const _SearchBody({
    required this.status,
    required this.results,
    required this.query,
    required this.pageController,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (status == _Status.loading) {
      return Wrap(
        spacing: AppSizes.posterGap,
        runSpacing: 32,
        children: List.generate(14, (_) => const _SkeletonPoster()),
      );
    }

    if (status == _Status.ready && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 4),
        child: Text(
          'No results for "$query".',
          style: const TextStyle(color: AppColors.muted, fontSize: 17.6),
        ),
      );
    }

    if (results.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSizes.posterGap,
      runSpacing: 32,
      children: [
        for (final media in results)
          _SearchPosterCard(
            key: ValueKey('${media.mediaType}-${media.id}'),
            media: media,
            pageController: pageController,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

class _SearchPosterCard extends StatefulWidget {
  final api.Media media;
  final ScrollController pageController;
  final void Function(api.Media) onSelect;

  const _SearchPosterCard({
    super.key,
    required this.media,
    required this.pageController,
    required this.onSelect,
  });

  @override
  State<_SearchPosterCard> createState() => _SearchPosterCardState();
}

class _SearchPosterCardState extends State<_SearchPosterCard> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: () => widget.onSelect(widget.media),
        onFocused: _scrollIntoView,
      );
      _registered = true;
    }
  }

  @override
  void dispose() {
    _controller.unregister(_id);
    super.dispose();
  }

  void _scrollIntoView() {
    final ctx = _controller.keyOf(_id).currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final viewport = RenderAbstractViewport.maybeOf(box);
    final page = widget.pageController;
    if (!page.hasClients || viewport == null) return;

    final revealTop = viewport.getOffsetToReveal(box, 0.0).offset;
    final target = (revealTop - 130).clamp(
      page.position.minScrollExtent,
      page.position.maxScrollExtent,
    );
    page.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(_id);
    final media = widget.media;

    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: GestureDetector(
        onTap: () => widget.onSelect(media),
        child: AnimatedScale(
          scale: focused ? AppSizes.posterFocusScale : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: Container(
            width: AppSizes.posterW,
            height: AppSizes.posterH,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSizes.radius),
              boxShadow: focused
                  ? const [
                      BoxShadow(
                        color: Color(0xB3000000),
                        blurRadius: 34,
                        offset: Offset(0, 12),
                      ),
                    ]
                  : const [],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              border: Border.all(
                color: focused ? AppColors.focus : Colors.transparent,
                width: 3,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: media.posterPath != null
                ? FadeImage(
                    src: api.Img.poster(media.posterPath),
                    errorWidget: const SizedBox.shrink(),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonPoster extends StatefulWidget {
  const _SkeletonPoster();

  @override
  State<_SkeletonPoster> createState() => _SkeletonPosterState();
}

class _SkeletonPosterState extends State<_SkeletonPoster>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.5,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: AppSizes.posterW,
        height: AppSizes.posterH,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppSizes.radius),
        ),
      ),
    );
  }
}
