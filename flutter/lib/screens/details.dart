import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../api/series.dart';
import '../api/stream.dart' as stream;
import '../api/tmdb.dart';
import '../components/hero.dart' show FadeIn;
import '../components/fade_image.dart';
import '../components/nav_icons.dart';
import '../components/player.dart';
import '../focus/focus_engine.dart';
import '../focus/focusable.dart';
import '../routes.dart';
import '../theme.dart';

class Details extends StatefulWidget {
  final Media media;

  const Details({super.key, required this.media});

  @override
  State<Details> createState() => _DetailsState();
}

class _DetailsState extends State<Details> {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  final _pageController = ScrollController();
  // Horizontal scroll for the season pill strip. Persistent (not rebuilt) so
  // focusing a season can smooth-scroll it to centre, mirroring the React
  // bar's scrollIntoView({ inline: 'center' }).
  final _seasonScroll = ScrollController();
  late final int _playId;
  late final int _watchLaterId;

  String? _shareKey;
  List<SeasonOption>? _seasons;
  List<stream.VideoFile>? _flatEpisodes;
  int _activeIdx = 0;
  List<stream.VideoFile>? _episodes;
  String? _seriesError;
  int? _playFid;

  bool get _isTv => widget.media.mediaType == 'tv';

  @override
  void initState() {
    super.initState();
    _playId = _focus.register(onSelect: _openPlayer, onFocused: _scrollToTop);
    _watchLaterId = _focus.register(
      onSelect: () => debugPrint('WATCH LATER ${widget.media.title}'),
      onFocused: _scrollToTop,
    );
    if (_isTv) _resolveSeries();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardNode.requestFocus();
      _focus.requestFocus(_playId);
    });
  }

  @override
  void dispose() {
    _focus.unregister(_playId);
    _focus.unregister(_watchLaterId);
    _pageController.dispose();
    _seasonScroll.dispose();
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_pageController.hasClients ||
        !_pageController.position.hasContentDimensions) {
      return;
    }
    _pageController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  Future<void> _resolveSeries() async {
    setState(() {
      _seasons = null;
      _episodes = null;
      _flatEpisodes = null;
      _seriesError = null;
      _activeIdx = 0;
      _playFid = null;
    });

    try {
      final resolved = await stream.resolveSeries(
        widget.media.title,
        widget.media.year,
      );
      if (!mounted) return;
      final built = buildSeasons(resolved.folders);
      setState(() {
        _shareKey = resolved.shareKey;
        _seasons = built;
        if (built.length == 1 && built.first.fid == null) {
          _flatEpisodes = resolved.rootVideoFiles;
        }
      });
      await _loadActiveSeason();
    } catch (e) {
      if (!mounted) return;
      debugPrint('resolveSeries failed: $e');
      setState(() {
        _seriesError = "This series isn't available to stream right now.";
        _seasons = const [];
        _episodes = const [];
      });
    }
  }

  Future<void> _loadActiveSeason() async {
    if (!_isTv || _seasons == null) return;
    final season = _seasons!.isEmpty ? null : _seasons![_activeIdx];
    if (season == null) return;

    final flat = _flatEpisodes;
    if (flat != null) {
      final ordered = orderedEpisodes(flat);
      if (!mounted) return;
      setState(() {
        _episodes = ordered;
        _playFid ??= ordered.isNotEmpty ? ordered.first.fid : null;
      });
      return;
    }

    if (season.fid == null || _shareKey == null) return;
    setState(() => _episodes = null);
    try {
      final files = await stream.getSeasonFiles(_shareKey!, season.fid!);
      if (!mounted) return;
      final ordered = orderedEpisodes(files);
      setState(() {
        _episodes = ordered;
        _playFid ??= ordered.isNotEmpty ? ordered.first.fid : null;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('getSeasonFiles failed: $e');
      setState(() => _episodes = const []);
    }
  }

  void _openPlayer() {
    if (!_isTv) {
      _pushPlayer(Player(media: widget.media, onClose: _popPlayer));
      return;
    }
    final episodes = _episodes;
    if (_playFid != null && episodes != null && episodes.isNotEmpty) {
      _openEpisode(episodes.first, 0);
    }
  }

  void _openEpisode(stream.VideoFile episode, int index) {
    final num = episode.episode ?? index + 1;
    _pushPlayer(
      Player(
        media: widget.media,
        startFid: episode.fid,
        title: '${widget.media.title} · ${epTitle(episode, num)}',
        onClose: _popPlayer,
      ),
    );
  }

  /// Push the player as a non-opaque overlay route so the Details page keeps
  /// painting (and blurring) behind it. Hardware Back pops exactly this route;
  /// when it returns, restore keyboard focus to the Play button. Because the
  /// player is its own route, Details' key handler stops receiving events while
  /// it's up — no flag needed to mute it.
  void _pushPlayer(Player player) {
    pushGuarded(
      context,
      fadeRoute(player, opaque: false),
    ).then((_) => _restoreDetailsFocus());
  }

  void _popPlayer() => Navigator.of(context).pop();

  void _restoreDetailsFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardNode.requestFocus();
      _focus.requestFocus(_playId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    // No PopScope needed: Details is a pushed route, so hardware Back pops it
    // back to Home via the Navigator. The custom key handler still routes
    // Escape/Back on desktop through the focus engine, which pops explicitly.
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FocusScopeProvider(
        controller: _focus,
        child: Focus(
          focusNode: _keyboardNode,
          autofocus: true,
          onKeyEvent: (_, event) =>
              _focus.handleKey(event, () => Navigator.of(context).maybePop(), null),
          child: CustomScrollView(
            controller: _pageController,
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _DetailsHero(
                  media: media,
                  isTv: _isTv,
                  seasons: _seasons,
                  flatEpisodes: _flatEpisodes,
                  playId: _playId,
                  watchLaterId: _watchLaterId,
                ),
              ),
              if (_isTv)
                ..._seriesSlivers(
                  seasons: _seasons,
                  activeIdx: _activeIdx,
                  episodes: _episodes,
                  error: _seriesError,
                  pageController: _pageController,
                  seasonController: _seasonScroll,
                  onSeason: (index) {
                    setState(() {
                      _activeIdx = index;
                      _episodes = null;
                    });
                    _loadActiveSeason();
                  },
                  onEpisode: _openEpisode,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsHero extends StatelessWidget {
  final Media media;
  final bool isTv;
  final List<SeasonOption>? seasons;
  final List<stream.VideoFile>? flatEpisodes;
  final int playId;
  final int watchLaterId;

  const _DetailsHero({
    required this.media,
    required this.isTv,
    required this.seasons,
    required this.flatEpisodes,
    required this.playId,
    required this.watchLaterId,
  });

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * (isTv ? 0.72 : 1.0);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.backdropPath != null)
            FadeImage(
              key: ValueKey('bg-${media.id}'),
              src: Img.backdrop(media.backdropPath),
              alignment: const Alignment(0, -0.64),
            ),
          const _DetailsScrim(),
          Positioned(
            left: AppSizes.pagePadding,
            bottom: 20,
            width: MediaQuery.of(context).size.width * 0.50,
            child: FadeIn(
              key: ValueKey('content-${media.id}'),
              child: _DetailsContent(
                media: media,
                seasons: seasons,
                flatEpisodes: flatEpisodes,
                playId: playId,
                watchLaterId: watchLaterId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsScrim extends StatelessWidget {
  const _DetailsScrim();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppColors.bg.withValues(alpha: 0.95),
                AppColors.bg.withValues(alpha: 0.40),
                Colors.transparent,
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                AppColors.bg,
                AppColors.bg.withValues(alpha: 0.85),
                AppColors.bg.withValues(alpha: 0.35),
                Colors.transparent,
              ],
              stops: const [0.0, 0.12, 0.30, 0.55],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailsContent extends StatelessWidget {
  final Media media;
  final List<SeasonOption>? seasons;
  final List<stream.VideoFile>? flatEpisodes;
  final int playId;
  final int watchLaterId;

  const _DetailsContent({
    required this.media,
    required this.seasons,
    required this.flatEpisodes,
    required this.playId,
    required this.watchLaterId,
  });

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final isTv = media.mediaType == 'tv';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          media.title,
          style: const TextStyle(
            fontSize: 57.6,
            height: 1.05,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
            shadows: [
              Shadow(
                color: Color(0x99000000),
                blurRadius: 18,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DefaultTextStyle.merge(
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: 0.64,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(isTv ? 'SERIES' : 'MOVIE'),
              if (media.year.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(media.year),
              ],
              const SizedBox(width: 16),
              // Split label and value into two Texts in a center-aligned row so
              // Poppins's lining figures (cap-height) and the mixed-case
              // "Rating" optically align instead of sharing one baseline where
              // the number rides above the lowercase. Em dash dropped — it
              // floats at the em-box center in this font, not the baseline.
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('RATING'),
                  const SizedBox(width: 6),
                  Text(media.rating == 0 ? 'N/A' : '${media.rating}'),
                ],
              ),
              if (isTv &&
                  seasons != null &&
                  flatEpisodes == null &&
                  seasons!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(
                  '${seasons!.length} SEASON${seasons!.length > 1 ? 'S' : ''}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          media.overview,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFD7DEE5),
            fontSize: 16.3,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailsButton(
              svg: NavIcons.playFilled,
              label: 'Play',
              id: playId,
              focused: controller.isFocused(playId),
            ),
            const SizedBox(width: 14),
            _DetailsButton(
              svg: NavIcons.plusFilled,
              label: 'Watch Later',
              id: watchLaterId,
              focused: controller.isFocused(watchLaterId),
            ),
          ],
        ),
      ],
    );
  }
}

List<Widget> _seriesSlivers({
  required List<SeasonOption>? seasons,
  required int activeIdx,
  required List<stream.VideoFile>? episodes,
  required String? error,
  required ScrollController pageController,
  required ScrollController seasonController,
  required ValueChanged<int> onSeason,
  required void Function(stream.VideoFile episode, int index) onEpisode,
}) {
  return [
    SliverPersistentHeader(
      pinned: true,
      delegate: _SeriesBarDelegate(
        seasons: seasons,
        activeIdx: activeIdx,
        seasonController: seasonController,
        onSeason: onSeason,
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.pagePadding,
        6,
        AppSizes.pagePadding,
        72,
      ),
      sliver: _seriesListSliver(
        episodes: episodes,
        error: error,
        pageController: pageController,
        onEpisode: onEpisode,
      ),
    ),
  ];
}

Widget _seriesListSliver({
  required List<stream.VideoFile>? episodes,
  required String? error,
  required ScrollController pageController,
  required void Function(stream.VideoFile episode, int index) onEpisode,
}) {
  if (error != null) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 4),
        child: Text(
          "This series isn't available to stream right now.",
          style: TextStyle(color: AppColors.muted, fontSize: 16.8),
        ),
      ),
    );
  }

  if (episodes == null) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
          child: const _EpisodeSkeleton(),
        ),
        childCount: 5,
      ),
    );
  }

  if (episodes.isEmpty) {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 24, horizontal: 4),
        child: Text(
          'No episodes found for this season.',
          style: TextStyle(color: AppColors.muted, fontSize: 16.8),
        ),
      ),
    );
  }

  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) => Padding(
        padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
        child: _EpisodeRow(
          num: episodes[index].episode ?? index + 1,
          title: epTitle(episodes[index], episodes[index].episode ?? index + 1),
          fileName: episodes[index].fileName,
          resLabel: episodes[index].resLabel,
          enabled: true,
          pageController: pageController,
          onSelect: () => onEpisode(episodes[index], index),
        ),
      ),
      childCount: episodes.length,
    ),
  );
}

