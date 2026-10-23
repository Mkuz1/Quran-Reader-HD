import 'package:flutter/material.dart';

import '../app_model.dart';
import '../audio/audio_controller.dart';
import '../audio/reciters.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import 'common.dart';

/// Pause/resume if something is loaded; otherwise start from the selection or the top of the page.
void playPause() {
  final audio = model.audio;
  if (audio.isActive) return audio.togglePause();
  final starts = [for (final p in model.visiblePages()) ?model.firstAyah(p)]..sort();
  final start = model.selected ?? (starts.isEmpty ? null : starts.first);
  if (start != null) audio.play(start);
}

/// Page slider and recitation controls, floating over the bottom of the reader.
class Dock extends StatelessWidget {
  final bool compact;
  const Dock({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: scheme.surfaceContainer.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(compact ? 18 : 24),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (model.mode == ReadingMode.mushaf) const PageSlider(),
          AudioBar(compact: compact),
        ]),
      ),
    );
  }
}

/// Jump bar (the original's page slider): page 1 sits on the right, like the book.
class PageSlider extends StatefulWidget {
  const PageSlider({super.key});

  @override
  State<PageSlider> createState() => _PageSliderState();
}

class _PageSliderState extends State<PageSlider> {
  double? _drag;

  String _label(int page) {
    final first = model.firstAyah(page);
    final sura = first == null ? '' : ' · ${model.surahName(first.sura)}';
    return '${tr('Page %d', [page])}$sura · ${tr("Juz' %d", [model.juzFor(page)])} · '
        '${AppModel.quarterLabel(model.quarterIndex(page))}';
  }

  @override
  Widget build(BuildContext context) {
    return ModelBuilder(builder: (context) {
      final shown = (_drag ?? model.page.toDouble()).round();
      return Row(children: [
        Flexible(
          flex: 2,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Text(_label(shown),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ),
        ),
        Expanded(
          flex: 3,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Slider(
              value: _drag ?? model.page.toDouble(),
              min: 1,
              max: Quran.pageCount.toDouble(),
              onChanged: (v) => setState(() => _drag = v.roundToDouble()),
              onChangeEnd: (v) {
                model.goTo(v.round());
                setState(() => _drag = null);
              },
            ),
          ),
        ),
      ]);
    });
  }
}

