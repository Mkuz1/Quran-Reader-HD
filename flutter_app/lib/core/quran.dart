/// Identifies one verse.
class AyahKey implements Comparable<AyahKey> {
  final int sura;
  final int ayah;

  const AyahKey(this.sura, this.ayah);

  static AyahKey? parse(String s) {
    final parts = s.split(':').map(int.tryParse).toList();
    if (parts.length != 2 || parts.contains(null)) return null;
    return AyahKey(parts[0]!, parts[1]!);
  }

  @override
  String toString() => '$sura:$ayah';

  @override
  bool operator ==(Object other) => other is AyahKey && other.sura == sura && other.ayah == ayah;

  @override
  int get hashCode => sura * 1000 + ayah;

  @override
  int compareTo(AyahKey other) => sura != other.sura ? sura - other.sura : ayah - other.ayah;

  bool operator <(AyahKey other) => compareTo(other) < 0;
  bool operator >(AyahKey other) => compareTo(other) > 0;
  bool operator <=(AyahKey other) => compareTo(other) <= 0;
  bool operator >=(AyahKey other) => compareTo(other) >= 0;
}

AyahKey maxKey(AyahKey a, AyahKey b) => a >= b ? a : b;

class Quran {
  static const pageCount = 604;
  static const pageWidth = 1024.0;
  static const pageHeight = 1656.0;
}

/// Western digits to Arabic-Indic, for ayah numbers set in Arabic text.
String arabicDigits(int n) =>
    n.toString().split('').map((d) => String.fromCharCode(0x0660 + int.parse(d))).join();