class _SeriesBarDelegate extends SliverPersistentHeaderDelegate {
  final List<SeasonOption>? seasons;
  final int activeIdx;
  final ScrollController seasonController;
  final ValueChanged<int> onSeason;

  const _SeriesBarDelegate({
    required this.seasons,
    required this.activeIdx,
    required this.seasonController,
    required this.onSeason,
  });

  // Fixed bar height. The child is forced to exactly this height so its paint
  // extent always equals the declared extent — otherwise, if the content lays
  // out shorter (e.g. a fallback font with smaller metrics before Poppins
  // loads, as on web), the pinned sliver throws "layoutExtent exceeds
  // paintExtent".
  static const double _barHeight = 82;

  @override
  double get minExtent => _barHeight;

  @override
  double get maxExtent => _barHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: _barHeight,
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(
        AppSizes.pagePadding,
        18,
        AppSizes.pagePadding,
        16,
      ),
      child: Row(
        children: [
          const Text(
            'Episodes',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 21.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          // 22 (not 28) because the pill strip below carries a 6px horizontal
          // pad for the focus-scale breathing room (React's `margin:-6px`
          // trick). 22 + 6 = 28, matching the React heading→pill gap exactly.
          const SizedBox(width: 22),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth <= 0
                    ? 1.0
                    : constraints.maxWidth;
                final fadeStop = (28.0 / width).clamp(0.0, 0.5).toDouble();
                // Always-on 28px edge fade on both sides, matching the React
                // .series__seasons mask-image 1:1 (fade is static, not
                // scroll-aware).
                return ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: [0, fadeStop, 1 - fadeStop, 1],
                  ).createShader(bounds),
                  blendMode: BlendMode.dstIn,
                  // Clip horizontally only: pills scrolled off the left mustn't
                  // paint over the "Episodes" heading, but the focused pill's
                  // 1.06 scale must be free to overflow vertically without being
                  // cut (the 82px bar is vertically tight). React gets this room
                  // from the scroll container's `padding:6px; margin:-6px`; a
                  // horizontal-only clip is the equivalent here.
                  child: ClipRect(
                    clipper: _HorizontalClipper(),
                    child: SingleChildScrollView(
                      controller: seasonController,
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      // No box clip here — the ClipRect above handles horizontal
                      // clipping and leaves vertical overflow (the focus scale)
                      // free.
                      clipBehavior: Clip.none,
                      // 6px horizontal breathing room = React's `padding:6px`
                      // on .series__seasons. It seats the first/last pill 6px
                      // inside the scroll content so a focused pill's 1.06 scale
                      // at either edge isn't hard-clipped, and the 28px fade eats
                      // ~22px of the edge pill (not its whole edge). Vertical
                      // scale room is already granted by _HorizontalClipper, so
                      // this stays horizontal-only (React's -6px margin is folded
                      // into the 22px heading gap above).
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: seasons == null
                            ? [
                                for (int i = 0; i < 3; i++)
                                  const _SeasonSkeleton(),
                              ]
                            : [
                                for (int i = 0; i < seasons!.length; i++)
                                  Padding(
                                    padding: EdgeInsets.only(
                                      right: i == seasons!.length - 1 ? 0 : 12,
                                    ),
                                    child: _SeasonTab(
                                      key: ValueKey(
                                        '${seasons![i].fid ?? 'flat'}-$i',
                                      ),
                                      label: seasons![i].label,
                                      active: i == activeIdx,
                                      stripController: seasonController,
                                      onSelect: () => onSeason(i),
                                    ),
                                  ),
                              ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SeriesBarDelegate oldDelegate) {
    return seasons != oldDelegate.seasons ||
        activeIdx != oldDelegate.activeIdx;
  }
}

/// Clips only the horizontal axis, leaving vertical overflow free. Lets the
/// season strip hide pills scrolled past the left/right edges (so they don't
/// paint over the "Episodes" heading) while a focused pill's 1.06 scale can
/// still overflow the bar's tight height without being cut top/bottom.
class _HorizontalClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) =>
      // Full width, but a generous vertical margin so the scaled focus pill is
      // never clipped top/bottom (the bar itself is only ~82px tall).
      Rect.fromLTRB(0, -size.height, size.width, size.height * 2);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _SeasonTab extends StatefulWidget {
  final String label;
  final bool active;
  final ScrollController stripController;
  final VoidCallback onSelect;

  const _SeasonTab({
    super.key,
    required this.label,
    required this.active,
    required this.stripController,
    required this.onSelect,
  });

  @override
  State<_SeasonTab> createState() => _SeasonTabState();
}

class _SeasonTabState extends State<_SeasonTab> with FocusableState {
  @override
  int registerFocusable(FocusController controller) =>
      controller.register(onSelect: widget.onSelect, onFocused: _centerInStrip);

  /// Scroll the horizontal season strip so this pill sits at its horizontal
  /// center — mirrors the React `scrollIntoView({ inline: 'center' })` so
  /// D-padding across seasons keeps the focused pill in view instead of leaving
  /// it clipped under the edge fade.
  void _centerInStrip() {
    final strip = widget.stripController;
    if (!strip.hasClients || !strip.position.hasContentDimensions) return;
    final ctx = focusKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box == null || !box.attached || viewport == null) return;
    // Offset that brings the pill's center to the viewport's center (0.5).
    final target = viewport.getOffsetToReveal(box, 0.5).offset.clamp(
      strip.position.minScrollExtent,
      strip.position.maxScrollExtent,
    );
    strip.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final focused = isFocused;
    final textColor = focused
        ? AppColors.bg
        : widget.active
        ? AppColors.text
        : AppColors.muted;
    return KeyedSubtree(
      key: focusKey,
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: focused ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            decoration: BoxDecoration(
              color: focused
                  ? AppColors.focus
                  : widget.active
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            // Merge onto the inherited DefaultTextStyle (which carries Poppins
            // from the theme) instead of replacing it — a bare TextStyle
            // here would drop the font family back to Roboto.
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              style: DefaultTextStyle.of(context).style.copyWith(
                color: textColor,
                fontSize: 15.7,
                fontWeight: FontWeight.w700,
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  final int num;
  final String title;
  final String fileName;
  final String resLabel;
  final bool enabled;
  final ScrollController pageController;
  final VoidCallback onSelect;

  const _EpisodeRow({
    required this.num,
    required this.title,
    required this.fileName,
    required this.resLabel,
    required this.enabled,
    required this.pageController,
    required this.onSelect,
  });

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> with FocusableState {
  @override
  int registerFocusable(FocusController controller) => controller.register(
    onSelect: widget.onSelect,
    onFocused: _scrollIntoView,
    active: widget.enabled,
  );

  @override
  void didUpdateWidget(_EpisodeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      focusController.setActive(focusId, widget.enabled);
    }
  }

  void _scrollIntoView() => verticalScrollIntoView(
    key: focusKey,
    page: widget.pageController,
    lift: AppSizes.episodeRowScrollLift,
  );

  @override
  Widget build(BuildContext context) {
    final focused = isFocused;
    final childColor = focused ? AppColors.bg : AppColors.muted;
    return KeyedSubtree(
      key: focusKey,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onSelect : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            // Neutral translucent white over the dark bg — same black/white
            // family as the Play button (HeaderButton), not the --surface
            // token. Mirrors the React .ep-row background.
            color: focused
                ? AppColors.focus
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${widget.num}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: childColor,
                    fontSize: 20.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: focused ? AppColors.bg : AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Opacity(
                      opacity: focused ? 0.7 : 1.0,
                      child: Text(
                        widget.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: childColor,
                          fontSize: 13.1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.resLabel.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(
                  widget.resLabel,
                  style: TextStyle(
                    color: childColor,
                    fontSize: 13.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsButton extends StatelessWidget {
  final String svg;
  final String label;
  final int id;
  final bool focused;

  const _DetailsButton({
    required this.svg,
    required this.label,
    required this.id,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    return KeyedSubtree(
      key: controller.keyOf(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: focused
              ? AppColors.focus
              : Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NavIcon(
              svg: svg,
              size: 20,
              color: focused ? AppColors.bg : AppColors.text,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: focused ? AppColors.bg : AppColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeasonSkeleton extends StatefulWidget {
  const _SeasonSkeleton();

  @override
  State<_SeasonSkeleton> createState() => _SeasonSkeletonState();
}

class _SeasonSkeletonState extends State<_SeasonSkeleton>
    with SingleTickerProviderStateMixin {
  // Opacity pulse 0.5 ↔ 1.0 over 1.8s, matching the React `skeletonPulse`
  // keyframes (and the Search poster skeleton).
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
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: 116,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSizes.radius),
      ),
    );
  }
}
