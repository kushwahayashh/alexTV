import 'stream.dart';

class SeasonOption {
  final int? fid;
  final String label;
  final int number;

  const SeasonOption({
    required this.fid,
    required this.label,
    required this.number,
  });
}

bool isSeasonFolder(Folder folder) {
  return RegExp(
    r'^\s*(season\s*\d{1,2}|s\d{1,2})\s*$',
    caseSensitive: false,
  ).hasMatch(folder.fileName);
}

int seasonNumber(Folder folder) {
  final match = RegExp(r'\d+').firstMatch(folder.fileName);
  return match == null ? 0 : int.parse(match.group(0)!);
}

String _seasonLabel(Folder folder) {
  final n = seasonNumber(folder);
  return n == 0 ? 'Specials' : 'Season $n';
}

List<SeasonOption> buildSeasons(List<Folder> folders) {
  final seasonDirs = folders.where(isSeasonFolder).toList();
  final dirs = (seasonDirs.isNotEmpty ? seasonDirs : folders).toList()
    ..sort((a, b) {
      final an = seasonNumber(a);
      final bn = seasonNumber(b);
      return (an == 0 ? 1 << 30 : an).compareTo(bn == 0 ? 1 << 30 : bn);
    });

  if (dirs.isEmpty) {
    return const [SeasonOption(fid: null, label: 'Episodes', number: 1)];
  }

  return [
    for (final folder in dirs)
      SeasonOption(
        fid: folder.fid,
        label: _seasonLabel(folder),
        number: seasonNumber(folder),
      ),
  ];
}

int _resRank(String? resLabel) {
  final match = RegExp(r'\d+').firstMatch(resLabel ?? '');
  return match == null ? 0 : int.parse(match.group(0)!);
}

List<VideoFile> bestPerEpisode(List<VideoFile> episodes) {
  final best = <int, VideoFile>{};
  final unknown = <VideoFile>[];

  for (final ep in episodes) {
    final num = ep.episode;
    if (num == null) {
      unknown.add(ep);
      continue;
    }
    final current = best[num];
    if (current == null || _resRank(ep.resLabel) > _resRank(current.resLabel)) {
      best[num] = ep;
    }
  }

  return [...best.values, ...unknown];
}

int episodeSort(VideoFile a, VideoFile b) {
  final epCompare = (a.episode ?? 1000000000).compareTo(
    b.episode ?? 1000000000,
  );
  if (epCompare != 0) return epCompare;
  return _resRank(b.resLabel).compareTo(_resRank(a.resLabel));
}

List<VideoFile> orderedEpisodes(List<VideoFile> files) {
  return bestPerEpisode(files)..sort(episodeSort);
}

String epTitle(VideoFile file, int num) {
  final raw = file.fileName;
  final match = RegExp(
    r'[sS]\d{1,2}[eE]\d{1,3}[.\s_-]+(.+?)[.\s_-]+(?:\d{3,4}p|web|bluray|hdtv|x26|h26|hevc|aac|ddp|dts)',
    caseSensitive: false,
  ).firstMatch(raw);

  final captured = match?.group(1);
  if (captured != null) {
    final title = captured.replaceAll(RegExp(r'[.\s_-]+'), ' ').trim();
    if (title.isNotEmpty && !RegExp(r'^\d+$').hasMatch(title)) return title;
  }

  return 'Episode $num';
}
