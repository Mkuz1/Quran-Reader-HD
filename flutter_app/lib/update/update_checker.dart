import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/storage.dart';

class AppUpdate {
  final String version;
  final String notes;
  final Uri page;

  /// This platform's installer, when the release has one.
  final Uri? download;
  const AppUpdate(this.version, this.notes, this.page, this.download);
}

/// Numeric version parts, so 1.10 sorts after 1.9. "v1.2" and "1.2.0" compare equal.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+]')).map((s) => int.tryParse(s) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// The newest published app release (tags v1.2, v1.3, …; other releases such as pages-v1 are ignored).
AppUpdate? latestRelease(List<dynamic> releases, {required String assetSuffix}) {
  final tag = RegExp(r'^v\d+(\.\d+)*$');
  Map<String, dynamic>? best;
  for (final r in releases.cast<Map<String, dynamic>>()) {
    final name = r['tag_name'] as String? ?? '';
    if (r['draft'] == true || r['prerelease'] == true || !tag.hasMatch(name)) continue;
    if (best == null || compareVersions(name, best['tag_name'] as String) > 0) best = r;
  }
  if (best == null) return null;
  final asset = (best['assets'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .where((a) => (a['name'] as String? ?? '').endsWith(assetSuffix))
      .firstOrNull;
  return AppUpdate(
    (best['tag_name'] as String).substring(1),
    best['body'] as String? ?? '',
    Uri.parse(best['html_url'] as String),
    asset == null ? null : Uri.parse(asset['browser_download_url'] as String),
  );
}

/// Checks GitHub for a newer release at launch (at most every 6 hours) and on request.
class UpdateChecker extends ChangeNotifier {
  final SharedPreferences _prefs;
  UpdateChecker(this._prefs);

  String currentVersion = '';
  AppUpdate? available;
  bool checking = false;

  /// Result of the last manual check, for "you're up to date" feedback.
  String? lastResult;

  static String get _assetSuffix => Platform.isAndroid ? '.apk' : Platform.isWindows ? '-Setup.exe' : '.dmg';

  Future<void> check({bool manual = false}) async {
    if (checking) return;
    if (currentVersion.isEmpty) await loadVersion();
    final last = _prefs.getInt('lastUpdateCheck') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!manual && now - last < const Duration(hours: 6).inMilliseconds) {
      // Still show an update found earlier and not yet installed or skipped.
      final cached = _prefs.getString('cachedUpdate');
      if (cached != null) _apply(cached, manual: false);
      return;
    }
    checking = true;
    notifyListeners();
    try {
      final body = utf8.decode(await Downloader.get(Remote.releases));
      await _prefs.setInt('lastUpdateCheck', now);
      await _prefs.setString('cachedUpdate', body);
      _apply(body, manual: manual);
    } catch (e) {
      if (manual) lastResult = 'error';
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  void _apply(String body, {required bool manual}) {
    final latest = latestRelease(jsonDecode(body) as List, assetSuffix: _assetSuffix);
    if (latest == null || currentVersion.isEmpty || compareVersions(latest.version, currentVersion) <= 0) {
      available = null;
      if (manual) lastResult = 'current';
      return;
    }
    // A version the user chose to skip is only shown again when they check by hand.
    if (!manual && _prefs.getString('skippedVersion') == latest.version) return;
    available = latest;
    lastResult = null;
  }

  Future<void> loadVersion() async {
    try {
      currentVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
  }

  void skip() {
    final v = available?.version;
    if (v != null) _prefs.setString('skippedVersion', v);
    available = null;
    notifyListeners();
  }

  void dismiss() {
    available = null;
    notifyListeners();
  }
}
