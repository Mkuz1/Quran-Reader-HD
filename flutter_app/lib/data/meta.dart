import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/quran.dart';
import '../core/storage.dart';

class Surah {
  final int number;
  final String name;
  final String englishName;
  final String englishNameTranslation;
  final int numberOfAyahs;
  final String revelationType;

  Surah.fromJson(Map<String, dynamic> j)
      : number = j['number'] as int,
        name = j['name'] as String,
        englishName = j['englishName'] as String,
        englishNameTranslation = j['englishNameTranslation'] as String,
        numberOfAyahs = j['numberOfAyahs'] as int,
        revelationType = j['revelationType'] as String;
}

/// Surah names and juz boundaries from alquran.cloud's /meta endpoint.
class QuranMeta {
  final List<Surah> surahs;
  final List<AyahKey> juzStarts;

  /// 240 rub' al-hizb starts; quarter i (0-based) is hizb i ~/ 4 + 1, quarter i % 4.
  final List<AyahKey> quarterStarts;

  QuranMeta(this.surahs, this.juzStarts, this.quarterStarts);

  static Future<QuranMeta> load() async {
    final file = await Downloader.fetch(Remote.meta, File(p.join(Paths.data.path, 'meta.json')));
    final data = (jsonDecode(await file.readAsString()) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
    List<Map<String, dynamic>> refs(String k) =>
        ((data[k] as Map<String, dynamic>)['references'] as List).cast<Map<String, dynamic>>();
    AyahKey key(Map<String, dynamic> r) => AyahKey(r['surah'] as int, r['ayah'] as int);
    return QuranMeta(
      refs('surahs').map(Surah.fromJson).toList(),
      refs('juzs').map(key).toList(),
      refs('hizbQuarters').map(key).toList(),
    );
  }
}
