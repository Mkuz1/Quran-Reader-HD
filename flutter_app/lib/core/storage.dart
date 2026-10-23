import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'quran.dart';

/// On-disk locations: app support for kept data, the cache folder for pages read online.
class Paths {
  static late Directory _root;
  static late Directory _cache;

  static Future<void> init() async {
    _root = await getApplicationSupportDirectory();
    _cache = await getApplicationCacheDirectory();
  }

  /// Tests keep everything in one temporary folder.
  static void useDirectory(Directory d) => _root = _cache = d;

  static Directory dir(String name) {
    final d = Directory(p.join(_root.path, name));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Installed (downloaded) pages, kept until the user removes them.
  static Directory get pages => dir('pages');

  /// Pages fetched while reading online.
  static Directory get onlinePages {
    final d = Directory(p.join(_cache.path, 'pages'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Directory get data => dir('data');
  static Directory get text => dir('text');
  static Directory get words => dir('words');
  static Directory get cards => Directory(p.join(_cache.path, 'cards'))..createSync(recursive: true);
  static Directory audio(String reciter) => dir('audio/$reciter');
  static File get library => File(p.join(_root.path, 'library.json'));
}

String pad3(int n) => n.toString().padLeft(3, '0');

/// Data sources: pages and ayah positions from this project's GitHub repository, audio from EveryAyah,
/// text from alquran.cloud, quran.com and quranenc.com.
class Remote {
  static const repository = 'Mkuz1/Quran-Reader-HD';
  static const _raw = 'https://raw.githubusercontent.com/$repository/main';

  static Uri pageImage(int page) => Uri.parse('$_raw/pages/page${pad3(page)}.png');
  static final ayahInfoDB = Uri.parse('$_raw/data/ayahinfo_1024.db');
  static final pagesArchive =
      Uri.parse('https://github.com/$repository/releases/download/pages-v1/QuranReaderHD-Pages.zip');
  static const pagesArchiveMB = 57;
  static final meta = Uri.parse('https://api.alquran.cloud/v1/meta');
  static Uri edition(String id) => Uri.parse('https://api.alquran.cloud/v1/quran/$id');
  static Uri pageWords(int page) => Uri.parse(
      'https://api.quran.com/api/v4/verses/by_page/$page?words=true&word_fields=text_uthmani&per_page=50');
  static Uri audio(String reciter, AyahKey key) =>
      Uri.parse('https://everyayah.com/data/$reciter/${pad3(key.sura)}${pad3(key.ayah)}.mp3');
  static final releases = Uri.parse('https://api.github.com/repos/$repository/releases?per_page=20');
  static final releasesPage = Uri.parse('https://github.com/$repository/releases/latest');
}

class DownloadException implements Exception {
  final int status;
  final Uri url;
  DownloadException(this.status, this.url);

  @override
  String toString() => 'Download failed ($status): ${p.basename(url.path)}';
}

class Downloader {
  static final client = http.Client();

  /// Returns [dest], downloading [url] to it first if it isn't cached yet.
  static Future<File> fetch(Uri url, File dest) async {
    if (dest.existsSync()) return dest;
    final bytes = await get(url);
    dest.parent.createSync(recursive: true);
    final tmp = File('${dest.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(dest.path);
    return dest;
  }

  /// Body of a 200 response. Transport errors (not HTTP statuses) are retried, since the first request
  /// after launch can fail.
  static Future<List<int>> get(Uri url, {int attempts = 3}) async {
    for (var attempt = 1;; attempt++) {
      try {
        final r = await client.get(url).timeout(const Duration(seconds: 60));
        if (r.statusCode != 200) throw DownloadException(r.statusCode, url);
        return r.bodyBytes;
      } on DownloadException {
        rethrow;
      } catch (_) {
        if (attempt >= attempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }
}
