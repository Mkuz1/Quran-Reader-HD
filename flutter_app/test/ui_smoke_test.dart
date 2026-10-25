import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quran_reader_hd/app_model.dart';
import 'package:quran_reader_hd/core/l10n.dart';
import 'package:quran_reader_hd/core/quran.dart';
import 'package:quran_reader_hd/core/storage.dart';
import 'package:quran_reader_hd/data/meta.dart';
import 'package:quran_reader_hd/data/page_words.dart';
import 'package:quran_reader_hd/main.dart';
import 'package:quran_reader_hd/ui/dedication.dart';
import 'package:quran_reader_hd/ui/dock.dart';
import 'package:quran_reader_hd/ui/home.dart';
import 'package:quran_reader_hd/ui/page_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Screenshots go here when run with `--dart-define=OUT=<folder>`.
const out = String.fromEnvironment('OUT');
final _screen = GlobalKey();

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(rootBundle.load(f));
  }
  await loader.load();
}

/// Roboto and the icon font from the Flutter SDK, so screenshots show real text instead of test boxes.
Future<void> _sdkFonts({bool roboto = true}) async {
  final dir = Directory('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<void> load(String family, bool Function(String) match) async {
    final loader = FontLoader(family);
    for (final f in dir.listSync().whereType<File>().where((f) => match(p.basename(f.path)))) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  if (roboto) await load('Roboto', (n) => n.startsWith('Roboto-'));
  await load('MaterialIcons', (n) => n.startsWith('MaterialIcons'));
}

/// The home screen at phone, unfolded-foldable and desktop sizes, with the repository's own page images
/// and ayah database, offline.
void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('qr');
    Paths.useDirectory(dir);
    File('../data/ayahinfo_1024.db').copySync(p.join(Paths.data.path, 'ayahinfo_1024.db'));
    for (final n in ['page001.png', 'page002.png', 'page042.png', 'page043.png']) {
      File('../pages/$n').copySync(p.join(Paths.pages.path, n));
    }
  });

  /// Decodes the page images for real before taking screenshots.
  Future<void> decodePages(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final e in tester.elementList(find.byType(Image))) {
        final image = (e.widget as Image).image;
        await precacheImage(image, e);
      }
    });
    await tester.pump();
  }

  Future<void> pumpHome(WidgetTester tester, Size size,
      {List<ui.DisplayFeature> features = const [],
      String language = 'en',
      bool dark = false,
      bool meta = false,
      bool dedication = false,
      Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues({'pagesChoiceMade': true, 'lastPage': 1, ...saved});
    final prefs = await SharedPreferences.getInstance();
    Localizer.init(prefs, Locale(language));
    tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    model = AppModel(prefs)..showDedication = dedication;
    // Words to colour red, as downloaded from quran.com on a device: the name of Allah in 1:1.
    model.words.allahWords[1] = {const WordRef(AyahKey(1, 1), 2)};
    // Offline there is no surah list; a short one with real names where the layout depends on them.
    if (meta) {
      model.meta = QuranMeta([
        Surah.fromJson({
          'number': 1, 'name': 'سُورَةُ ٱلْفَاتِحَةِ', 'englishName': 'Al-Faatiha', 'englishNameTranslation': 'The Opening',
          'numberOfAyahs': 7, 'revelationType': 'Meccan',
        }),
        Surah.fromJson({
          'number': 2, 'name': 'سُورَةُ البَقَرَةِ', 'englishName': 'Al-Baqara', 'englishNameTranslation': 'The Cow',
          'numberOfAyahs': 286, 'revelationType': 'Medinan',
        }),
      ], const [], const []);
    }
    clearPageCache();
    await tester.runAsync(() async {
      await _font('Amiri Quran', ['assets/fonts/AmiriQuran-Regular.ttf']);
      await _font('Amiri', ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']);
      if (out.isNotEmpty) await _sdkFonts(roboto: language != 'ar');
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.displayFeatures = features;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(key: _screen, child: const QuranReaderApp()));
    // Let bootstrap open the database (and fail the network fetches quickly) and the pages decode.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await decodePages(tester);
    expect(model.status, LoadStatus.ready);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (out.isEmpty) return;
    await tester.runAsync(() async {
      final boundary = _screen.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> finish(WidgetTester tester) async {
    // The delayed update check runs (and fails offline) before the test ends.
    await tester.pump(const Duration(seconds: 4));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('phone', (tester) async {
    await pumpHome(tester, const Size(412, 892));
    expect(model.effectiveDual, isFalse);
    await shot(tester, 'phone');
    model.showText(InspectorTab.translation, const AyahKey(1, 5));
    await tester.pump();
    await shot(tester, 'phone-inspector');
    await finish(tester);
  });


  testWidgets('full screen: the page alone, controls over it on a tap', (tester) async {
    await pumpHome(tester, const Size(412, 892), saved: {'fullScreen': true});
    expect(find.byType(AppBar), findsNothing);
    expect(model.controlsVisible, isFalse);
    // The page fills the screen's width, and nothing is kept free for the player.
    final pageHeight = tester.getSize(find.byType(MushafPage).first).height;
    expect(tester.getSize(find.byType(MushafPage).first).width, greaterThan(412 - 12));
    // A single tap waits out the double-tap window (double-tap recites); then the controls slide in.
    await tester.tapAt(const Offset(206, 446));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(model.controlsVisible, isTrue);
    expect(tester.getSize(find.byType(MushafPage).first).height, pageHeight);
    await shot(tester, 'fullscreen-controls');
    // They hide again by themselves.
    await tester.pump(const Duration(seconds: 6));
    expect(model.controlsVisible, isFalse);
    await tester.tap(find.byType(MushafPage).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    expect(model.controlsVisible, isTrue);
    await tester.tap(find.byIcon(Icons.fullscreen_exit));
    await tester.pump();
    expect(model.fullScreen, isFalse);
    expect(find.byType(AppBar), findsOneWidget);
    await finish(tester);
  });

  testWidgets('continue reading where it stopped', (tester) async {
    await pumpHome(tester, const Size(412, 892),
        dedication: true, saved: {'lastPage': 2, 'lastAyah': '2:3', 'lastListening': true});
    expect(find.text('Continue Reading'), findsOneWidget);
    expect(find.text('Continue Listening'), findsOneWidget);
    expect(find.text('Start from the Beginning'), findsOneWidget);
    expect(find.textContaining('Page 2 · Ayah 3'), findsOneWidget);
    await shot(tester, 'continue');
    await tester.ensureVisible(find.text('Continue Reading'));
    await tester.tap(find.text('Continue Reading'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(model.showDedication, isFalse);
    expect(model.selected, const AyahKey(2, 3));
    expect(model.visiblePages(), contains(2));
    await finish(tester);
  });

  testWidgets('first launch just begins', (tester) async {
    await pumpHome(tester, const Size(412, 892), dedication: true);
    expect(find.text('Begin Reading'), findsOneWidget);
    expect(find.text('Continue Reading'), findsNothing);
    await finish(tester);
  });

  testWidgets('opening page on a small phone', (tester) async {
    await pumpHome(tester, const Size(320, 640));
    model.showDedication = true;
    model.update(() {});
    await tester.pump();
    expect(find.byType(DedicationView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('unfolded foldable with a hinge', (tester) async {
    await pumpHome(tester, const Size(1080, 960), features: const [
      ui.DisplayFeature(
          bounds: Rect.fromLTWH(530, 0, 20, 960), type: ui.DisplayFeatureType.hinge, state: ui.DisplayFeatureState.postureFlat),
    ]);
    expect(model.effectiveDual, isTrue);
    await shot(tester, 'foldable');
    model.showText(InspectorTab.tafsir, const AyahKey(1, 5));
    await tester.pump();
    await shot(tester, 'foldable-inspector');
    await finish(tester);
  });

  testWidgets('desktop window', (tester) async {
    await pumpHome(tester, const Size(1440, 900));
    expect(model.effectiveDual, isTrue);
    model.select(const AyahKey(2, 3));
    await tester.pump();
    await shot(tester, 'desktop');
    await finish(tester);
  });

  testWidgets('edge to edge in landscape: clear of a side navigation bar and a cutout', (tester) async {
    await pumpHome(tester, const Size(892, 412));
    // Android 15 draws the app behind the system bars: a camera cutout on the left, buttons on the right.
    const insets = FakeViewPadding(left: 40, top: 24, right: 48);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    await tester.pump();
    void expectClear(Finder f) {
      for (final e in f.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.left, greaterThanOrEqualTo(40), reason: '$f');
        expect(r.right, lessThanOrEqualTo(892 - 48), reason: '$f');
      }
    }

    expectClear(find.byType(MushafPage));
    expectClear(find.byType(Dock));
    await shot(tester, 'landscape-insets');
    model.setFullScreen(true);
    await tester.pump();
    await decodePages(tester);
    expectClear(find.byType(MushafPage));
    expect(tester.getRect(find.byType(MushafPage).first).top, greaterThanOrEqualTo(24));
    await shot(tester, 'landscape-insets-fullscreen');
    model.setFullScreen(false);
    await finish(tester);
  });

  testWidgets('phone in Arabic and dark mode, with the recitation options', (tester) async {
    // Interface text in Amiri (wider than Android's own Arabic font), so the fit below is a safe check. Fonts stay
    // loaded for later tests, so this test runs last.
    await tester.runAsync(() => _font('Roboto', ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']));
    await pumpHome(tester, const Size(343, 760), language: 'ar', dark: true, meta: true);
    // The surah's full Arabic name fits beside the bar's actions.
    final title = tester.renderObject<RenderParagraph>(find.text('سُورَةُ ٱلْفَاتِحَةِ'));
    expect(title.didExceedMaxLines, isFalse);
    await shot(tester, 'phone-ar');
    showAudioOptions(tester.element(find.byType(Home)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await shot(tester, 'phone-ar-recitation');
    await tester.tap(find.text(tr('Done')));
    await tester.pumpAndSettle();
    await finish(tester);
  });
}
