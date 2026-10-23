import 'package:flutter_test/flutter_test.dart';
import 'package:quran_reader_hd/core/arabic.dart';
import 'package:quran_reader_hd/core/quran.dart';
import 'package:quran_reader_hd/data/glyph_db.dart';
import 'package:quran_reader_hd/data/text_library.dart';
import 'package:quran_reader_hd/update/update_checker.dart';

void main() {
  test('ayah coordinates database', () {
    final db = GlyphDB('../data/ayahinfo_1024.db');
    expect(db.ayahCounts[1], 7);
    expect(db.ayahCounts[2], 286);
    expect(db.ayahCounts[114], 6);
    expect(db.page(const AyahKey(2, 255)), 42);
    expect(db.page(const AyahKey(1, 1)), 1);
    expect(db.ayahs(1).first, const AyahKey(1, 1));
    expect(db.highlightRects(const AyahKey(2, 255), 42), isNotEmpty);
    final r = db.highlightRects(const AyahKey(2, 255), 42).first;
    expect(db.ayahAt(r.center, 42), const AyahKey(2, 255));
    expect(db.next(const AyahKey(1, 7)), const AyahKey(2, 1));
    expect(db.previous(const AyahKey(2, 1)), const AyahKey(1, 7));
    expect(db.ayahAt(const Offset(-500, -500), 42), isNull);
    db.dispose();
  });

  test('arabic normalisation', () {
    expect(Arabic.normalize('بِسْمِ ٱللَّهِ'), 'بسم الله');
    expect(Arabic.isNameOfAllah('وَٱللَّهُ'), isTrue);
    expect(Arabic.isNameOfAllah('ٱلرَّحْمَٰنِ'), isFalse);
  });

  test('html to plain text', () {
    expect(plainFromHtml('<p>One<sup foot_note="1">1</sup></p><p>Two &amp; three</p>'), 'One\n\nTwo & three');
  });

  test('version comparison and latest release', () {
    expect(compareVersions('1.10', '1.9'), 1);
    expect(compareVersions('v1.2', '1.2.0'), 0);
    final latest = latestRelease([
      {'tag_name': 'pages-v1', 'draft': false, 'prerelease': false, 'html_url': 'x', 'assets': <Map<String, String>>[]},
      {'tag_name': 'v1.1', 'draft': false, 'prerelease': false, 'html_url': 'https://a/1.1', 'assets': <Map<String, String>>[]},
      {
        'tag_name': 'v1.2', 'draft': false, 'prerelease': false, 'html_url': 'https://a/1.2', 'body': 'n',
        'assets': [
          {'name': 'QuranReaderHD-1.2.apk', 'browser_download_url': 'https://a/x.apk'},
          {'name': 'QuranReaderHD-1.2-Setup.exe', 'browser_download_url': 'https://a/x.exe'},
        ]
      },
      {'tag_name': 'v9.0', 'draft': true, 'prerelease': false, 'html_url': 'x', 'assets': <Map<String, String>>[]},
    ], assetSuffix: '-Setup.exe');
    expect(latest!.version, '1.2');
    expect(latest.download.toString(), 'https://a/x.exe');
  });
}
