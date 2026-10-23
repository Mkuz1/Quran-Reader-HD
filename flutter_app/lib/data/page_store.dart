import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/quran.dart';
import '../core/storage.dart';

enum PageStoreState { online, downloading, installing, installed, failed }

/// The mushaf pages are not shipped in the app. Users either install all 604 from the GitHub release
/// (one zip) or read online, where each page is fetched from the repository as it is opened.
class PageStore extends ChangeNotifier {
  PageStoreState state;
  double progress = 0;
  String? error;
  bool _cancelled = false;
  http.Client? _client;

  PageStore() : state = _marker.existsSync() ? PageStoreState.installed : PageStoreState.online;

  static File get _marker => File(p.join(Paths.pages.path, '.installed'));

  bool get isInstalled => state == PageStoreState.installed;
  bool get isBusy => state == PageStoreState.downloading || state == PageStoreState.installing;

  void _set(PageStoreState s) {
    state = s;
    notifyListeners();
  }

  Future<void> install() async {
    if (isBusy || isInstalled) return;
    _cancelled = false;
    progress = 0;
    error = null;
    _set(PageStoreState.downloading);
    final zip = File(p.join(Directory.systemTemp.path, 'QuranReaderHD-Pages-${DateTime.now().millisecondsSinceEpoch}.zip'));
    try {
      final client = _client = http.Client();
      final response = await client.send(http.Request('GET', Remote.pagesArchive));
      if (response.statusCode != 200) throw DownloadException(response.statusCode, Remote.pagesArchive);
      final total = response.contentLength ?? Remote.pagesArchiveMB * 1000000;
      final sink = zip.openWrite();
      var received = 0;
      var lastNotified = 0.0;
      await for (final chunk in response.stream) {
        if (_cancelled) break;
        sink.add(chunk);
        received += chunk.length;
        progress = (received / total).clamp(0, 1);
        if (progress - lastNotified > 0.01) {
          lastNotified = progress;
          notifyListeners();
        }
      }
      await sink.close();
      if (_cancelled) throw const _Cancelled();
      _set(PageStoreState.installing);
      await _unpack(zip.path);
      _set(PageStoreState.installed);
    } on _Cancelled {
      _set(PageStoreState.online);
    } catch (e) {
      if (_cancelled) {
        _set(PageStoreState.online);
      } else {
        error = e.toString();
        _set(PageStoreState.failed);
      }
    } finally {
      _client?.close();
      _client = null;
      if (zip.existsSync()) zip.deleteSync();
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
    _set(PageStoreState.online);
  }

  /// Deletes installed pages; reading continues online.
  void remove() {
    if (isBusy) return;
    try {
      Paths.pages.deleteSync(recursive: true);
    } catch (_) {}
    _set(PageStoreState.online);
  }

  /// Unzips into a staging folder, checks all 604 pages are present, then moves them into place.
  static Future<void> _unpack(String zipPath) async {
    final staging = Directory(p.join(Directory.systemTemp.path, 'QuranReaderHD-pages-${DateTime.now().millisecondsSinceEpoch}'));
    try {
      await extractFileToDisk(zipPath, staging.path);
      final names = [for (var i = 1; i <= Quran.pageCount; i++) 'page${pad3(i)}.png'];
      bool hasAll(String dir) => names.every((n) => File(p.join(dir, n)).existsSync());
      // The archive may hold the files at its root or inside one folder.
      var root = staging.path;
      if (!hasAll(root)) {
        root = staging
                .listSync()
                .whereType<Directory>()
                .map((d) => d.path)
                .firstWhere((d) => File(p.join(d, names.first)).existsSync(), orElse: () => staging.path);
      }
      if (!hasAll(root)) throw Exception('Could not unpack the downloaded archive.');
      final dest = Paths.pages.path;
      for (final n in names) {
        final target = File(p.join(dest, n));
        if (target.existsSync()) target.deleteSync();
        final src = File(p.join(root, n));
        try {
          src.renameSync(target.path);
        } on FileSystemException {
          src.copySync(target.path); // staging can be on another volume
        }
      }
      File(p.join(dest, '.installed')).writeAsStringSync('');
      // Pages now installed don't need their online copies.
      try {
        Paths.onlinePages.deleteSync(recursive: true);
      } catch (_) {}
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Page PNG location: installed copy, else the online cache, downloading it first.
Future<File> pageFile(int page) async {
  final name = 'page${pad3(page)}.png';
  final installed = File(p.join(Paths.pages.path, name));
  if (installed.existsSync()) return installed;
  return Downloader.fetch(Remote.pageImage(page), File(p.join(Paths.onlinePages.path, name)));
}
