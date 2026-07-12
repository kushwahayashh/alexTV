import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../api/series.dart';
import '../api/stream.dart' as stream;
import '../api/tmdb.dart';
import '../components/hero.dart' show FadeIn, Scrim;
import '../components/fade_image.dart';
import '../components/player.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

class Details extends StatefulWidget {
  final Media media;
  final VoidCallback onBack;

  const Details({super.key, required this.media, required this.onBack});

  @override
  State<Details> createState() => _DetailsState();
}

class _EpisodePlay {
  final int fid;
  final String label;

  const _EpisodePlay({required this.fid, required this.label});
}

class _DetailsState extends State<Details> {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  final _pageController = ScrollController();
  bool _showPlayer = false;
  _EpisodePlay? _episodePlay;
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
  bool get _playerOpen => _showPlayer || _episodePlay != null;

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
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_pageController.hasClients) return;
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
    } catch (_) {
      if (!mounted) return;
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _episodes = const []);
    }
  }

  void _openPlayer() {
    if (!_isTv) {
      setState(() => _showPlayer = true);
      return;
    }
    final episodes = _episodes;
    if (_playFid != null && episodes != null && episodes.isNotEmpty) {
      _openEpisode(episodes.first, 0);
    }
  }

  void _openEpisode(stream.VideoFile episode, int index) {
    final num = episode.episode ?? index + 1;
    setState(() {
      _episodePlay = _EpisodePlay(
        fid: episode.fid,
        label: '${widget.media.title} · ${epTitle(episode, num)}',
      );
    });
  }

  void _closeMoviePlayer() {
    setState(() => _showPlayer = false);
    _restoreDetailsFocus();
  }

  void _closeEpisodePlayer() {
    setState(() => _episodePlay = null);
    _restoreDetailsFocus();
  }

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _playerOpen) return;
          widget.onBack();
        },
        child: FocusScopeProvider(
          controller: _focus,
          child: Focus(
            focusNode: _keyboardNode,
            autofocus: true,
            onKeyEvent: (_, event) =>
                _focus.handleKey(event, widget.onBack, null),
            child: Stack(
              fit: StackFit.expand,
              children: [
                SingleChildScrollView(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailsHero(
                        media: media,
                        isTv: _isTv,
                        seasons: _seasons,
                        flatEpisodes: _flatEpisodes,
                        playId: _playId,
                        watchLaterId: _watchLaterId,
                      ),
                      if (_isTv)
                        _SeriesSection(
                          seasons: _seasons,
                          activeIdx: _activeIdx,
                          episodes: _episodes,
                          error: _seriesError,
                          playerOpen: _playerOpen,
                          pageController: _pageController,
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
                if (_showPlayer)
                  Player(media: media, onClose: _closeMoviePlayer),
                if (_episodePlay != null)
                  Player(
                    media: media,
                    startFid: _episodePlay!.fid,
                    title: _episodePlay!.label,
                    onClose: _closeEpisodePlayer,
                  ),
              ],
            ),
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
          const Scrim(),
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
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(isTv ? 'Series' : 'Movie'),
              if (media.year.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(media.year),
              ],
              const SizedBox(width: 16),
              Text('✔ ${media.rating == 0 ? '—' : media.rating}'),
              if (isTv &&
                  seasons != null &&
                  flatEpisodes == null &&
                  seasons!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Text(
                  '${seasons!.length} Season${seasons!.length > 1 ? 's' : ''}',
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
              label: '▶ Play',
              id: playId,
              focused: controller.isFocused(playId),
            ),
            const SizedBox(width: 14),
            _DetailsButton(
              label: '+ Watch Later',
              id: watchLaterId,
              focused: controller.isFocused(watchLaterId),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeriesSection extends StatelessWidget {
  final List<SeasonOption>? seasons;
  final int activeIdx;
  final List<stream.VideoFile>? episodes;
  final String? error;
  final bool playerOpen;
  final ScrollController pageController;
  final ValueChanged<int> onSeason;
  final void Function(stream.VideoFile episode, int index) onEpisode;

  const _SeriesSection({
    required this.seasons,
    required this.activeIdx,
    required this.episodes,
    required this.error,
    required this.playerOpen,
    required this.pageController,
    required this.onSeason,
    required this.onEpisode,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.pagePadding,
        0,
        AppSizes.pagePadding,
        72,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.only(top: 18, bottom: 16),
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
                const SizedBox(width: 28),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    clipBehavior: Clip.none,
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
                                    label: seasons![i].label,
                                    active: i == activeIdx,
                                    enabled: !playerOpen,
                                    onSelect: () => onSeason(i),
                                  ),
                                ),
                            ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (error != null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 4),
              child: Text(
                "This series isn't available to stream right now.",
                style: TextStyle(color: AppColors.muted, fontSize: 16.8),
              ),
            )
          else if (episodes == null)
            for (int i = 0; i < 5; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: const _EpisodeSkeleton(),
              )
          else if (episodes!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24, horizontal: 4),
              child: Text(
                'No episodes found for this season.',
                style: TextStyle(color: AppColors.muted, fontSize: 16.8),
              ),
            )
          else
            for (int i = 0; i < episodes!.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: _EpisodeRow(
                  num: episodes![i].episode ?? i + 1,
                  title: epTitle(episodes![i], episodes![i].episode ?? i + 1),
                  fileName: episodes![i].fileName,
                  resLabel: episodes![i].resLabel,
                  enabled: !playerOpen,
                  pageController: pageController,
                  onSelect: () => onEpisode(episodes![i], i),
                ),
              ),
        ],
      ),
    );
  }
}

class _SeasonTab extends StatefulWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onSelect;

  const _SeasonTab({
    required this.label,
    required this.active,
    required this.enabled,
    required this.onSelect,
  });

  @override
  State<_SeasonTab> createState() => _SeasonTabState();
}

class _SeasonTabState extends State<_SeasonTab> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: widget.onSelect,
        active: widget.enabled,
      );
      _registered = true;
    }
  }

  @override
  void didUpdateWidget(_SeasonTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_registered && oldWidget.enabled != widget.enabled) {
      _controller.setActive(_id, widget.enabled);
    }
  }

  @override
  void dispose() {
    _controller.unregister(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = FocusScopeProvider.of(context);
    final focused = controller.isFocused(_id);
    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onSelect : null,
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
            child: Text(
              widget.label,
              style: TextStyle(
                color: focused
                    ? AppColors.bg
                    : widget.active
                    ? AppColors.text
                    : AppColors.muted,
                fontSize: 15.7,
                fontWeight: FontWeight.w700,
              ),
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

class _EpisodeRowState extends State<_EpisodeRow> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: widget.onSelect,
        onFocused: _scrollIntoView,
        active: widget.enabled,
      );
      _registered = true;
    }
  }

  @override
  void didUpdateWidget(_EpisodeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_registered && oldWidget.enabled != widget.enabled) {
      _controller.setActive(_id, widget.enabled);
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
    final target = (revealTop - 286).clamp(
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
    final childColor = focused ? AppColors.bg : AppColors.muted;
    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onSelect : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: focused ? AppColors.focus : AppColors.surface,
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
  final String label;
  final int id;
  final bool focused;

  const _DetailsButton({
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
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: focused ? AppColors.bg : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _SeasonSkeleton extends StatelessWidget {
  const _SeasonSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Container(
        width: 116,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
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
