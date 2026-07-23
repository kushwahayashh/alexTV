/// Stream API client — chains through the AlexStream backend to resolve a
/// TMDB title to a playable stream URL. Handles movies and series.
/// Ported from src/api/stream.ts.

library;

import 'dart:convert';
import 'package:http/http.dart' as http;

const _base = 'https://alexhasitbig--alexstream-serve.modal.run';

class VideoFile {
  final int fid;
  final String fileName;
  final String ext;
  final String resLabel;
  final String fileSize;
  final int? season;
  final int? episode;

  const VideoFile({
    required this.fid,
    required this.fileName,
    required this.ext,
    required this.resLabel,
    required this.fileSize,
    required this.season,
    required this.episode,
  });

  factory VideoFile.fromJson(Map<String, dynamic> j) => VideoFile(
    fid: (j['fid'] as num).toInt(),
    fileName: (j['file_name'] ?? '') as String,
    ext: (j['ext'] ?? '') as String,
    resLabel: (j['resLabel'] ?? '') as String,
    fileSize: (j['file_size'] ?? '') as String,
    season: (j['season'] as num?)?.toInt(),
    episode: (j['episode'] as num?)?.toInt(),
  );
}

class Folder {
  final int fid;
  final String fileName;

  const Folder({required this.fid, required this.fileName});

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
    fid: (j['fid'] as num).toInt(),
    fileName: (j['file_name'] ?? '') as String,
  );
}

class SeriesResolve {
  final String shareKey;
  final List<Folder> folders;
  final List<VideoFile> rootVideoFiles;

  const SeriesResolve({
    required this.shareKey,
    required this.folders,
    required this.rootVideoFiles,
  });
}

class _FileListing {
  final List<VideoFile> videoFiles;
  final List<Folder> folders;

  const _FileListing({required this.videoFiles, required this.folders});
}

class StreamLink {
  final String url;
  final String quality;
  final String ext;
  final String speed;

  const StreamLink({
    required this.url,
    required this.quality,
    required this.ext,
    required this.speed,
  });

  factory StreamLink.fromJson(Map<String, dynamic> j) => StreamLink(
    url: (j['url'] ?? '') as String,
    quality: (j['quality'] ?? '') as String,
    ext: (j['ext'] ?? '') as String,
    speed: (j['speed'] ?? '') as String,
  );
}

Future<Map<String, dynamic>> _getJson(String path) async {
  final res = await http.get(Uri.parse('$_base$path'));
  if (res.statusCode != 200) {
    throw Exception('$path → ${res.statusCode}');
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// A FebBox web subtitle for a file, scraped + converted to WebVTT by the
/// backend. English-only; [url] is an absolute URL serving the VTT file.
class WebSub {
  final String label;
  final String url;

  const WebSub({required this.label, required this.url});
}

/// Strip a subtitle filename down to a menu label: drop the extension and
/// collapse dots/underscores to spaces so the release name is readable.
String _cleanSubLabel(String fileName) {
  var s = fileName.replaceAll(
    RegExp(r'\.(srt|vtt|ass)$', caseSensitive: false),
    '',
  );
  s = s.replaceAll(RegExp(r'[._]+'), ' ').trim();
  return s.isEmpty ? 'English' : s;
}

/// Fetch FebBox web subtitles for a file (by [fid]). The backend already filters
/// to English and serves VTT; we de-dupe by label and resolve relative URLs.
Future<List<WebSub>> getWebSubs(int fid) async {
  final data = await _getJson('/api/subtitles?fid=$fid');
  final raw = (data['subtitles'] as List?) ?? const [];
  final seen = <String>{};
  final out = <WebSub>[];
  for (final j in raw.cast<Map<String, dynamic>>()) {
    final rel = (j['url'] ?? '') as String;
    if (rel.isEmpty) continue;
    final label = _cleanSubLabel(
      (j['langName'] ?? j['lang'] ?? 'English') as String,
    );
    if (!seen.add(label)) continue; // drop duplicate filenames
    out.add(
      WebSub(label: label, url: rel.startsWith('http') ? rel : '$_base$rel'),
    );
  }
  return out;
}

/// Resolve a TMDB title+year to a ShowBox ID.
Future<int> _resolveTitle(String title, String year, String type) async {
  final data = await _getJson(
    '/api/resolve?title=${Uri.encodeComponent(title)}&year=$year&type=$type',
  );
  final id = data['id'];
  if (id == null) throw Exception('Could not resolve title');
  return id as int;
}

/// Get a FebBox share key from a ShowBox ID. type: 1=movie, 2=tv
Future<String> _getShareKey(int showboxId, int type) async {
  final data = await _getJson('/api/share-key?id=$showboxId&type=$type');
  final key = data['shareKey'];
  if (key == null) throw Exception('Could not get share key');
  return key as String;
}

/// List a FebBox share directory. parentId '0' is the share root.
Future<_FileListing> _getFiles(String shareKey, [String parentId = '0']) async {
  final data = await _getJson(
    '/api/files?shareKey=$shareKey&parentId=$parentId',
  );
  final rawVideo = (data['videoFiles'] as List?) ?? const [];
  final rawFiles = (data['files'] as List?) ?? const [];
  final rawFolders =
      (data['folders'] as List?) ??
      rawFiles.where((f) => f['is_dir'] == 1).toList();
  return _FileListing(
    videoFiles: rawVideo
        .cast<Map<String, dynamic>>()
        .map(VideoFile.fromJson)
        .toList(),
    folders: rawFolders
        .cast<Map<String, dynamic>>()
        .map(Folder.fromJson)
        .toList(),
  );
}

/// Get stream links for a specific file.
Future<List<StreamLink>> getLinks(int fid) async {
  final data = await _getJson('/api/links?fid=$fid');
  final raw = (data['links'] as List?) ?? const [];
  return raw.cast<Map<String, dynamic>>().map(StreamLink.fromJson).toList();
}

/// Full resolve chain for a movie: title+year → ShowBox ID → share key → files.
/// Returns the video files so the user can pick which one to play.
Future<List<VideoFile>> resolveMovie(String title, String year) async {
  final id = await _resolveTitle(title, year, 'movie');
  final shareKey = await _getShareKey(id, 1);
  return (await _getFiles(shareKey)).videoFiles;
}

Future<SeriesResolve> resolveSeries(String title, String year) async {
  final id = await _resolveTitle(title, year, 'tv');
  final shareKey = await _getShareKey(id, 2);
  final files = await _getFiles(shareKey);
  return SeriesResolve(
    shareKey: shareKey,
    folders: files.folders,
    rootVideoFiles: files.videoFiles,
  );
}

Future<List<VideoFile>> getSeasonFiles(String shareKey, int folderFid) async {
  return (await _getFiles(shareKey, folderFid.toString())).videoFiles;
}
