class Arabic {
  static final _latinLetter = RegExp(r'\p{L}', unicode: true);
  static final _spaces = RegExp(r'\s+');
  static final _allah = RegExp(r'^(و|ف)?(ب|ت|ل)?ا?لله(م)?$');

  /// Base letters only: drops harakat, Quranic marks and tatweel, and folds alef/ya/ta-marbuta variants,
  /// so typed queries match the printed text.
  static String normalize(String s) {
    final out = StringBuffer();
    for (final u in s.runes) {
      if (u == 0x0622 || u == 0x0623 || u == 0x0625 || u == 0x0671) {
        out.write('ا');
      } else if (u == 0x0649) {
        out.write('ي');
      } else if (u == 0x0629) {
        out.write('ه');
      } else if ((u >= 0x0621 && u <= 0x063A) || (u >= 0x0641 && u <= 0x064A) || u == 0x20) {
        out.writeCharCode(u);
      } else if (u < 0x0600) {
        final c = String.fromCharCode(u);
        if (_latinLetter.hasMatch(c)) out.write(c); // keep Latin for mixed input
      }
    }
    return out.toString().split(_spaces).where((w) => w.isNotEmpty).join(' ');
  }

  /// The name of Allah (lafz al-jalala), with attached prefixes و ف ب ت ل and the vocative اللهم.
  static bool isNameOfAllah(String word) => _allah.hasMatch(normalize(word));

  static bool containsArabic(String s) => s.runes.any((u) => u >= 0x0600 && u <= 0x06FF);
}
