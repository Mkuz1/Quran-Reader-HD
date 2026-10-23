import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/quran.dart';
import '../core/storage.dart';

/// ISO 8601 without fractional seconds, the format the macOS app reads and writes.
String isoDate(DateTime d) => '${d.toUtc().toIso8601String().split('.').first}Z';

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class Bookmark {
  final String id;
  final int page;
  final DateTime created;
  String? title;

  Bookmark(this.page, {this.title, String? id, DateTime? created})
      : id = id ?? _uuid(),
        created = created ?? DateTime.now();

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(j['page'] as int,
      title: j['title'] as String?, id: j['id'] as String?, created: DateTime.tryParse('${j['created']}'));

  Map<String, dynamic> toJson() =>
      {'id': id, 'page': page, 'created': isoDate(created), if (title != null) 'title': title};
}

class Note {
  final String text;
  final DateTime updated;
  Note(this.text, [DateTime? updated]) : updated = updated ?? DateTime.now();

  factory Note.fromJson(Map<String, dynamic> j) =>
      Note(j['text'] as String, DateTime.tryParse('${j['updated']}'));

  Map<String, dynamic> toJson() => {'text': text, 'updated': isoDate(updated)};
}

/// Notes, bookmarks and last-read page. Notes and bookmarks live in library.json, in the same format as
/// the macOS app, so exports move between platforms.
class UserLibrary extends ChangeNotifier {
  final SharedPreferences _prefs;
  final List<Bookmark> bookmarks = [];
  final Map<AyahKey, Note> notes = {};
  int _lastPage;

  UserLibrary(this._prefs) : _lastPage = (_prefs.getInt('lastPage') ?? 1).clamp(1, Quran.pageCount) {
    try {
      if (Paths.library.existsSync()) apply(Paths.library.readAsStringSync(), merge: false);
    } catch (_) {}
  }

  int get lastPage => _lastPage;
  set lastPage(int p) {
    _lastPage = p;
    _prefs.setInt('lastPage', p);
  }

  bool isBookmarked(int page) => bookmarks.any((b) => b.page == page);

  void toggleBookmark(int page, {String? title}) {
    if (isBookmarked(page)) {
      bookmarks.removeWhere((b) => b.page == page);
    } else {
      bookmarks.add(Bookmark(page, title: title));
    }
    _save();
  }

  void rename(Bookmark b, String title) {
    b.title = title.isEmpty ? null : title;
    _save();
  }

  void removeBookmark(Bookmark b) {
    bookmarks.removeWhere((x) => x.id == b.id);
    _save();
  }

  void setNote(String text, AyahKey key) {
    if (text.trim().isEmpty) {
      notes.remove(key);
    } else if (notes[key]?.text != text) {
      notes[key] = Note(text);
    }
    _save();
  }

  bool get isEmpty => bookmarks.isEmpty && notes.isEmpty;

  String exportJson() {
    final sortedNotes = notes.keys.toList()..sort();
    final sortedBookmarks = [...bookmarks]..sort((a, b) => a.page.compareTo(b.page));
    return const JsonEncoder.withIndent('  ').convert({
      'bookmarks': [for (final b in sortedBookmarks) b.toJson()],
      'notes': {for (final k in sortedNotes) '$k': notes[k]!.toJson()},
    });
  }

  /// Adds the snapshot's bookmarks and notes; with [merge], a newer local note wins over an imported one.
  void apply(String json, {required bool merge}) {
    final snap = jsonDecode(json) as Map<String, dynamic>;
    if (!merge) {
      bookmarks.clear();
      notes.clear();
    }
    for (final b in (snap['bookmarks'] as List? ?? const [])) {
      final bm = Bookmark.fromJson((b as Map).cast<String, dynamic>());
      if (!isBookmarked(bm.page)) bookmarks.add(bm);
    }
    ((snap['notes'] as Map?) ?? const {}).forEach((k, v) {
      final key = AyahKey.parse('$k');
      if (key == null) return;
      final n = Note.fromJson((v as Map).cast<String, dynamic>());
      final existing = notes[key];
      if (existing != null && existing.updated.isAfter(n.updated)) return;
      notes[key] = n;
    });
    if (merge) _save();
    notifyListeners();
  }

  void _save() {
    try {
      Paths.library.writeAsStringSync(exportJson(), flush: true);
    } catch (_) {}
    notifyListeners();
  }

  /// The same content as plain text, for an email body.
  String plainText(String Function(int) surahTitle, String? Function(AyahKey) arabic, String Function(int) pageTitle) {
    final t = StringBuffer('Mushaf Notes & Bookmarks\n');
    if (notes.isNotEmpty) {
      t.write('\nNOTES\n');
      for (final key in notes.keys.toList()..sort()) {
        t.write('\n${surahTitle(key.sura)} : ${key.ayah}\n');
        final a = arabic(key);
        if (a != null) t.write('$a\n');
        t.write('${notes[key]!.text}\n');
      }
    }
    if (bookmarks.isNotEmpty) {
      t.write('\nBOOKMARKS\n');
      for (final b in [...bookmarks]..sort((a, b) => a.page.compareTo(b.page))) {
        t.write('• ${b.title ?? pageTitle(b.page)}\n');
      }
    }
    return t.toString();
  }

  /// A readable HTML page of all notes (with the ayah text) and bookmarks.
  String html(String Function(int) surahTitle, String? Function(AyahKey) arabic, String Function(int) pageTitle) {
    String esc(String s) =>
        s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('\n', '<br>');
    String date(DateTime d) => d.toLocal().toString().split('.').first;
    final h = StringBuffer('''<!doctype html><html><head><meta charset="utf-8"><title>Mushaf Notes & Bookmarks</title>
<style>body{font:15px system-ui,sans-serif;max-width:760px;margin:2em auto;padding:0 1em;color:#222}
h1{font-size:22px}h2{font-size:17px;border-bottom:1px solid #ddd;padding-bottom:4px;margin-top:2em}
.ar{font:22px 'Amiri Quran','Amiri','Traditional Arabic',serif;direction:rtl;text-align:right;line-height:1.9}
.meta{color:#888;font-size:12px}.note{margin:1.2em 0}</style></head><body>
<h1>Mushaf Notes &amp; Bookmarks</h1>''');
    if (notes.isNotEmpty) {
      h.write('<h2>Notes</h2>');
      for (final key in notes.keys.toList()..sort()) {
        final n = notes[key]!;
        h.write("<div class='note'><b>${esc(surahTitle(key.sura))} : ${key.ayah}</b> "
            "<span class='meta'>${date(n.updated)}</span>");
        final a = arabic(key);
        if (a != null) h.write("<p class='ar'>${esc(a)}</p>");
        h.write('<p>${esc(n.text)}</p></div>');
      }
    }
    if (bookmarks.isNotEmpty) {
      h.write('<h2>Bookmarks</h2><ul>');
      for (final b in [...bookmarks]..sort((a, b) => a.page.compareTo(b.page))) {
        h.write("<li>${esc(b.title ?? pageTitle(b.page))} <span class='meta'>${date(b.created)}</span></li>");
      }
      h.write('</ul>');
    }
    h.write('</body></html>');
    return h.toString();
  }
}
