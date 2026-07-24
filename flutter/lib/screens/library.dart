import 'dart:convert';

import 'package:flutter/material.dart';
import '../api/library.dart';
import '../api/stream.dart';
import '../components/sidebar.dart';
import '../components/spinner.dart';
import '../focus/focus_engine.dart';
import '../focus/focusable.dart';
import '../main.dart' show openSearch, runUpdate;
import '../theme.dart';

/// Fetch saved watch-progress for [paths] from the native store. Returns a map
/// of backend path -> progress fraction (0..1). Empty on any error or when
/// nothing is tracked, so callers can treat "no bar" as the default.
Future<Map<String, double>> fetchPlaybackProgress(List<String> paths) async {
  if (paths.isEmpty) return const {};
  try {
    final raw = await playerChannel.invokeMethod<String>('getProgress', {
      'paths': paths,
    });
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final out = <String, double>{};
    decoded.forEach((path, value) {
      final progress = (value is Map) ? value['progress'] : null;
      if (progress is num) out[path] = progress.toDouble().clamp(0.0, 1.0);
    });
    return out;
  } catch (e) {
    // Progress is a nice-to-have (the fill bars); a native-channel or decode
    // failure just means no bars, never a broken listing. Log for diagnosis but
    // fall back to "nothing tracked".
    debugPrint('fetchPlaybackProgress failed: $e');
    return const {};
  }
}

/// File-manager style library, backed by the AlexTV Library backend. The
/// current path is held in state; the global Back button climbs into the
/// parent folder if we're drilled in, otherwise it pops the screen. Selecting a
/// folder drills into it; selecting a file resolves a stream URL and launches
/// the native player.
class Library extends StatefulWidget {
  const Library({super.key});

  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> with WidgetsBindingObserver {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  final _pageController = ScrollController();

  /// Backend path of the current level; "/" is the root.
  String _path = '/';
  LibraryListing? _listing;
  LoadStatus _status = LoadStatus.loading;

  /// Watch-progress fraction (0..1) per file path, read back from the native
  /// store. Only files with a saved position appear; missing = no bar.
  Map<String, double> _progress = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(_path);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The native player runs as a separate Activity; when it closes we resume.
    // Re-read progress so a file's bar reflects the position just watched.
    if (state == AppLifecycleState.resumed) _refreshProgress();
  }

