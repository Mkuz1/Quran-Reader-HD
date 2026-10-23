import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/arabic.dart';
import '../core/quran.dart';
import '../core/storage.dart';

/// Identifies one word glyph on a page: ayah plus its glyph position in ayahinfo.
class WordRef {
  final AyahKey key;
  final int position;
  const WordRef(this.key, this.position);

  @override
  bool operator ==(Object other) => other is WordRef && other.key == key && other.position == position;

  @override
  int get hashCode => key.hashCode * 31 + position;
}

/// Word layout per page, used to colour the name of Allah on the monochrome page images.
class PageWords extends ChangeNotifier {
  final Map<int, Set<WordRef>> allahWords = {};
  final Set<int> _inFlight = {};
  final Map<int, DateTime> _failedAt = {};

  /// Glyphs a quran.com token occupies on the page image: a saktah sign (ۜ) glued to its word is its own glyph.
  static int _glyphCount(String token) {
    final hasLetters = token.runes.any((u) => (u >= 0x0621 && u <= 0x064A) || u == 0x0671);
    return hasLetters && token.runes.contains(0x06DC) ? 2 : 1;
  }

  /// quran.com words can hold several printed glyphs, so the mapping walks space-separated tokens. Ayahs whose
  /// total disagrees with the page's glyph count stay uncoloured.
  Future<void> ensure(int page, Map<AyahKey, int> glyphCounts) async {
    if (allahWords.containsKey(page) || _inFlight.contains(page)) return;
    // Pages are rebuilt often (hover, highlights); after a failure wait before asking the network again.
    final failed = _failedAt[page];
    if (failed != null && DateTime.now().difference(failed).inSeconds < 60) return;
    _inFlight.add(page);
    final dest = File(p.join(Paths.words.path, 'page${pad3(page)}.json'));
    try {
      final file = await Downloader.fetch(Remote.pageWords(page), dest);
      final env = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final refs = <WordRef>{};
      for (final v in env['verses'] as List) {
        final key = AyahKey.parse((v as Map)['verse_key'] as String);
        if (key == null) continue;
        var glyph = 1;
        final found = <WordRef>[];
        for (final w in v['words'] as List) {
          if ((w as Map)['char_type_name'] != 'word') continue;
          for (final token in ((w['text_uthmani'] as String?) ?? '').split(' ')) {
            if (token.isEmpty) continue;
            if (Arabic.isNameOfAllah(token)) found.add(WordRef(key, glyph));
            glyph += _glyphCount(token);
          }
        }
        // `glyph` is now one past the last word: the ayah-end marker's position.
        if (glyphCounts[key] == glyph) refs.addAll(found);
      }
      allahWords[page] = refs;
      notifyListeners();
    } catch (_) {
      _failedAt[page] = DateTime.now();
      if (dest.existsSync()) dest.deleteSync();
    } finally {
      _inFlight.remove(page);
    }
  }
}
