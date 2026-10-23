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
import 'package:quran_reader_hd/main.dart';
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
Future<void> _sdkFonts() async {
  final dir = Directory('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<void> load(String family, bool Function(String) match) async {
    final loader = FontLoader(family);
    for (final f in dir.listSync().whereType<File>().where((f) => match(p.basename(f.path)))) {
      loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', (n) => n.startsWith('Roboto-'));
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

  Future<void> pumpHome(WidgetTester tester, Size size, {List<ui.DisplayFeature> features = const []}) async {
    SharedPreferences.setMockInitialValues({'pagesChoiceMade': true, 'lastPage': 1});
    final prefs = await SharedPreferences.getInstance();
    Localizer.init(prefs, const Locale('en'));
    model = AppModel(prefs)..showDedication = false;
    clearPageCache();
    await tester.runAsync(() async {
      await _font('Amiri Quran', ['assets/fonts/AmiriQuran-Regular.ttf']);
      await _font('Amiri', ['assets/fonts/Amiri-Regular.ttf', 'assets/fonts/Amiri-Bold.ttf']);
      if (out.isNotEmpty) await _sdkFonts();
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
    // Decode the page images for real before taking screenshots.
    await tester.runAsync(() async {
      for (final e in tester.elementList(find.byType(Image))) {
        final image = (e.widget as Image).image;
        await precacheImage(image, e);
      }
    });
    await tester.pump();
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
}
