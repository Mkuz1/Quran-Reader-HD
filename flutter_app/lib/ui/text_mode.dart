import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../data/text_library.dart';
import 'ayah_menu.dart';
import 'common.dart';

/// Translation/tafsir-only mode: the current surah as a scrolling list of ayahs.
class TextModeView extends StatefulWidget {
  const TextModeView({super.key});

  @override
  State<TextModeView> createState() => _TextModeViewState();
}

class _TextModeViewState extends State<TextModeView> {
  bool _showTafsir = false;
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};
  AyahKey? _lastAudio;
  String? _ensured;

  int get _sura => model.firstAyah(model.page)?.sura ?? 1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jump(int n) => model.goTo(model.startPage(n));

  /// Fetches once per surah and edition choice; Retry is a sura change or a new edition, not every rebuild.
  void _ensureTexts() {
    final tag = '${model.translationID}/${model.tafsirID}/$_sura/$_showTafsir';
    if (tag == _ensured) return;
    _ensured = tag;
    model.text.ensure(model.translationID);
    if (_showTafsir) model.text.ensure(model.tafsirID, sura: _sura);
  }

  @override
  Widget build(BuildContext context) {
    return ModelBuilder(
      also: [model.text, model.audio, model.library],
      builder: (context) {
        final sura = _sura;
        final count = model.db?.ayahCounts[sura] ?? 0;
        _ensureTexts();
        _followAudio(sura);
        final s = model.surah(sura);
        final theme = Theme.of(context);
        return Container(
          color: theme.brightness == Brightness.dark ? AppColors.paperDark : AppColors.paperLight,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Material(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            onPressed: sura > 1 ? () => _jump(sura - 1) : null, icon: const Icon(Icons.chevron_left)),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(model.surahTitle(sura), style: theme.textTheme.titleSmall),
                          if (s != null)
                            Text(
                              '${Localizer.shared.language == AppLanguage.arabic ? s.englishName : s.englishNameTranslation}'
                              ' · ${tr(s.revelationType == 'Meccan' ? 'Makki' : 'Madani')} · ${tr('%d verses', [s.numberOfAyahs])}',
                              style: theme.textTheme.bodySmall,
                            ),
                        ]),
                        IconButton(
                            onPressed: sura < 114 ? () => _jump(sura + 1) : null, icon: const Icon(Icons.chevron_right)),
                      ]),
                      SegmentedButton<StudyDisplay>(
                        segments: [
                          for (final d in StudyDisplay.values) ButtonSegment(value: d, label: Text(tr(d.label)))
                        ],
                        selected: {model.studyDisplay},
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        onSelectionChanged: (v) => model.update(() => model.studyDisplay = v.first),
                      ),
                      FilterChip(
                        label: Text(tr('Tafsir')),
                        selected: _showTafsir,
                        onSelected: (v) => setState(() => _showTafsir = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 140),
                itemCount: count,
                itemBuilder: (context, i) => _row(context, AyahKey(sura, i + 1)),
              ),
            ),
          ]),
        );
      },
    );
  }

  void _followAudio(int sura) {
    final c = model.audio.current;
    if (c == null || c == _lastAudio || c.sura != sura) return;
    _lastAudio = c;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rowKeys[c.ayah]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 300));
      }
    });
  }

  Widget _row(BuildContext context, AyahKey key) {
    final active = model.audio.current == key;
    final selected = model.selected == key;
    final translation = Edition.named(model.translationID);
    final t = model.studyDisplay != StudyDisplay.arabic ? model.text.text(model.translationID, key) : null;
    final tafsir = _showTafsir ? model.text.text(model.tafsirID, key) : null;
    final note = model.library.notes[key];
    final scheme = Theme.of(context).colorScheme;
    void menu(Offset at) => showAyahMenu(context, key, at);
    return GestureDetector(
      key: _rowKeys.putIfAbsent(key.ayah, GlobalKey.new),
      behavior: HitTestBehavior.opaque,
      onTap: () => model.select(key),
      onDoubleTap: () {
        model.select(key);
        model.audio.play(key);
      },
      onLongPressStart: (d) => menu(d.globalPosition),
      onSecondaryTapUp: (d) => menu(d.globalPosition),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active
              ? Colors.green.withValues(alpha: 0.15)
              : selected
                  ? scheme.primary.withValues(alpha: 0.10)
                  : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$key', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 8),
            if (model.studyDisplay != StudyDisplay.translation)
              Expanded(child: ArabicText(model.text.text(Edition.arabic.id, key), size: 24)),
          ]),
          if (t != null)
            translation.isRTL ? ArabicText(t, size: 18, quran: false) : SelectableText(t, style: const TextStyle(height: 1.5)),
          if (tafsir != null) ...[
            const SizedBox(height: 6),
            Edition.named(model.tafsirID).isRTL
                ? ArabicText(tafsir, size: 16, quran: false, color: scheme.onSurfaceVariant)
                : Text(tafsir, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45)),
          ],
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                const Icon(Icons.sticky_note_2_outlined, size: 16, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(child: Text(note.text, style: const TextStyle(color: Colors.orange))),
              ]),
            ),
        ]),
      ),
    );
  }
}
