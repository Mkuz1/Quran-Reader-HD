import 'dart:ui';

import 'package:sqlite3/sqlite3.dart';

import '../core/quran.dart';

/// One word (or ayah-end marker) on a page image, in 1024px image coordinates.
class Glyph {
  final AyahKey key;
  final int position; // word index within the ayah, 1-based; the last one is the ayah-end marker
  final int line;
  final Rect rect;
  const Glyph(this.key, this.position, this.line, this.rect);
}

/// Read-only access to ayahinfo_1024.db: word bounding boxes for all 604 pages.
class GlyphDB {
  final Database _db;
  final Map<int, List<Glyph>> _pageCache = {};
  final Map<AyahKey, int> _pageOf = {};
  final Map<AyahKey, int> _glyphTotals = {};
  final List<int> ayahCounts = List.filled(115, 0);

  GlyphDB(String path) : _db = sqlite3.open(path, mode: OpenMode.readOnly) {
    for (final r in _db.select('SELECT sura_number, MAX(ayah_number) FROM glyphs GROUP BY sura_number')) {
      final sura = r.columnAt(0) as int;
      if (sura >= 1 && sura <= 114) ayahCounts[sura] = r.columnAt(1) as int;
    }
    // Every ayah's first page and glyph count in one pass, so later lookups never hit SQLite.
    for (final r in _db.select(
        'SELECT sura_number, ayah_number, MIN(page_number), COUNT(*) FROM glyphs GROUP BY sura_number, ayah_number')) {
      final key = AyahKey(r.columnAt(0) as int, r.columnAt(1) as int);
      _pageOf[key] = r.columnAt(2) as int;
      _glyphTotals[key] = r.columnAt(3) as int;
    }
  }

  void dispose() => _db.close();

  List<Glyph> glyphs(int page) => _pageCache.putIfAbsent(page, () {
        return _db.select('''
          SELECT sura_number, ayah_number, line_number, position, min_x, max_x, min_y, max_y
          FROM glyphs WHERE page_number = ? ORDER BY glyph_id''', [page]).map((r) {
          final x0 = (r.columnAt(4) as int).toDouble(), x1 = (r.columnAt(5) as int).toDouble();
          final y0 = (r.columnAt(6) as int).toDouble(), y1 = (r.columnAt(7) as int).toDouble();
          return Glyph(AyahKey(r.columnAt(0) as int, r.columnAt(1) as int), r.columnAt(3) as int,
              r.columnAt(2) as int, Rect.fromLTRB(x0, y0, x1, y1));
        }).toList();
      });

  /// Ayahs on a page, in reading order.
  List<AyahKey> ayahs(int page) {
    final seen = <AyahKey>{};
    return [for (final g in glyphs(page)) if (seen.add(g.key)) g.key];
  }

  /// Glyphs the ayah has across all pages (words, pause marks and its end marker).
  int glyphTotal(AyahKey key) => _glyphTotals[key] ?? 0;

  int? page(AyahKey key) => _pageOf[key];

  /// One rectangle per line the ayah covers on this page (words on a line merged).
  List<Rect> highlightRects(AyahKey key, int page) {
    final byLine = <int, Rect>{};
    for (final g in glyphs(page)) {
      if (g.key != key) continue;
      byLine[g.line] = byLine[g.line]?.expandToInclude(g.rect) ?? g.rect;
    }
    final lines = byLine.keys.toList()..sort();
    return [for (final l in lines) byLine[l]!];
  }

  AyahKey? ayahAt(Offset point, int page) {
    final all = glyphs(page);
    for (final g in all) {
      if (Rect.fromLTRB(g.rect.left - 4, g.rect.top - 10, g.rect.right + 4, g.rect.bottom + 10).contains(point)) {
        return g.key;
      }
    }
    // Gaps between words: take the nearest glyph on the line under the pointer.
    Glyph? best;
    for (final g in all) {
      if (point.dy < g.rect.top - 12 || point.dy > g.rect.bottom + 12) continue;
      if (best == null || (g.rect.center.dx - point.dx).abs() < (best.rect.center.dx - point.dx).abs()) best = g;
    }
    return best?.key;
  }

  AyahKey? next(AyahKey key) {
    if (key.ayah < ayahCounts[key.sura]) return AyahKey(key.sura, key.ayah + 1);
    return key.sura < 114 ? AyahKey(key.sura + 1, 1) : null;
  }

  AyahKey? previous(AyahKey key) {
    if (key.ayah > 1) return AyahKey(key.sura, key.ayah - 1);
    return key.sura > 1 ? AyahKey(key.sura - 1, ayahCounts[key.sura - 1]) : null;
  }
}
