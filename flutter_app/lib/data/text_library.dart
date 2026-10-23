import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/arabic.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../core/storage.dart';

enum EditionKind { arabic, translation, tafsir }

sealed class EditionSource {
  const EditionSource();
}

class AlquranCloud extends EditionSource {
  const AlquranCloud();
}

/// Whole Quran in one request.
class QuranComTranslation extends EditionSource {
  final int id;
  const QuranComTranslation(this.id);
}

/// Fetched per surah; grouped commentary leaves later ayahs of a group empty.
class QuranComTafsir extends EditionSource {
  final int id;
  const QuranComTafsir(this.id);
}

/// quranenc.com translation key, fetched per surah.
class QuranEnc extends EditionSource {
  final String key;
  const QuranEnc(this.key);
}

class Edition {
  final String id;
  final String title;
  final EditionKind kind;
  final String language;
  final EditionSource source;
  const Edition(this.id, this.title, this.kind, this.language, [this.source = const AlquranCloud()]);

  bool get isRTL => language == 'ar';
  bool get perSurah => source is QuranComTafsir || source is QuranEnc;

  static const arabic = Edition('quran-uthmani', 'Arabic (Uthmani)', EditionKind.arabic, 'ar');

  /// Plain spelling without diacritics, used only as the Arabic search index.
  static const arabicSearch = Edition('quran-simple-clean', 'Arabic (plain)', EditionKind.arabic, 'ar');

  static const all = <Edition>[
    arabic,
    Edition('en.sahih', 'English — Saheeh International', EditionKind.translation, 'en'),
    Edition('en.pickthall', 'English — Pickthall', EditionKind.translation, 'en'),
    Edition('fr.hamidullah', 'Français — Hamidullah', EditionKind.translation, 'fr'),
    Edition('qc-tr-136', 'Français — Montada Islamic Foundation', EditionKind.translation, 'fr',
        QuranComTranslation(136)),
    Edition('qc-tr-779', 'Français — Rashid Maash', EditionKind.translation, 'fr', QuranComTranslation(779)),
    Edition('ar.muyassar', 'التفسير الميسر — Al-Muyassar', EditionKind.tafsir, 'ar'),
    Edition('ar.jalalayn', 'تفسير الجلالين — Al-Jalalayn', EditionKind.tafsir, 'ar'),
    Edition('qe-french_mokhtasar', 'Français — Al-Mukhtasar (Exégèse abrégée)', EditionKind.tafsir, 'fr',
        QuranEnc('french_mokhtasar')),
    Edition('qc-tafsir-169', 'English — Ibn Kathir (abridged)', EditionKind.tafsir, 'en', QuranComTafsir(169)),
    Edition('qc-tafsir-168', "English — Ma'arif al-Qur'an", EditionKind.tafsir, 'en', QuranComTafsir(168)),
    Edition('qc-tafsir-817', 'English — Tazkirul Quran', EditionKind.tafsir, 'en', QuranComTafsir(817)),
  ];

  static List<Edition> get translations => all.where((e) => e.kind == EditionKind.translation).toList();
  static List<Edition> get tafsirs => all.where((e) => e.kind == EditionKind.tafsir).toList();
  static Edition named(String id) =>
      [...all, arabicSearch].firstWhere((e) => e.id == id, orElse: () => arabic);

  /// Defaults when the UI language changes.
  static (String, String) defaults(AppLanguage language) => switch (language) {
        AppLanguage.english => ('en.sahih', 'qc-tafsir-169'),
        AppLanguage.french => ('fr.hamidullah', 'qe-french_mokhtasar'),
        AppLanguage.arabic => ('en.sahih', 'ar.muyassar'),
      };
}

