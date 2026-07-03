import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads the latest release APK and hands it to the system installer.
///
/// The APK is written to a single fixed path and overwritten on every update,
/// so repeated updates never pile up multiple files in storage.
class Updater {
  static const _apkUrl =
      'https://github.com/kushwahayashh/alexTV/releases/download/latest/alexTV.apk';
  static const _fileName = 'alexTV-update.apk';

  /// Fetches the APK (replacing any previous download) then opens it, which
  /// triggers Android's install confirmation popup. Throws on network/IO error.
  static Future<void> downloadAndInstall() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_fileName');

    final res = await http.get(Uri.parse(_apkUrl));
    if (res.statusCode != 200) {
      throw HttpException('Download failed (HTTP ${res.statusCode})');
    }
    // Overwrite in place — same path every time, so no stale APKs accumulate.
    await file.writeAsBytes(res.bodyBytes, flush: true);

    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw Exception('Could not open installer: ${result.message}');
    }
  }
}
