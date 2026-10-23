import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_model.dart';
import 'core/l10n.dart';
import 'core/storage.dart';
import 'ui/common.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A part of the screen that fails to build shows what went wrong, not the release build's plain grey box,
  // so a screenshot is enough to report it.
  ErrorWidget.builder = (details) => Directionality(
        textDirection: TextDirection.ltr,
        child: ColoredBox(
          color: const Color(0xFFF6EBD0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('⚠ ${details.exceptionAsString()}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A1C1C), decoration: TextDecoration.none)),
            ),
          ),
        ),
      );
  final prefs = await SharedPreferences.getInstance();
  await Paths.init();
  Localizer.init(prefs, PlatformDispatcher.instance.locale);
  model = AppModel(prefs);
  runApp(const QuranReaderApp());
}

class QuranReaderApp extends StatelessWidget {
  const QuranReaderApp({super.key});

  ThemeData _theme(Brightness brightness) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: brightness),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Localizer.shared,
      builder: (context, _) => MaterialApp(
        title: 'Quran Reader HD',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        // Arabic lays the interface out right-to-left; the mushaf itself keeps book order.
        builder: (context, child) =>
            Directionality(textDirection: Localizer.shared.language.direction, child: child!),
        home: const Home(),
      ),
    );
  }
}
