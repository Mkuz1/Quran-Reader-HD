import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quran_reader_hd/app_model.dart';
import 'package:quran_reader_hd/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

/// Runs the real app on an Android device or emulator (see the release workflow): online pages, real
/// downloads, Arabic and the Coloured theme, then fails with the error if any part of a page didn't build.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a mushaf page builds and shows on a device', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('language', 'ar');
    await prefs.setString('theme', 'coloured');
    await prefs.setInt('lastPage', 17);
    await prefs.setBool('pagesChoiceMade', true);
    // main() installs the app's error display; the test framework checks its own is back when the test body
    // ends (before tear-downs run). Any build error is reported by the framework itself, with its stack.
    final errorBuilder = ErrorWidget.builder;
    try {
      await _run(tester);
    } finally {
      ErrorWidget.builder = errorBuilder;
    }
  });
}

Future<void> _run(WidgetTester tester) async {
  await app.main();
  await tester.pump(const Duration(seconds: 1));

  // The opening page, then the mushaf.
  await tester.tap(find.byType(FilledButton).last);
  await tester.pump(const Duration(seconds: 1));

  // Wait for the ayah database, the page image and the word colouring to download.
  for (var i = 0; i < 90; i++) {
    await tester.pump(const Duration(seconds: 1));
    final loaded =
        model.status == LoadStatus.ready &&
        tester.widgetList<RawImage>(find.byType(RawImage)).any((r) => r.image != null) &&
        model.words.allahWords.containsKey(17);
    if (loaded) break;
  }
  await tester.pump(const Duration(seconds: 2));
  debugPrint(
    'DEVICE CHECK status=${model.status} page=${model.page} '
    'images=${tester.widgetList<RawImage>(find.byType(RawImage)).where((r) => r.image != null).length} '
    'allahWords=${model.words.allahWords[17]?.length}',
  );
  expect(tester.widgetList<RawImage>(find.byType(RawImage)).any((r) => r.image != null), isTrue);
}
