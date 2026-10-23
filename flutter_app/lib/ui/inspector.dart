import 'dart:async';

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../data/text_library.dart';
import 'ayah_menu.dart';
import 'common.dart';
import 'share_card.dart';

/// Translation, tafsir and note for the selected ayah.
class AyahInspector extends StatelessWidget {
  final VoidCallback? onClose;
  const AyahInspector({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    return ModelBuilder(
      also: [model.text, model.library],
      builder: (context) {
        final key = model.selected;
        if (key == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.touch_app_outlined, size: 40, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                Text(tr('No Ayah Selected'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(tr('Click an ayah on the page to see its translation, tafsir and your notes.'),
                    textAlign: TextAlign.center),
                if (onClose != null) ...[
                  const SizedBox(height: 12),
                  TextButton(onPressed: onClose, child: Text(tr('Done'))),
                ],
              ]),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context, key),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(child: ArabicText(model.text.text(Edition.arabic.id, key), size: 24)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<InspectorTab>(
              segments: [for (final t in InspectorTab.values) ButtonSegment(value: t, label: Text(tr(t.label)))],
              selected: {model.inspectorTab},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                model.inspectorTab = s.first;
                model.update(() {});
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: switch (model.inspectorTab) {
                InspectorTab.translation => _EditionText(
                    ayah: key,
                    editionID: model.translationID,
                    choices: Edition.translations,
                    onChanged: (id) => model.update(() => model.translationID = id)),
                InspectorTab.tafsir => _EditionText(
                    ayah: key,
                    editionID: model.tafsirID,
                    choices: Edition.tafsirs,
                    onChanged: (id) => model.update(() => model.tafsirID = id)),
                InspectorTab.note => _NoteEditor(key: ValueKey(key), ayah: key),
              },
            ),
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, AyahKey key) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(model.surahTitle(key.sura), style: Theme.of(context).textTheme.titleMedium),
          Text(tr('Ayah %d', [key.ayah]), style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      IconButton(
          onPressed: () => model.audio.play(key, to: key),
          icon: const Icon(Icons.play_circle_outline),
          tooltip: tr('Recite this ayah')),
      IconButton(
          onPressed: () => copyText(context, model.arabicWithCitation(key)),
          icon: const Icon(Icons.copy),
          tooltip: tr('Copy Arabic text')),
      IconButton(
          onPressed: () => showShareCard(context, key),
          icon: const Icon(Icons.image_outlined),
          tooltip: tr('Share as Image…')),
      IconButton(
          onPressed: () => shareText(context, key), icon: const Icon(Icons.share), tooltip: tr('Share this ayah')),
      if (onClose != null) IconButton(onPressed: onClose, icon: const Icon(Icons.close), tooltip: tr('Done')),
    ]);
  }
}

class _EditionText extends StatefulWidget {
  final AyahKey ayah;
  final String editionID;
  final List<Edition> choices;
  final ValueChanged<String> onChanged;
  const _EditionText({required this.ayah, required this.editionID, required this.choices, required this.onChanged});

  @override
  State<_EditionText> createState() => _EditionTextState();
}

class _EditionTextState extends State<_EditionText> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(_EditionText old) {
    super.didUpdateWidget(old);
    if (old.editionID != widget.editionID || old.ayah.sura != widget.ayah.sura) _ensure();
  }

  void _ensure() => model.text.ensure(widget.editionID, sura: widget.ayah.sura);

  @override
  Widget build(BuildContext context) {
    final edition = Edition.named(widget.editionID);
    final t = model.text.text(widget.editionID, widget.ayah);
    final err = model.text.errors[widget.editionID];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButton<String>(
        value: widget.editionID,
        isExpanded: true,
        items: [
          for (final e in widget.choices)
            DropdownMenuItem(value: e.id, child: Text(e.title, overflow: TextOverflow.ellipsis))
        ],
        onChanged: (id) => widget.onChanged(id!),
      ),
      Expanded(
        child: SingleChildScrollView(
          child: t != null
              ? (edition.isRTL
                  ? ArabicText(t, size: 18, quran: false)
                  : SelectableText(t, style: const TextStyle(height: 1.5)))
              : err != null
                  ? Row(children: [
                      const Icon(Icons.warning_amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(err)),
                      TextButton(onPressed: _ensure, child: Text(tr('Retry'))),
                    ])
                  : Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(tr('Downloading %@…', [edition.title]), textAlign: TextAlign.center),
                      ]),
                    ),
        ),
      ),
    ]);
  }
}

class _NoteEditor extends StatefulWidget {
  final AyahKey ayah;
  const _NoteEditor({super.key, required this.ayah});

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _controller = TextEditingController(text: model.library.notes[widget.ayah]?.text ?? '');
  Timer? _save;

  @override
  void dispose() {
    _save?.cancel();
    model.library.setNote(_controller.text, widget.ayah);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = model.library.notes[widget.ayah];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: TextField(
          controller: _controller,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            filled: true,
            hintText: tr('Note'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (text) {
            _save?.cancel();
            _save = Timer(const Duration(milliseconds: 600), () => model.library.setNote(text, widget.ayah));
          },
        ),
      ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(tr('Saved %@', [note.updated.toLocal().toString().split('.').first]),
              style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }
}