  Future<void> _load(String path) async {
    setState(() => _status = LoadStatus.loading);
    try {
      final data = await fetchLibrary(path);
      if (!mounted || path != _path) return;
      setState(() {
        _listing = data;
        _status = LoadStatus.ready;
      });
      // Drilling into a folder disposes the previously focused row, so focus is
      // left cleared (see FocusController.unregister). Seat it on the first row
      // of the new listing once the sliver has built it, so the user isn't left
      // with nothing highlighted. Guarded on "nothing focused" so it never
      // steals focus from the sidebar rail.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _focus.focusId != null) return;
        _focus.focusFirstContent();
      });
      _refreshProgress();
    } catch (e) {
      debugPrint('$e');
      if (!mounted || path != _path) return;
      setState(() => _status = LoadStatus.error);
    }
  }

  /// Pull watch-progress for the currently-listed files from the native store
  /// and update the fill bars. Called after a listing loads and after playback
  /// returns (a file's position may have advanced or cleared on completion).
  Future<void> _refreshProgress() async {
    final listing = _listing;
    if (listing == null) return;
    final paths = [
      for (final item in listing.items)
        if (item is FileItem) item.file.path,
    ];
    if (paths.isEmpty) return;
    final progress = await fetchPlaybackProgress(paths);
    if (!mounted) return;
    setState(() => _progress = progress);
  }

  void _openFolder(String folderPath) {
    setState(() => _path = folderPath);
    if (_pageController.hasClients) _pageController.jumpTo(0);
    _load(folderPath);
  }

  Future<void> _playFile(LibraryFile file) async {
    // Resolve the (fast-tunnel) stream URL, then hand it to the native
    // ExoPlayer. The Library streams a single file directly, so there's no
    // quality/file picker — launch straight into playback.
    try {
      final url = await fetchStreamUrl(file.path);
      if (!mounted) return;
      final dot = file.name.lastIndexOf('.');
      final ext = dot >= 0 ? file.name.substring(dot + 1) : '';
      await playerChannel.invokeMethod('play', {
        'url': url,
        'ext': ext,
        'title': file.name,
        // Stable backend path: the key the native player stores watch-progress
        // under (so we can resume + draw the progress bar).
        'mediaPath': file.path,
        'subLabels': const <String>[],
        'subUrls': const <String>[],
      });
    } catch (e) {
      debugPrint('Could not start playback: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start playback.')),
      );
    }
  }

  /// Back: climb into the parent folder if drilled in, otherwise pop the screen.
  void _handleBack() {
    if (_path != '/') {
      _openFolder(parentOf(_path));
    } else {
      Navigator.of(context).maybePop();
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    return _focus.handleKey(event, _handleBack, null);
  }

  @override
  Widget build(BuildContext context) {
    // Wire sidebar items: Home climbs out of the Library route, Search pushes
    // the Search screen, Library is a no-op (already on it). The rest are
    // placeholders pending their own screens.
    final navItems = withHandlers({
      NavId.home: () => Navigator.of(context).maybePop(),
      NavId.search: () => openSearch(context),
      NavId.update: () => runUpdate(context),
    });
    return PopScope(
      // At root, let Back pop the whole Library route. Drilled into a folder,
      // block the pop and climb to the parent instead — otherwise hardware Back
      // (dispatched by the Navigator, not our focus engine) would tear down the
      // whole screen instead of stepping out one level.
      canPop: _path == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openFolder(parentOf(_path));
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: FocusScopeProvider(
          controller: _focus,
          child: Focus(
            focusNode: _keyboardNode,
            autofocus: true,
            onKeyEvent: _handleKey,
            child: Stack(
              children: [
                CustomScrollView(
                  controller: _pageController,
                  physics: const ClampingScrollPhysics(),
                  // Left padding clears the collapsed sidebar
                  // (sidebarContentPad); the rest matches the original Library
                  // padding. A CustomScrollView + SliverList.builder lazily
                  // builds (and registers a focus entry for) only the rows near
                  // the viewport, so a folder with hundreds of files no longer
                  // builds every row up front.
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.sidebarContentPad,
                        24,
                        AppSizes.pagePadding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _Breadcrumb(path: _path, onNavigate: _openFolder),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSizes.sidebarContentPad,
                        20,
                        AppSizes.pagePadding,
                        64,
                      ),
                      sliver: _bodySliver(),
                    ),
                  ],
                ),
                // Fixed left sidebar overlaying the content. Lives inside the
                // FocusScopeProvider so its items register with Library's
                // controller.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Sidebar(items: navItems, currentId: NavId.library),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The listing area as a sliver: a centered spinner while loading, a message
  /// on error / empty, otherwise a lazily-built list of rows. Using
  /// [SliverList.builder] means each row (and its focus registration) is created
  /// only as it scrolls near the viewport, so large folders stay responsive.
  Widget _bodySliver() {
    if (_status == LoadStatus.loading) {
      // The body starts ~84 design units below the top (top padding + header
      // row + gap). To land the spinner at true screen centre we subtract that
      // offset twice: the box centre is at offset + (height-2*offset)/2 =
      // height/2.
      return SliverToBoxAdapter(
        child: SizedBox(
          height: MediaQuery.of(context).size.height - 168,
          child: const Center(
            child: AppleSpinner(),
          ),
        ),
      );
    }
    if (_status == LoadStatus.error) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 120),
          child: Center(
            child: Text(
              'Failed to load the library.',
              style: TextStyle(color: AppColors.muted, fontSize: 18.4),
            ),
          ),
        ),
      );
    }
    final items = _listing?.items ?? const <LibraryItem>[];
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 120),
          child: Center(
            child: Text(
              'This folder is empty.',
              style: TextStyle(color: AppColors.muted, fontSize: 18.4),
            ),
          ),
        ),
      );
    }

    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _LibraryRow(
            key: ValueKey(switch (item) {
              FolderItem(:final folder) => folder.path,
              FileItem(:final file) => file.path,
            }),
            item: item,
            progress: switch (item) {
              FileItem(:final file) => _progress[file.path] ?? 0.0,
              _ => 0.0,
            },
            pageController: _pageController,
            onOpenFolder: _openFolder,
            onPlayFile: _playFile,
          ),
        );
      },
    );
  }
}

/// Current location trail, always rooted at "Home" then each folder level
/// ("Home / Breaking Bad / S01"). The whole bar is one focusable item — like a
/// list row — and selecting it climbs one folder up.
class _Breadcrumb extends StatefulWidget {
  final String path;
  final void Function(String) onNavigate;
  const _Breadcrumb({required this.path, required this.onNavigate});

  @override
  State<_Breadcrumb> createState() => _BreadcrumbState();
}

class _BreadcrumbState extends State<_Breadcrumb> with FocusableState {
  @override
  int registerFocusable(FocusController controller) =>
      controller.register(onSelect: _select);

  void _select() => widget.onNavigate(parentOf(widget.path));

