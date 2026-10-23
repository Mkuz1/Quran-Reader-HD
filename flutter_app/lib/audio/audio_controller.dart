import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';
import '../core/quran.dart';
import '../core/storage.dart';
import '../data/glyph_db.dart';
import 'reciters.dart';

enum PlayScope {
  ayah('This ayah'),
  surah('To end of surah'),
  quran('Continue through Quran');

  const PlayScope(this.label);
  final String label;
}

/// Verse-by-verse recitation with per-verse and per-range repeat, for memorisation.
class AudioController extends ChangeNotifier {
  final SharedPreferences _prefs;
  GlyphDB? db;

  AudioController(this._prefs) {
    final saved = _prefs.getString('reciter');
    _reciter = reciters.any((r) => r.id == saved) ? saved! : reciters.first.id;
  }

  /// Created on first use, so launching doesn't start the audio engine.
  AudioPlayer? _audioPlayer;
  AudioPlayer get _player =>
      _audioPlayer ??= AudioPlayer()..onPlayerComplete.listen((_) => _itemFinished());

  late String _reciter;
  String get reciter => _reciter;
  set reciter(String id) {
    _reciter = id;
    _prefs.setString('reciter', id);
    final c = current;
    if (c != null) play(c);
    notifyListeners();
  }

  PlayScope scope = PlayScope.surah;

  /// Repeat counts; [infinite] loops until stopped.
  int verseRepeat = 1;
  int rangeRepeat = 1;
  static const infinite = 1 << 30;
  static const repeatChoices = [1, 2, 3, 5, 7, 10, infinite];
  static String repeatLabel(int n) => n == infinite ? '∞' : n == 1 ? tr('Once') : '$n×';

  AyahKey? rangeStart;
  AyahKey? rangeEnd;

  AyahKey? current;
  bool isPlaying = false;
  bool isLoading = false;
  String? errorMessage;

  AyahKey _start = const AyahKey(1, 1);
  AyahKey? _end; // null: run to the end of the Quran
  int _verseCount = 0;
  int _rangeCount = 0;
  bool _inBismillah = false;
  int _generation = 0;

  bool get isActive => current != null;

  void changed() => notifyListeners();

  /// Starts at [key]. Without an explicit [to], the current scope decides where to stop.
  void play(AyahKey key, {AyahKey? to}) {
    final db = this.db;
    if (db == null) return;
    _start = key;
    if (to != null) {
      _end = maxKey(to, key);
    } else {
      _end = switch (scope) {
        PlayScope.ayah => key,
        PlayScope.surah => AyahKey(key.sura, db.ayahCounts[key.sura]),
        PlayScope.quran => null,
      };
    }
    _verseCount = 0;
    _rangeCount = 0;
    _load(key, withBismillah: true);
  }

  void playRange() {
    final s = rangeStart;
    if (s != null) play(s, to: rangeEnd ?? s);
  }

  void togglePause() {
    if (current == null) return;
    if (isPlaying) {
      _player.pause();
    } else {
      _player.resume();
    }
    isPlaying = !isPlaying;
    notifyListeners();
  }

  void stop() {
    _generation++;
    _audioPlayer?.stop();
    current = null;
    isPlaying = false;
    isLoading = false;
    _inBismillah = false;
    notifyListeners();
  }

  void skip(bool forward) {
    final c = current, db = this.db;
    if (c == null || db == null) return;
    final target = forward ? db.next(c) : db.previous(c);
    if (target == null) return;
    _verseCount = 0;
    final e = _end;
    if (e != null && target > e) _end = target;
    if (target < _start) _start = target;
    _load(target, withBismillah: true);
  }

  Future<void> _load(AyahKey key, {required bool withBismillah}) async {
    final gen = ++_generation;
    current = key;
    errorMessage = null;
    // Every surah except Al-Fatiha (where it is ayah 1) and At-Tawbah opens with the basmala.
    final bismillah = withBismillah && key.ayah == 1 && key.sura != 1 && key.sura != 9;
    _inBismillah = bismillah;
    isLoading = true;
    notifyListeners();
    try {
      final file = await _file(bismillah ? const AyahKey(1, 1) : key);
      if (gen != _generation) return;
      await _player.stop();
      await _player.play(DeviceFileSource(file.path));
      isPlaying = true;
      isLoading = false;
      notifyListeners();
      _prefetch(key);
    } catch (e) {
      if (gen != _generation) return;
      errorMessage = e.toString();
      stop();
    }
  }

  void _itemFinished() {
    final c = current, db = this.db;
    if (c == null || db == null) return;
    if (_inBismillah) {
      _load(c, withBismillah: false);
      return;
    }
    _verseCount++;
    if (_verseCount < verseRepeat) {
      _load(c, withBismillah: false);
      return;
    }
    _verseCount = 0;
    final next = db.next(c);
    final end = _end;
    if (next == null || (end != null && c >= end)) {
      _rangeCount++;
      if (_rangeCount < rangeRepeat) {
        _load(_start, withBismillah: true);
      } else {
        stop();
      }
      return;
    }
    _load(next, withBismillah: true);
  }

  Future<File> _file(AyahKey key) => Downloader.fetch(
      Remote.audio(_reciter, key), File(p.join(Paths.audio(_reciter).path, '${pad3(key.sura)}${pad3(key.ayah)}.mp3')));

  void _prefetch(AyahKey key) {
    final db = this.db;
    if (db == null) return;
    unawaited(() async {
      var k = key;
      for (var i = 0; i < 3; i++) {
        final n = db.next(k);
        if (n == null) break;
        try {
          await _file(n);
        } catch (_) {}
        k = n;
      }
    }());
  }
}
