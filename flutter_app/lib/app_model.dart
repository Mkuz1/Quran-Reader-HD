import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio/audio_controller.dart';
import 'core/l10n.dart';
import 'core/quran.dart';
import 'core/storage.dart';
import 'data/glyph_db.dart';
import 'data/meta.dart';
import 'data/page_store.dart';
import 'data/page_words.dart';
import 'data/text_library.dart';
import 'data/user_library.dart';
import 'update/update_checker.dart';

enum ReadingMode { mushaf('Mushaf'), text('Translation & Tafsir');
  const ReadingMode(this.label); final String label; }

enum PageTheme { classic('Classic'), coloured('Coloured'), night('Night');
  const PageTheme(this.label); final String label; }

enum StudyDisplay { arabic('Arabic'), translation('Translation'), both('Both');
  const StudyDisplay(this.label); final String label; }

enum InspectorTab { translation('Translation'), tafsir('Tafsir'), note('Note');
  const InspectorTab(this.label); final String label; }

enum LoadStatus { loading, ready, failed }

late AppModel model;

class AppModel extends ChangeNotifier {
  final SharedPreferences prefs;
  AppModel(this.prefs)
      : library = UserLibrary(prefs),
        audio = AudioController(prefs),
        updates = UpdateChecker(prefs) {
    _page = library.lastPage;
    final d = Edition.defaults(Localizer.shared.language);
    translationID = prefs.getString('translation') ?? d.$1;
    tafsirID = prefs.getString('tafsir') ?? d.$2;
    dualPage = prefs.getBool('dualPage') ?? true;
    theme = PageTheme.values.asNameMap()[prefs.getString('theme')] ?? PageTheme.coloured;
    brightness = prefs.getDouble('brightness') ?? 1;
    swipeEnabled = prefs.getBool('swipe') ?? true;
    studyDisplay = StudyDisplay.values.asNameMap()[prefs.getString('study')] ?? StudyDisplay.both;
    // Recitation turns the pages: follow the ayah being recited.
    audio.addListener(() {
      final c = audio.current;
      if (c != null && c != _followed) goToAyah(c, select: false);
      _followed = c;
    });
  }

  AyahKey? _followed;

  LoadStatus status = LoadStatus.loading;
  String statusMessage = 'Preparing…';
  GlyphDB? db;
  QuranMeta? meta;

  final text = TextLibrary();
  final UserLibrary library;
  final AudioController audio;
  final pageStore = PageStore();
  final words = PageWords();
  final UpdateChecker updates;

  int _page = 1;
  int get page => _page;

  /// Direction of the last page turn.
  bool turningForward = true;

  ReadingMode mode = ReadingMode.mushaf;
  AyahKey? selected;
  bool showInspector = false;
  InspectorTab inspectorTab = InspectorTab.translation;
  bool showDedication = true;

  late String translationID;
  late String tafsirID;
  late bool dualPage;
  late PageTheme theme;
  late double brightness;
  late bool swipeEnabled;
  late StudyDisplay studyDisplay;

  /// Whether the reader is showing two-page spreads right now: the setting, if the window or unfolded
  /// screen is wide enough. Set by the reader as it lays out.
  bool effectiveDual = true;

  void update(void Function() change) {
    change();
    prefs
      ..setString('translation', translationID)
      ..setString('tafsir', tafsirID)
      ..setBool('dualPage', dualPage)
      ..setString('theme', theme.name)
      ..setDouble('brightness', brightness)
      ..setBool('swipe', swipeEnabled)
      ..setString('study', studyDisplay.name);
    notifyListeners();
  }

  /// Switches the UI language and moves translation/tafsir to that language's defaults.
  void setLanguage(AppLanguage language) {
    if (language == Localizer.shared.language) return;
    Localizer.shared.value = language;
    final d = Edition.defaults(language);
    update(() {
      translationID = d.$1;
      tafsirID = d.$2;
    });
    text.ensure(translationID);
  }

  Future<void> bootstrap() async {
    status = LoadStatus.loading;
    statusMessage = 'Preparing…';
    notifyListeners();
    try {
      final dbFile = File(p.join(Paths.data.path, 'ayahinfo_1024.db'));
      if (!dbFile.existsSync()) {
        statusMessage = 'Downloading ayah coordinates…';
        notifyListeners();
        await Downloader.fetch(Remote.ayahInfoDB, dbFile);
      }
      db = GlyphDB(dbFile.path);
      audio.db = db;
      status = LoadStatus.ready;
    } catch (e) {
      statusMessage = e.toString();
      status = LoadStatus.failed;
      notifyListeners();
      return;
    }
    notifyListeners();
    try {
      meta = await QuranMeta.load();
    } catch (_) {}
    notifyListeners();
    await text.ensure(Edition.arabic.id);
    await text.ensure(translationID);
    await text.ensure(Edition.arabicSearch.id);
  }

  // MARK: Navigation

