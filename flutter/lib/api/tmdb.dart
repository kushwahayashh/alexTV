/// TMDB data layer. Read-only fetch via Cloudflare Workers proxy, same as the
/// React prototype. Ported from src/api/tmdb.ts. Note: for production the
/// key should move server-side / into secure storage — fine inline for this
/// local prototype.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;

const _apiKey = '8bd45cfb804f84ce85fa6accd833d6a1';
const _base = 'https://api.themoviedb.org/3';
const _proxy = 'https://lunaissohot.lunastar0003.workers.dev/?destination=';

class Img {
  static String poster(String? path) =>
      path != null ? 'https://image.tmdb.org/t/p/w342$path' : '';
  static String backdrop(String? path) =>
      path != null ? 'https://image.tmdb.org/t/p/original$path' : '';
}

class Media {
  final int id;
  final String title;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double rating;
  final String year;
  final String mediaType; // 'movie' | 'tv'

  const Media({
    required this.id,
    required this.title,
    required this.posterPath,
    required this.backdropPath,
    required this.overview,
    required this.rating,
    required this.year,
    required this.mediaType,
  });

  factory Media.fromJson(Map<String, dynamic> item, String fallbackType) {
    final date = (item['release_date'] ?? item['first_air_date'] ?? '') as String;
    final rawType = item['media_type'];
    final type = (rawType == 'tv' || rawType == 'movie') ? rawType : fallbackType;
    final vote = (item['vote_average'] as num?)?.toDouble() ?? 0;
    return Media(
      id: item['id'] as int,
      title: (item['title'] ?? item['name'] ?? 'Untitled') as String,
      posterPath: item['poster_path'] as String?,
      backdropPath: item['backdrop_path'] as String?,
      overview: (item['overview'] ?? '') as String,
      rating: (vote * 10).round() / 10,
      year: date.isNotEmpty ? date.substring(0, 4) : '',
      mediaType: type as String,
    );
  }
}

class Rail {
  final String title;
  final List<Media> items;
  const Rail({required this.title, required this.items});
}

Future<List<Map<String, dynamic>>> _get(String path) async {
  final sep = path.contains('?') ? '&' : '?';
  final targetUrl = '$_base$path${sep}api_key=$_apiKey';
  final res = await http.get(Uri.parse('$_proxy${Uri.encodeComponent(targetUrl)}'));
  if (res.statusCode != 200) {
    throw Exception('TMDB ${res.statusCode} on $path');
  }
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final results = (json['results'] as List?) ?? const [];
  return results.cast<Map<String, dynamic>>();
}

Future<List<Rail>> fetchHomeRails() async {
  final results = await Future.wait([
    _get('/trending/all/week'),
    _get('/movie/popular'),
    _get('/movie/top_rated'),
    _get('/tv/popular'),
    _get('/movie/upcoming'),
  ]);

  List<Media> map(List<Map<String, dynamic>> raw, String type) =>
      raw.map((i) => Media.fromJson(i, type)).toList();

  return [
    Rail(title: 'Trending This Week', items: map(results[0], 'movie')),
    Rail(title: 'Popular Movies', items: map(results[1], 'movie')),
    Rail(title: 'Top Rated', items: map(results[2], 'movie')),
    Rail(title: 'Popular Series', items: map(results[3], 'tv')),
    Rail(title: 'Coming Soon', items: map(results[4], 'movie')),
  ];
}