  @override
  Widget build(BuildContext context) {
    final focused = isFocused;

    final names = widget.path.split('/').where((s) => s.isNotEmpty).toList();
    // Home at the root, then one crumb per folder level.
    final labels = ['Home', ...names];

    final parts = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      if (i > 0) {
        parts.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '/',
              style: TextStyle(
                color: focused ? AppColors.bg : const Color(0x47FFFFFF),
                fontSize: 17.6,
              ),
            ),
          ),
        );
      }
      final isLast = i == labels.length - 1;
      parts.add(
        Text(
          labels[i],
          style: TextStyle(
            color: focused
                ? AppColors.bg
                : (isLast ? AppColors.text : AppColors.muted),
            fontSize: 17.6,
            fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: KeyedSubtree(
        key: focusKey,
        child: GestureDetector(
          onTap: _select,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            // Span the full content width like the React crumbbar (a block-level
            // flex container), rather than shrinking to the trail's width.
            width: double.infinity,
            transformAlignment: Alignment.center,
            transform: focused
                ? (Matrix4.identity()..scaleByDouble(1.015, 1.015, 1.015, 1.0))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              color: focused ? AppColors.focus : AppColors.surface,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  // "Level up" arrow — go up one folder.
                  Icons.subdirectory_arrow_left_rounded,
                  size: 22,
                  color: focused ? AppColors.bg : AppColors.muted,
                ),
                const SizedBox(width: 18),
                ...parts,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryRow extends StatefulWidget {
  final LibraryItem item;
  /// Watch-progress fraction (0..1); 0 hides the bar.
  final double progress;
  final ScrollController pageController;
  final void Function(String) onOpenFolder;
  final void Function(LibraryFile) onPlayFile;

  const _LibraryRow({
    super.key,
    required this.item,
    required this.progress,
    required this.pageController,
    required this.onOpenFolder,
    required this.onPlayFile,
  });

  @override
  State<_LibraryRow> createState() => _LibraryRowState();
}

class _LibraryRowState extends State<_LibraryRow> with FocusableState {
  bool get _isFolder => widget.item is FolderItem;

  @override
  int registerFocusable(FocusController controller) =>
      controller.register(onSelect: _select, onFocused: _scrollIntoView);

  void _select() {
    switch (widget.item) {
      case FolderItem(:final folder):
        widget.onOpenFolder(folder.path);
      case FileItem(:final file):
        widget.onPlayFile(file);
    }
  }

  void _scrollIntoView() => verticalScrollIntoView(
    key: focusKey,
    page: widget.pageController,
    lift: AppSizes.libraryRowScrollLift,
  );

  @override
  Widget build(BuildContext context) {
    final focused = isFocused;
    final onColor = focused ? AppColors.bg : AppColors.text;
    final metaColor = focused
        ? const Color(0x9E000000)
        : AppColors.muted;

    final name = switch (widget.item) {
      FolderItem(:final folder) => folder.name,
      FileItem(:final file) => file.name,
    };

    return KeyedSubtree(
      key: focusKey,
      child: GestureDetector(
        onTap: _select,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transformAlignment: Alignment.center,
          transform: focused
              ? (Matrix4.identity()..scaleByDouble(1.015, 1.015, 1.015, 1.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: focused ? AppColors.focus : AppColors.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      _isFolder ? Icons.folder_rounded : Icons.web_asset,
                      size: 24,
                      color: focused ? AppColors.bg : AppColors.muted,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onColor,
                          fontSize: 16.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ..._badges(focused, metaColor),
                  ],
                ),
              ),
              if (widget.progress > 0) _progressBar(focused),
            ],
          ),
        ),
      ),
    );
  }

  /// Thin watch-progress bar floating just above the row bottom, inset from the
  /// sides to line up under the content. A dull track with a white fill at the
  /// watched fraction (min 2% so a sliver always shows); on a focused (white)
  /// row the fill flips dark so it stays visible.
  Widget _progressBar(bool focused) {
    final track = focused ? const Color(0x1F000000) : const Color(0x14FFFFFF);
    final fill = focused ? AppColors.bg : AppColors.text;
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 3,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(color: track),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: widget.progress.clamp(0.02, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: fill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _badges(bool focused, Color textColor) {
    // Folders carry no meta; files show plain-text size only.
    if (widget.item is! FileItem) return const [];
    final file = (widget.item as FileItem).file;

    final out = <Widget>[];
    if (file.sizeFormatted != null) {
      out.add(
        Text(
          file.sizeFormatted!,
          style: TextStyle(
            color: textColor,
            fontSize: 14.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return out;
  }
}
