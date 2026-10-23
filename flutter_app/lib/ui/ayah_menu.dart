import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../data/text_library.dart';
import 'common.dart';
import 'share_card.dart';

/// The ayah menu shared by the page view and the translation list: right-click on Windows, long-press on Android.
Future<void> showAyahMenu(BuildContext context, AyahKey key, Offset globalPosition) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(globalPosition & const Size(1, 1), Offset.zero & overlay.size);
  final audio = model.audio;
  final hasArabic = model.text.text(Edition.arabic.id, key) != null;
  final page = model.db?.page(key);
  PopupMenuItem<VoidCallback> item(String label, IconData icon, VoidCallback action, {bool enabled = true}) =>
      PopupMenuItem(
        value: action,
        enabled: enabled,
        height: 40,
        child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 12), Flexible(child: Text(label))]),
      );

  final action = await showMenu<VoidCallback>(
    context: context,
    position: position,
    items: [
      PopupMenuItem(
        enabled: false,
        height: 32,
        child: Text(tr('%@ — Ayah %d', [model.surahTitle(key.sura), key.ayah]),
            style: Theme.of(context).textTheme.labelMedium),
      ),
      item(tr('Play From Here'), Icons.play_arrow, () {
        model.select(key);
        audio.play(key);
      }),
      item(tr('Play This Ayah Only'), Icons.play_circle_outline, () {
        model.select(key);
        audio.play(key, to: key);
      }),
      item(tr('Set as Range Start'), Icons.first_page, () {
        audio.rangeStart = key;
        final e = audio.rangeEnd;
        audio.rangeEnd = e == null ? key : maxKey(e, key);
        audio.changed();
      }),
      item(tr('Set as Range End'), Icons.last_page, () {
        audio.rangeEnd = key;
        final s = audio.rangeStart;
        if (s == null || s > key) audio.rangeStart = key;
        audio.changed();
      }),
      item(tr('Play Range'), Icons.repeat, audio.playRange, enabled: audio.rangeStart != null),
      const PopupMenuDivider(),
      item(tr('Translation'), Icons.translate, () => model.showText(InspectorTab.translation, key)),
      item(tr('Tafsir'), Icons.menu_book, () => model.showText(InspectorTab.tafsir, key)),
      item(tr(model.library.notes[key] == null ? 'Add Note…' : 'Edit Note…'), Icons.sticky_note_2_outlined,
          () => model.showText(InspectorTab.note, key)),
      const PopupMenuDivider(),
      item(tr('Share as Image…'), Icons.image_outlined, () => showShareCard(context, key), enabled: hasArabic),
      item(tr('Copy Arabic Text'), Icons.copy, () => copyText(context, model.arabicWithCitation(key)),
          enabled: hasArabic),
      item(tr('Copy with Translation'), Icons.copy_all, () => copyText(context, model.shareText(key)),
          enabled: hasArabic),
      item(tr('Share…'), Icons.share, () => shareText(context, key)),
      if (page != null)
        item(model.library.isBookmarked(page) ? tr('Remove Page Bookmark') : tr('Bookmark Page %d', [page]),
            Icons.bookmark_border, () => model.library.toggleBookmark(page, title: model.pageTitle(page))),
    ],
  );
  action?.call();
}

void copyText(BuildContext context, String text) {
  Clipboard.setData(ClipboardData(text: text));
  toast(context, tr('Copied'));
}

Future<void> shareText(BuildContext context, AyahKey key) async {
  final box = context.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    text: model.shareText(key),
    subject: model.citation(key),
    sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
  ));
}