/// quran.com text is HTML: footnote markers are dropped, block tags become paragraph breaks.
String plainFromHtml(String html) {
  var s = html.replaceAll(RegExp(r'<sup[^>]*>.*?</sup>', dotAll: true), '');
  s = s.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  s = s.replaceAll(RegExp(r'</(p|h[1-6]|li|div)>'), '\n\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {'&nbsp;': ' ', '&quot;': '"', '&#39;': "'", '&apos;': "'", '&lt;': '<', '&gt;': '>', '&amp;': '&'};
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

class SearchHit {
  final AyahKey key;
  final String edition;
  const SearchHit(this.key, this.edition);
}

/// Text editions, downloaded once and cached as JSON.
class TextLibrary extends ChangeNotifier {
  final Map<String, List<List<String>>> texts = {}; // edition -> [sura-1][ayah-1]
  final Set<String> loading = {};
  final Map<String, String> errors = {};

  /// Per-surah texts for editions fetched one surah at a time: edition -> sura -> ayahs.
  final Map<String, Map<int, List<String>>> chapters = {};

  /// Arabic.normalize applied to every ayah of the plain edition, built once it loads.
  List<List<String>> _normalizedArabic = [];

  String? text(String edition, AyahKey key) {
    final source = Edition.named(edition).source;
    if (source is QuranEnc) {
      final ayahs = chapters[edition]?[key.sura];
      if (ayahs == null || key.ayah - 1 >= ayahs.length) return null;
      final t = ayahs[key.ayah - 1];
      return t.isEmpty ? null : t;
    }
    if (source is QuranComTafsir) {
      final ayahs = chapters[edition]?[key.sura];
      if (ayahs == null || ayahs.isEmpty) return null;
      if (key.ayah - 1 < ayahs.length && ayahs[key.ayah - 1].isNotEmpty) return ayahs[key.ayah - 1];
      // Grouped commentary: an empty (or trailing, omitted) entry belongs to the nearest earlier ayah with text.
      final last = (key.ayah - 1).clamp(0, ayahs.length);
      for (var first = last; first >= 1; first--) {
        if (ayahs[first - 1].isEmpty) continue;
        final note = tr('Commentary for ayahs %@ is under %@.', ['${key.sura}:$first–${key.ayah}', '${key.sura}:$first']);
        return '$note\n\n${ayahs[first - 1]}';
      }
      return null;
    }
    final t = texts[edition];
    if (t == null || key.sura - 1 >= t.length || key.ayah - 1 >= t[key.sura - 1].length) return null;
    final text = t[key.sura - 1][key.ayah - 1];
    // The Arabic editions prefix each surah's first ayah with the four-word basmala; it isn't part of the ayah.
    if ((edition == Edition.arabic.id || edition == Edition.arabicSearch.id) && key.ayah == 1 && key.sura != 1) {
      final words = text.split(' ');
      if (words.length > 4 && Arabic.normalize(words.first) == 'بسم') return words.skip(4).join(' ');
    }
    return text;
  }

  bool isLoaded(String edition) => texts.containsKey(edition);

  /// Ayahs whose Arabic (diacritic-insensitive) or translation text contains [query], Arabic matches first.
  (List<SearchHit>, bool) search(String query, String translation, int limit) {
    final q = query.trim();
    if (q.length < 2) return (const [], false);
    final hits = <SearchHit>[];
    final arabicQuery = Arabic.normalize(q);
    if (arabicQuery.isNotEmpty && Arabic.containsArabic(q)) {
      outer:
      for (var si = 0; si < _normalizedArabic.length; si++) {
        for (var ai = 0; ai < _normalizedArabic[si].length; ai++) {
          if (!_normalizedArabic[si][ai].contains(arabicQuery)) continue;
          hits.add(SearchHit(AyahKey(si + 1, ai + 1), Edition.arabicSearch.id));
          if (hits.length > limit) break outer;
        }
      }
    } else {
      final t = texts[translation];
      final needle = _fold(q);
      if (t != null) {
        outer:
        for (var si = 0; si < t.length; si++) {
          for (var ai = 0; ai < t[si].length; ai++) {
            final key = AyahKey(si + 1, ai + 1);
            final s = text(translation, key);
            if (s == null || !_fold(s).contains(needle)) continue;
            hits.add(SearchHit(key, translation));
            if (hits.length > limit) break outer;
          }
        }
      }
    }
    return (hits.take(limit).toList(), hits.length > limit);
  }

  /// Case- and accent-insensitive form for translation search.
  static String _fold(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  /// Distinct Arabic words starting with the typed prefix, for search suggestions.
  List<String> suggestions(String prefix, {int max = 8}) {
    final pfx = Arabic.normalize(prefix);
    if (pfx.length < 2 || pfx.contains(' ')) return const [];
    final counts = <String, int>{};
    for (final ayahs in _normalizedArabic) {
      for (final a in ayahs) {
        for (final w in a.split(' ')) {
          if (w.startsWith(pfx)) counts[w] = (counts[w] ?? 0) + 1;
        }
      }
    }
    final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(max).map((e) => e.key).toList();
  }

  Future<void> ensure(String edition, {int? sura}) async {
    final source = Edition.named(edition).source;
    switch (source) {
      case AlquranCloud():
        await _ensureAlquran(edition);
      case QuranComTranslation(:final id):
        await _ensureQuranComTranslation(edition, id);
      case QuranComTafsir(:final id):
        if (sura != null) await _ensureQuranComTafsir(edition, id, sura);
      case QuranEnc(:final key):
        if (sura != null) await _ensureQuranEnc(edition, key, sura);
    }
  }

  Future<void> _ensureAlquran(String edition) async {
    if (texts.containsKey(edition) || loading.contains(edition)) return;
    loading.add(edition);
    final dest = File(p.join(Paths.text.path, '$edition.json'));
    try {
      final file = await Downloader.fetch(Remote.edition(edition), dest);
      final path = file.path;
      final parsed = await Isolate.run(() {
        final env = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        final surahs = (env['data'] as Map<String, dynamic>)['surahs'] as List;
        return [
          for (final s in surahs)
            [for (final a in (s as Map)['ayahs'] as List) ((a as Map)['text'] as String).replaceAll('﻿', '')]
        ];
      });
      texts[edition] = parsed;
      if (edition == Edition.arabicSearch.id) {
        _normalizedArabic = await Isolate.run(() {
          const basmala = 'بسم الله الرحمن الرحيم ';
          return [
            for (var si = 0; si < parsed.length; si++)
              [
                for (var ai = 0; ai < parsed[si].length; ai++)
                  // Drop the basmala prefix on first ayahs so it doesn't match every surah.
                  Arabic.normalize(ai == 0 && si > 0 && parsed[si][ai].startsWith(basmala)
                      ? parsed[si][ai].substring(basmala.length)
                      : parsed[si][ai])
              ]
          ];
        });
      }
      errors.remove(edition);
    } catch (e) {
      errors[edition] = e.toString();
      if (dest.existsSync()) dest.deleteSync();
    } finally {
      loading.remove(edition);
      notifyListeners();
    }
  }

  Future<void> _ensureQuranComTranslation(String edition, int id) async {
    if (texts.containsKey(edition) || loading.contains(edition)) return;
    loading.add(edition);
    final dest = File(p.join(Paths.text.path, '$edition.json'));
    try {
      final url = Uri.parse('https://api.quran.com/api/v4/quran/translations/$id?fields=verse_key');
      final path = (await Downloader.fetch(url, dest)).path;
      texts[edition] = await Isolate.run(() {
        final out = List.generate(114, (_) => <String>[]);
        final list = (jsonDecode(File(path).readAsStringSync()) as Map)['translations'] as List;
        for (final t in list) {
          final key = AyahKey.parse((t as Map)['verse_key'] as String);
          if (key == null || key.sura < 1 || key.sura > 114) continue;
          out[key.sura - 1].add(plainFromHtml(t['text'] as String));
        }
        return out;
      });
      errors.remove(edition);
    } catch (e) {
      errors[edition] = e.toString();
      if (dest.existsSync()) dest.deleteSync();
    } finally {
      loading.remove(edition);
      notifyListeners();
    }
  }

  /// Shared by the per-surah sources: cache in `text/<edition>-<sura>.json` as a plain list of ayahs.
  Future<void> _ensurePerSurah(String edition, int sura, Future<Map<int, String>> Function() fetch) async {
    final tag = '$edition/$sura';
    if (chapters[edition]?[sura] != null || loading.contains(tag)) return;
    loading.add(tag);
    final dest = File(p.join(Paths.text.path, '$edition-$sura.json'));
    try {
      if (!dest.existsSync()) {
        final byAyah = await fetch();
        final count = byAyah.keys.fold(0, (a, b) => a > b ? a : b);
        final ayahs = [for (var i = 1; i <= count; i++) byAyah[i] ?? ''];
        await dest.writeAsString(jsonEncode(ayahs), flush: true);
      }
      final ayahs = (jsonDecode(await dest.readAsString()) as List).cast<String>();
      (chapters[edition] ??= {})[sura] = ayahs;
      errors.remove(edition);
    } catch (e) {
      errors[edition] = e.toString();
    } finally {
      loading.remove(tag);
      notifyListeners();
    }
  }

  Future<void> _ensureQuranComTafsir(String edition, int id, int sura) => _ensurePerSurah(edition, sura, () async {
        final byAyah = <int, String>{};
        int? page = 1;
        while (page != null) {
          final url = Uri.parse('https://api.quran.com/api/v4/tafsirs/$id/by_chapter/$sura?per_page=50&page=$page');
          final body = jsonDecode(utf8.decode(await Downloader.get(url))) as Map<String, dynamic>;
          for (final t in body['tafsirs'] as List) {
            final k = AyahKey.parse((t as Map)['verse_key'] as String);
            if (k != null) byAyah[k.ayah] = plainFromHtml(t['text'] as String);
          }
          page = (body['pagination'] as Map?)?['next_page'] as int?;
        }
        return byAyah;
      });

  /// quranenc.com returns numbers as strings; accept either.
  Future<void> _ensureQuranEnc(String edition, String key, int sura) => _ensurePerSurah(edition, sura, () async {
        final url = Uri.parse('https://quranenc.com/api/v1/translation/sura/$key/$sura');
        final body = jsonDecode(utf8.decode(await Downloader.get(url))) as Map<String, dynamic>;
        return {
          for (final a in body['result'] as List)
            int.parse('${(a as Map)['aya']}'): plainFromHtml(a['translation'] as String)
        };
      });
}