class AudioBar extends StatelessWidget {
  final bool compact;
  const AudioBar({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ModelBuilder(
      also: [model.audio],
      builder: (context) {
        final audio = model.audio;
        final scheme = Theme.of(context).colorScheme;
        final reciter = reciters.where((r) => r.id == audio.reciter).firstOrNull?.localizedName ?? audio.reciter;
        Widget nowPlaying;
        final err = audio.errorMessage, key = audio.current;
        if (err != null) {
          nowPlaying = Text(err, style: TextStyle(color: scheme.error), maxLines: 1, overflow: TextOverflow.ellipsis);
        } else if (key != null) {
          nowPlaying = Row(children: [
            if (audio.isLoading)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.graphic_eq, size: 18, color: audio.isPlaying ? scheme.primary : null),
            const SizedBox(width: 8),
            Flexible(
                child: Text('${model.surahTitle(key.sura)} · $key', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]);
        } else {
          nowPlaying = Text(tr(isDesktop ? 'Double-click an ayah to recite' : 'Double-tap an ayah to recite'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant));
        }
        final range = audio.rangeStart;
        return Row(children: [
          IconButton(
              onPressed: audio.isActive ? () => audio.skip(false) : null,
              icon: const Icon(Icons.skip_previous),
              tooltip: tr('Previous ayah')),
          IconButton.filled(
              onPressed: playPause,
              icon: Icon(audio.isPlaying ? Icons.pause : Icons.play_arrow),
              tooltip: tr(audio.isPlaying ? 'Pause' : 'Play')),
          IconButton(
              onPressed: audio.isActive ? () => audio.skip(true) : null,
              icon: const Icon(Icons.skip_next),
              tooltip: tr('Next ayah')),
          if (!compact)
            IconButton(
                onPressed: audio.isActive ? audio.stop : null, icon: const Icon(Icons.stop), tooltip: tr('Stop')),
          const SizedBox(width: 6),
          Expanded(child: DefaultTextStyle.merge(style: Theme.of(context).textTheme.bodyMedium, child: nowPlaying)),
          if (range != null && !compact)
            InputChip(
              label: Text(tr('Range %@–%@', [range, audio.rangeEnd ?? range])),
              onPressed: audio.playRange,
              onDeleted: () {
                audio.rangeStart = null;
                audio.rangeEnd = null;
                audio.changed();
              },
              tooltip: tr('Play the memorisation range'),
            ),
          if (compact)
            IconButton(
                onPressed: () => showAudioOptions(context), icon: const Icon(Icons.tune), tooltip: tr('Reciter, scope and repeat'))
          else
            TextButton.icon(
              onPressed: () => showAudioOptions(context),
              icon: const Icon(Icons.tune, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(_summary(reciter, audio), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
        ]);
      },
    );
  }

  String _summary(String reciter, AudioController audio) {
    final parts = [reciter];
    if (audio.verseRepeat > 1) parts.add('${tr('Ayah')} ${AudioController.repeatLabel(audio.verseRepeat)}');
    if (audio.rangeRepeat > 1) parts.add('${tr('Repeat selection')} ${AudioController.repeatLabel(audio.rangeRepeat)}');
    return parts.join(' · ');
  }
}

Future<void> showAudioOptions(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _AudioOptions());

class _AudioOptions extends StatefulWidget {
  const _AudioOptions();

  @override
  State<_AudioOptions> createState() => _AudioOptionsState();
}

class _AudioOptionsState extends State<_AudioOptions> {
  late AyahKey _from;
  late AyahKey _to;

  @override
  void initState() {
    super.initState();
    final audio = model.audio;
    _from = audio.rangeStart ?? model.selected ?? model.firstAyah(model.page) ?? const AyahKey(1, 1);
    _to = audio.rangeEnd ?? _from;
  }

  @override
  Widget build(BuildContext context) {
    final audio = model.audio;
    // Label beside the field when there is room, above it on phones.
    Widget row(String label, Widget field) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth < 400
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: Theme.of(context).textTheme.labelLarge),
                    field,
                  ])
                : Row(children: [
                    SizedBox(width: 150, child: Text(label)),
                    Expanded(child: field),
                  ]),
          ),
        );
    Widget one(String text) => Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis);
    DropdownButton<int> repeats(int value, ValueChanged<int> onChanged) => DropdownButton<int>(
          value: value,
          isExpanded: true,
          items: [
            for (final n in AudioController.repeatChoices)
              DropdownMenuItem(value: n, child: one(AudioController.repeatLabel(n)))
          ],
          onChanged: (v) => setState(() => onChanged(v!)),
        );
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: Text(tr('Recitation')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: ListenableBuilder(
            listenable: audio,
            builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              row(
                tr('Reciter'),
                DropdownButton<String>(
                  value: audio.reciter,
                  isExpanded: true,
                  items: [
                    for (final r in reciters)
                      DropdownMenuItem(value: r.id, child: one(r.localizedName))
                  ],
                  onChanged: (v) => audio.reciter = v!,
                ),
              ),
              row(
                tr('Play'),
                DropdownButton<PlayScope>(
                  value: audio.scope,
                  isExpanded: true,
                  items: [for (final s in PlayScope.values) DropdownMenuItem(value: s, child: one(tr(s.label)))],
                  onChanged: (v) => setState(() => audio.scope = v!),
                ),
              ),
              row(tr('Repeat each ayah'), repeats(audio.verseRepeat, (v) => audio.verseRepeat = v)),
              row(tr('Repeat selection'), repeats(audio.rangeRepeat, (v) => audio.rangeRepeat = v)),
              const Divider(height: 24),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(tr('Play To — choose a stopping point'), style: Theme.of(context).textTheme.titleSmall),
              ),
              AyahPicker(
                  label: tr('From'),
                  value: _from,
                  onChanged: (k) => setState(() {
                        _from = k;
                        if (_to < k) _to = k;
                      })),
              AyahPicker(
                  label: tr('To'),
                  value: _to,
                  onChanged: (k) => setState(() {
                        _to = k;
                        if (_from > k) _from = k;
                      })),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done'))),
        FilledButton(
          onPressed: () {
            audio.rangeStart = _from;
            audio.rangeEnd = _to;
            audio.play(_from, to: _to);
            Navigator.pop(context);
          },
          child: Text(tr('Play Selection')),
        ),
      ],
    );
  }
}

/// Surah + ayah chooser for the Play To range.
class AyahPicker extends StatelessWidget {
  final String label;
  final AyahKey value;
  final ValueChanged<AyahKey> onChanged;
  const AyahPicker({super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final count = model.db?.ayahCounts[value.sura] ?? 1;
    Widget one(String text) => Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis);
    final pickers = Row(children: [
      Expanded(
        flex: 3,
        child: DropdownButton<int>(
          value: value.sura,
          isExpanded: true,
          items: [
            for (var n = 1; n <= 114; n++)
              DropdownMenuItem(value: n, child: one(model.surahTitle(n)))
          ],
          onChanged: (n) => onChanged(AyahKey(n!, 1)),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: DropdownButton<int>(
          value: value.ayah.clamp(1, count < 1 ? 1 : count),
          isExpanded: true,
          items: [
            for (var a = 1; a <= (count < 1 ? 1 : count); a++)
              DropdownMenuItem(value: a, child: one(tr('Ayah %d', [a])))
          ],
          onChanged: (a) => onChanged(AyahKey(value.sura, a!)),
        ),
      ),
    ]);
    // "From" / "To" beside the pickers when there is room, above them on phones.
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < 400
          ? Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                pickers,
              ]),
            )
          : Row(children: [SizedBox(width: 60, child: Text(label)), Expanded(child: pickers)]),
    );
  }
}