  /// Madani mushaf spreads: odd pages on the right, the following even page on the left.
  (int, int?) spreadOf(int page) {
    final right = page.isOdd ? page : page - 1;
    return (right, right + 1 <= Quran.pageCount ? right + 1 : null);
  }

  /// [right, left] for a spread, or the single page.
  List<int> visiblePages({bool? dual}) {
    if (!(dual ?? effectiveDual)) return [_page];
    final (r, l) = spreadOf(_page);
    return [r, ?l];
  }

  void goTo(int newPage) {
    final target = newPage.clamp(1, Quran.pageCount);
    if (target == _page) return;
    turningForward = target > _page;
    _page = target;
    library.lastPage = target;
    notifyListeners();
  }

  void goToAyah(AyahKey key, {bool select = true, bool? dual}) {
    if (select) selected = key;
    final pg = db?.page(key);
    if (pg != null && !visiblePages(dual: dual).contains(pg)) {
      goTo(pg);
    } else {
      notifyListeners();
    }
  }

  void select(AyahKey? key) {
    selected = key;
    notifyListeners();
  }

  void turn({required bool forward, bool? dual}) {
    final d = dual ?? effectiveDual;
    final step = d ? 2 : 1;
    final base = d ? spreadOf(_page).$1 : _page;
    goTo(base + (forward ? step : -step));
  }

  // MARK: Lookups

  Surah? surah(int n) => meta?.surahs.where((s) => s.number == n).firstOrNull;

  /// Surah name in the UI language: the Arabic name in Arabic, the transliteration otherwise.
  String surahName(int n) {
    final s = surah(n);
    if (s == null) return '$n';
    return Localizer.shared.language == AppLanguage.arabic ? s.name : s.englishName;
  }

  String surahTitle(int n) => '$n. ${surahName(n)}';

  int startPage(int sura) => db?.page(AyahKey(sura, 1)) ?? 1;

  List<int> get juzStartPages {
    final db = this.db, meta = this.meta;
    if (db == null || meta == null) return const [];
    return [for (final k in meta.juzStarts) ?db.page(k)];
  }

  int juzFor(int page) {
    final starts = juzStartPages;
    var i = 0;
    for (var j = 0; j < starts.length; j++) {
      if (starts[j] <= page) i = j;
    }
    return i + 1;
  }

  List<int> get quarterStartPages {
    final db = this.db, meta = this.meta;
    if (db == null || meta == null) return const [];
    return [for (final k in meta.quarterStarts) ?db.page(k)];
  }

  /// 0-based rub' al-hizb index the page falls in.
  int quarterIndex(int page) {
    final starts = quarterStartPages;
    var i = 0;
    for (var j = 0; j < starts.length; j++) {
      if (starts[j] <= page) i = j;
    }
    return i;
  }

  static String quarterLabel(int index) =>
      tr(const ['Hizb %d', '¼ Hizb %d', '½ Hizb %d', '¾ Hizb %d'][index % 4], [index ~/ 4 + 1]);

  /// Opening words of an ayah, like the original's index snippets.
  String snippet(AyahKey key, {int words = 5}) {
    final t = text.text(Edition.arabic.id, key);
    if (t == null) return '';
    final w = t.split(' ');
    return w.take(words).join(' ') + (w.length > words ? ' …' : '');
  }

  AyahKey? firstAyah(int page) {
    final a = db?.ayahs(page);
    return a == null || a.isEmpty ? null : a.first;
  }

  String pageTitle(int page) {
    final first = firstAyah(page);
    if (first == null) return tr('Page %d', [page]);
    return '${surahTitle(first.sura)} · ${tr('Page %d', [page])}';
  }

  // MARK: Actions

  void showText(InspectorTab tab, AyahKey key) {
    selected = key;
    inspectorTab = tab;
    showInspector = true;
    notifyListeners();
  }

  /// "Surah Al-Baqara : Verse 255 : Page 42", the original's citation format.
  String citation(AyahKey key) {
    final name = surah(key.sura)?.englishName ?? '${key.sura}';
    return 'Surah $name : Verse ${key.ayah} : Page ${db?.page(key) ?? 0}';
  }

  /// Arabic, the selected translation and the citation, for copying and sharing.
  String shareText(AyahKey key) {
    final parts = <String>[];
    final a = text.text(Edition.arabic.id, key);
    if (a != null) parts.add('$a ﴿${key.ayah}﴾');
    final t = text.text(translationID, key);
    if (t != null) parts.add(t);
    parts.add(citation(key));
    return parts.join('\n\n');
  }

  String arabicWithCitation(AyahKey key) => '${text.text(Edition.arabic.id, key) ?? ''} ﴿${key.ayah}﴾\n${citation(key)}';

  String notesHtml() => library.html(surahTitle, (k) => text.text(Edition.arabic.id, k), pageTitle);
  String notesPlain() => library.plainText(surahTitle, (k) => text.text(Edition.arabic.id, k), pageTitle);
}
