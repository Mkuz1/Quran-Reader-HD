import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings_table.dart';

enum AppLanguage {
  english('en', 'English'),
  french('fr', 'Français'),
  arabic('ar', 'العربية');

  const AppLanguage(this.code, this.nativeName);
  final String code;

  /// Each language names itself, so the toggle is readable whatever is selected.
  final String nativeName;

  TextDirection get direction => this == arabic ? TextDirection.rtl : TextDirection.ltr;
}

/// App-wide UI language. Widgets that call [tr] rebuild when it changes.
class Localizer extends ValueNotifier<AppLanguage> {
  Localizer._(super.value);
  static late Localizer shared;

  static void init(SharedPreferences prefs, Locale systemLocale) {
    final saved = prefs.getString('language') ?? systemLocale.languageCode;
    shared = Localizer._(AppLanguage.values.firstWhere((l) => l.code == saved, orElse: () => AppLanguage.english));
    shared.addListener(() => prefs.setString('language', shared.value.code));
  }

  AppLanguage get language => value;
}

/// Translates an English UI string (unknown strings fall back to English) and fills in %@ / %d
/// placeholders in order.
String tr(String english, [List<Object?> args = const []]) {
  final entry = stringsTable[english];
  var s = switch (Localizer.shared.language) {
    AppLanguage.english => english,
    AppLanguage.french => entry?.$1 ?? english,
    AppLanguage.arabic => entry?.$2 ?? english,
  };
  if (args.isEmpty && !s.contains('%%')) return s;
  var i = 0;
  s = s.replaceAllMapped(RegExp(r'%[@d%]'), (m) {
    if (m[0] == '%%') return '%';
    return i < args.length ? '${args[i++]}' : m[0]!;
  });
  return s;
}
