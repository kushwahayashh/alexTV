import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../api/library.dart';
import '../components/header_button.dart';
import '../focus/focus_engine.dart';
import '../theme.dart';

enum _Status { loading, ready, error }

/// Method channel to the native full-screen ExoPlayer (see MainActivity /
/// PlayerActivity). Same channel the Details Player uses; the Library resolves
/// a direct stream URL and launches playback with no quality/file picker.
const _playerChannel = MethodChannel('com.example.alextv/player');

/// File-manager style library, backed by the AlexTV Library backend. The
/// current path is held in state; the global Back button climbs into the
/// parent folder if we're drilled in, otherwise it pops the screen. Selecting a
/// folder drills into it; selecting a file will play it (wiring lands later).
class Library extends StatefulWidget {
  const Library({super.key});

  @override
  State<Library> createState() => _LibraryState();
}

class _LibraryState extends State<Library> {
  final _focus = FocusController();
  final _keyboardNode = FocusNode();
  final _pageController = ScrollController();

  /// Backend path of the current level; "/" is the root.
  String _path = '/';
  LibraryListing? _listing;
  _Status _status = _Status.loading;

  @override
  void initState() {
    super.initState();
    _load(_path);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _keyboardNode.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load(String path) async {
    setState(() => _status = _Status.loading);
    try {
      final data = await fetchLibrary(path);
      if (!mounted || path != _path) return;
      setState(() {
        _listing = data;
        _status = _Status.ready;
      });
    } catch (e) {
      debugPrint('$e');
      if (!mounted || path != _path) return;
      setState(() => _status = _Status.error);
    }
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
      final dot = file.name.lastIndexOf('.');
      final ext = dot >= 0 ? file.name.substring(dot + 1) : '';
      await _playerChannel.invokeMethod('play', {
        'url': url,
        'ext': ext,
        'title': file.name,
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
                  _Breadcrumb(path: _path),
                  const SizedBox(height: 20),
                  _LibraryBody(
                    status: _status,
                    listing: _listing,
                    pageController: _pageController,
                    onOpenFolder: _openFolder,
                    onPlayFile: _playFile,
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

/// Current location as the folder path below the root ("Breaking Bad / S01").
/// Empty at the root — we already know we're in the Library.
class _Breadcrumb extends StatelessWidget {
  final String path;
  const _Breadcrumb({required this.path});

  @override
  Widget build(BuildContext context) {
    final names = path.split('/').where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) return const SizedBox.shrink();

    final parts = <Widget>[];
    for (var i = 0; i < names.length; i++) {
      if (i > 0) {
        parts.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '›',
              style: TextStyle(color: Color(0x47FFFFFF), fontSize: 17.6),
            ),
          ),
        );
      }
      final isLast = i == names.length - 1;
      parts.add(
        Text(
          names[i],
          style: TextStyle(
            color: isLast ? AppColors.text : AppColors.muted,
            fontSize: 17.6,
            fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(children: parts),
    );
  }
}

class _LibraryBody extends StatelessWidget {
  final _Status status;
  final LibraryListing? listing;
  final ScrollController pageController;
  final void Function(String) onOpenFolder;
  final void Function(LibraryFile) onPlayFile;

  const _LibraryBody({
    required this.status,
    required this.listing,
    required this.pageController,
    required this.onOpenFolder,
    required this.onPlayFile,
  });

  @override
  Widget build(BuildContext context) {
    if (status == _Status.loading) {
      // The body starts ~84 design units below the top (top padding + header
      // row + gap). To land the spinner at true screen centre we subtract that
      // offset twice: the box centre is at offset + (height-2*offset)/2 =
      // height/2.
      return SizedBox(
        height: MediaQuery.of(context).size.height - 168,
        child: const Center(
          child: CupertinoActivityIndicator(radius: 18, color: AppColors.muted),
        ),
      );
    }
    if (status == _Status.error) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 120),
        child: Center(
          child: Text(
            'Failed to load the library.',
            style: TextStyle(color: AppColors.muted, fontSize: 18.4),
          ),
        ),
      );
    }
    final items = listing?.items ?? const [];
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 120),
        child: Center(
          child: Text(
            'This folder is empty.',
            style: TextStyle(color: AppColors.muted, fontSize: 18.4),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _LibraryRow(
              key: ValueKey(switch (item) {
                FolderItem(:final folder) => folder.path,
                FileItem(:final file) => file.path,
              }),
              item: item,
              pageController: pageController,
              onOpenFolder: onOpenFolder,
              onPlayFile: onPlayFile,
            ),
          ),
      ],
    );
  }
}

class _LibraryRow extends StatefulWidget {
  final LibraryItem item;
  final ScrollController pageController;
  final void Function(String) onOpenFolder;
  final void Function(LibraryFile) onPlayFile;

  const _LibraryRow({
    super.key,
    required this.item,
    required this.pageController,
    required this.onOpenFolder,
    required this.onPlayFile,
  });

  @override
  State<_LibraryRow> createState() => _LibraryRowState();
}

class _LibraryRowState extends State<_LibraryRow> {
  late FocusController _controller;
  late int _id;
  bool _registered = false;

  bool get _isFolder => widget.item is FolderItem;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_registered) {
      _controller = FocusScopeProvider.read(context);
      _id = _controller.register(
        onSelect: _select,
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

  void _select() {
    switch (widget.item) {
      case FolderItem(:final folder):
        widget.onOpenFolder(folder.path);
      case FileItem(:final file):
        widget.onPlayFile(file);
    }
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
    final target = (revealTop - 150).clamp(
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
    final onColor = focused ? AppColors.bg : AppColors.text;
    final metaColor = focused
        ? const Color(0x9E000000)
        : AppColors.muted;

    final name = switch (widget.item) {
      FolderItem(:final folder) => folder.name,
      FileItem(:final file) => file.name,
    };

    return KeyedSubtree(
      key: _controller.keyOf(_id),
      child: GestureDetector(
        onTap: _select,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transformAlignment: Alignment.center,
          transform: focused
              ? (Matrix4.identity()..scaleByDouble(1.015, 1.015, 1.015, 1.0))
              : Matrix4.identity(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: focused ? AppColors.focus : AppColors.surface,
          ),
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
