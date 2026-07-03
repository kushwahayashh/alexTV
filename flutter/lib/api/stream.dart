/// Stream API client — chains through the AlexStream backend to resolve a
/// TMDB title to a playable stream URL. Movie-only for now.
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

  const VideoFile({
    required this.fid,
    required this.fileName,
    required this.ext,
    required this.resLabel,
    required this.fileSize,
  });

  factory VideoFile.fromJson(Map<String, dynamic> j) => VideoFile(
        fid: j['fid'] as int,
        fileName: (j['file_name'] ?? '') as String,
        ext: (j['ext'] ?? '') as String,
        resLabel: (j['resLabel'] ?? '') as String,
        fileSize: (j['file_size'] ?? '') as String,
      );
}

class StreamLink {
  final String url;
  final String quality;
  final String ext;
  final String speed;
  final String proxiedUrl;

  const StreamLink({
    required this.url,
    required this.quality,
    required this.ext,
    required this.speed,
    required this.proxiedUrl,
  });

  factory StreamLink.fromJson(Map<String, dynamic> j) => StreamLink(
        url: (j['url'] ?? '') as String,
        quality: (j['quality'] ?? '') as String,
        ext: (j['ext'] ?? '') as String,
        speed: (j['speed'] ?? '') as String,
        proxiedUrl: (j['proxiedUrl'] ?? '') as String,
      );
}

Future<Map<String, dynamic>> _getJson(String path) async {
  final res = await http.get(Uri.parse('$_base$path'));
  if (res.statusCode != 200) {
    throw Exception('$path → ${res.statusCode}');
  }
  return jsonDecode(res.body) as Map<String, dynamic>;
}

/// Resolve a TMDB title+year to a ShowBox ID.
Future<int> _resolveTitle(String title, String year, String type) async {
  final data = await _getJson(
      '/api/resolve?title=${Uri.encodeComponent(title)}&year=$year&type=$type');
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

/// List video files in a FebBox share.
Future<List<VideoFile>> _getFiles(String shareKey) async {
  final data = await _getJson('/api/files?shareKey=$shareKey');
  final raw = (data['videoFiles'] as List?) ?? const [];
  return raw.cast<Map<String, dynamic>>().map(VideoFile.fromJson).toList();
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
  return _getFiles(shareKey);
}
