/// Library API client — browses the AlexTV Library backend (FastAPI on Modal).
/// The stable URL serves the full API directly, so listing hits `/list?path=`
/// straight against it. Streaming should go through the fast tunnel, resolved
/// via `/download-url` when the player needs a URL.
/// Ported from src/api/library.ts.

library;

import 'dart:convert';
import 'package:http/http.dart' as http;

const _base = 'https://alexhasitbig--alextv-library-start.modal.run';

/// A playable media file in the library.
class LibraryFile {
  final String name;

  /// Backend path, e.g. "/Breaking Bad/S01E01.mkv".
  final String path;
  final int? size;

  /// Human-readable size badge, e.g. "2.4 GB".
  final String? sizeFormatted;

  /// Filename-derived resolution badge, e.g. "1080p", or null if unknown.
  final String? resolution;
  final double mtime;

  const LibraryFile({
    required this.name,
    required this.path,
    required this.size,
    required this.sizeFormatted,
    required this.resolution,
    required this.mtime,
  });

  factory LibraryFile.fromJson(Map<String, dynamic> j) => LibraryFile(
    name: (j['name'] ?? '') as String,
    path: (j['path'] ?? '') as String,
    size: (j['size'] as num?)?.toInt(),
    sizeFormatted: j['sizeFormatted'] as String?,
    resolution: j['resolution'] as String?,
    mtime: (j['mtime'] as num?)?.toDouble() ?? 0,
  );
}

/// A folder (a series, holding episode files).
class LibraryFolder {
  final String name;
  final String path;

  /// Number of media items inside, for the folder badge.
  final int itemCount;
  final double mtime;

  const LibraryFolder({
    required this.name,
    required this.path,
    required this.itemCount,
    required this.mtime,
  });

  factory LibraryFolder.fromJson(Map<String, dynamic> j) => LibraryFolder(
    name: (j['name'] ?? '') as String,
    path: (j['path'] ?? '') as String,
    itemCount: (j['itemCount'] as num?)?.toInt() ?? 0,
    mtime: (j['mtime'] as num?)?.toDouble() ?? 0,
  );
}

/// Union of the two row types; the backend tags each item with `type`.
sealed class LibraryItem {
  const LibraryItem();
}

class FolderItem extends LibraryItem {
  final LibraryFolder folder;
  const FolderItem(this.folder);
}

class FileItem extends LibraryItem {
  final LibraryFile file;
  const FileItem(this.file);
}

/// One level of the media tree.
class LibraryListing {
  /// Path that was listed ("/" at the root).
  final String path;

  /// Parent path, or null at the root.
  final String? parentPath;
  final List<LibraryItem> items;

  const LibraryListing({
    required this.path,
    required this.parentPath,
    required this.items,
  });
}

/// List one level of the media tree. Folders first, then files.
Future<LibraryListing> fetchLibrary(String path) async {
  final res = await http.get(
    Uri.parse('$_base/list?path=${Uri.encodeComponent(path)}'),
  );
  if (res.statusCode != 200) {
    throw Exception('Failed to load library (${res.statusCode})');
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final raw = (data['items'] as List?) ?? const [];
  final items = <LibraryItem>[];
  for (final j in raw.cast<Map<String, dynamic>>()) {
    if (j['type'] == 'folder') {
      items.add(FolderItem(LibraryFolder.fromJson(j)));
    } else {
      items.add(FileItem(LibraryFile.fromJson(j)));
    }
  }
  return LibraryListing(
    path: (data['path'] ?? '/') as String,
    parentPath: data['parentPath'] as String?,
    items: items,
  );
}

/// Resolve a playable stream URL for a file, preferring the fast tunnel the
/// backend hands back from `/download-url`. Falls back to a direct `/stream`
/// URL if that call fails.
Future<String> fetchStreamUrl(String path) async {
  try {
    final res = await http.get(
      Uri.parse('$_base/download-url?path=${Uri.encodeComponent(path)}'),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final url = data['url'];
      if (url is String && url.isNotEmpty) return url;
    }
  } catch (_) {
    // fall through to the direct stream URL
  }
  return '$_base/stream?path=${Uri.encodeComponent(path)}';
}

/// Parent path of a backend path, "/" at or above the root.
String parentOf(String path) {
  final trimmed = path.replaceAll(RegExp(r'/+$'), '');
  final idx = trimmed.lastIndexOf('/');
  if (idx <= 0) return '/';
  return trimmed.substring(0, idx);
}
