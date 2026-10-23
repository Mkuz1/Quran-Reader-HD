import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/storage.dart';
import '../data/page_store.dart';
import 'common.dart';

/// Offered once after the opening page, and from Settings: install all pages from GitHub for offline
/// reading, or keep reading online.
Future<void> showPagesChoice(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _PagesChoice());

class _PagesChoice extends StatelessWidget {
  const _PagesChoice();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model.pageStore,
      builder: (context, _) {
        final store = model.pageStore;
        void chose() {
          model.prefs.setBool('pagesChoiceMade', true);
          Navigator.pop(context);
        }

        final (content, actions) = switch (store.state) {
          PageStoreState.online || PageStoreState.failed => (
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Download all 604 pages (about %d MB) from GitHub to read offline, or read online: each page loads as you open it.',
                    [Remote.pagesArchiveMB])),
                if (store.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(store.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
              ]),
              [
                TextButton(onPressed: chose, child: Text(tr('Read Online'))),
                FilledButton(
                  onPressed: () {
                    model.prefs.setBool('pagesChoiceMade', true);
                    store.install();
                  },
                  child: Text(tr('Download (%d MB)', [Remote.pagesArchiveMB])),
                ),
              ]
            ),
          PageStoreState.downloading => (
              Column(mainAxisSize: MainAxisSize.min, children: [
                LinearProgressIndicator(value: store.progress),
                const SizedBox(height: 8),
                Text(tr('Downloading pages… %d%%', [(store.progress * 100).round()])),
                const SizedBox(height: 8),
                Text(tr('You can keep reading online while the pages download.'),
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
              [
                TextButton(onPressed: store.cancel, child: Text(tr('Cancel Download'))),
                FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Continue Reading'))),
              ]
            ),
          PageStoreState.installing => (
              Column(mainAxisSize: MainAxisSize.min, children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(tr('Installing pages…')),
              ]),
              const <Widget>[]
            ),
          PageStoreState.installed => (
              Text(tr('All pages are installed. The mushaf now works offline.')),
              [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done')))]
            ),
        };
        return AlertDialog(
          icon: Icon(store.isInstalled ? Icons.check_circle_outline : Icons.menu_book_outlined,
              size: 40, color: AppColors.accent),
          title: Text(tr('Mushaf Pages')),
          content: SizedBox(width: 400, child: content),
          actions: actions,
        );
      },
    );
  }
}

/// Page appearance, language, pages, notes export/import, updates and help.
Future<void> showSettings(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _Settings());

class _Settings extends StatelessWidget {
  const _Settings();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ModelBuilder(
          also: [model.pageStore, model.updates],
          builder: (context) {
            final theme = Theme.of(context);
            Widget section(String title) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
                );
            final store = model.pageStore;
            return ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
              ListTile(
                title: Text(tr('Settings'), style: theme.textTheme.titleLarge),
                trailing: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ),
              section(tr('Page appearance')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SegmentedButton<PageTheme>(
                  segments: [for (final t in PageTheme.values) ButtonSegment(value: t, label: Text(tr(t.label)))],
                  selected: {model.theme},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => model.update(() => model.theme = s.first),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(tr('Brightness')),
                subtitle: Slider(
                  value: model.brightness,
                  min: 0.35,
                  max: 1,
                  onChanged: (v) => model.update(() => model.brightness = v),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.auto_stories_outlined),
                title: Text(tr('Two-page spread')),
                subtitle: Text(tr('When the window or unfolded screen is wide enough')),
                value: model.dualPage,
                onChanged: (v) => model.update(() => model.dualPage = v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.swipe_outlined),
                title: Text(tr('Swipe to turn pages')),
                value: model.swipeEnabled,
                onChanged: (v) => model.update(() => model.swipeEnabled = v),
              ),
              ListTile(
                leading: Icon(store.isInstalled ? Icons.download_done : Icons.cloud_outlined),
                title: Text(tr('Pages')),
                subtitle: Text(store.isInstalled ? tr('Installed') : tr('Online')),
                trailing: store.isInstalled
                    ? TextButton(onPressed: store.remove, child: Text(tr('Remove')))
                    : TextButton(
                        onPressed: store.isBusy ? null : () => showPagesChoice(context), child: Text(tr('Download'))),
              ),
              section(tr('Language')),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SegmentedButton<AppLanguage>(
                  segments: [for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.nativeName))],
                  selected: {Localizer.shared.language},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => model.setLanguage(s.first),
                ),
              ),
              section(tr('Notes & Bookmarks')),
              ListTile(
                leading: const Icon(Icons.html_outlined),
                title: Text(tr('Export Notes & Bookmarks as HTML…')),
                onTap: () => _export(context, html: true),
              ),
              ListTile(
                leading: const Icon(Icons.data_object),
                title: Text(tr('Export Notes & Bookmarks as JSON…')),
                onTap: () => _export(context, html: false),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: Text(tr('Email Notes & Bookmarks…')),
                onTap: () => _email(context),
              ),
              ListTile(
                leading: const Icon(Icons.file_open_outlined),
                title: Text(tr('Import Notes & Bookmarks…')),
                onTap: () => _import(context),
              ),
              section(tr('About')),
              ListTile(
                leading: const Icon(Icons.system_update_alt),
                title: Text(tr('Check for Updates')),
                subtitle: Text(_updateStatus()),
                trailing: model.updates.checking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                onTap: () => model.updates.check(manual: true),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(tr('Mushaf Help')),
                onTap: () => showHelp(context),
              ),
              ListTile(
                leading: const Icon(Icons.favorite_border),
                title: Text(tr('About This Sadaqa Jariyah')),
                onTap: () {
                  Navigator.pop(context);
                  model.showDedication = true;
                  model.update(() {});
                },
              ),
            ]);
          },
        ),
      ),
    );
  }

  String _updateStatus() {
    final u = model.updates;
    final version = tr('Version %@', [u.currentVersion]);
    if (u.available != null) return '$version · ${tr('Version %@ is available', [u.available!.version])}';
    return switch (u.lastResult) {
      'current' => '$version · ${tr('You have the latest version')}',
      'error' => '$version · ${tr("Couldn't check for updates")}',
      _ => version,
    };
  }

  Future<void> _export(BuildContext context, {required bool html}) async {
    if (model.library.isEmpty) return toast(context, tr('There are no notes or bookmarks to export'));
    final name = html ? 'Mushaf Notes & Bookmarks.html' : 'Mushaf Notes & Bookmarks.json';
    final content = html ? model.notesHtml() : model.library.exportJson();
    if (isDesktop) {
      final location = await getSaveLocation(suggestedName: name, acceptedTypeGroups: [
        XTypeGroup(label: html ? 'HTML' : 'JSON', extensions: [html ? 'html' : 'json'])
      ]);
      if (location == null) return;
      await File(location.path).writeAsString(content);
      if (context.mounted) toast(context, tr('Saved'));
    } else {
      final file = File(p.join(Paths.cards.path, name));
      await file.writeAsString(content);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: html ? 'text/html' : 'application/json')],
        subject: 'Mushaf Notes & Bookmarks',
      ));
    }
  }

  Future<void> _email(BuildContext context) async {
    if (model.library.isEmpty) return toast(context, tr('There are no notes or bookmarks to export'));
    // A mailto: link works with whichever mail app is the default.
    final uri = Uri(scheme: 'mailto', query: _encode({'subject': 'Mushaf Notes & Bookmarks', 'body': model.notesPlain()}));
    await launchUrl(uri);
  }

  static String _encode(Map<String, String> params) =>
      params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  Future<void> _import(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json'], mimeTypes: ['application/json'])
    ]);
    if (file == null) return;
    try {
      model.library.apply(await file.readAsString(), merge: true);
      if (context.mounted) toast(context, tr('Imported'));
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    }
  }
}

Future<void> showHelp(BuildContext context) {
  final tips = <(IconData, String)>[
    (
      Icons.touch_app_outlined,
      isDesktop
          ? 'Click an ayah to select it and see its translation, tafsir and note. Double-click to recite from it.'
          : 'Tap an ayah to select it and see its translation, tafsir and note. Double-tap to recite from it.'
    ),
    (
      Icons.more_horiz,
      isDesktop
          ? 'Right-click an ayah for the menu: play, memorisation range, translation, tafsir, note, copy and share.'
          : 'Long-press an ayah for the menu: play, memorisation range, translation, tafsir, note, copy and share.'
    ),
    (Icons.image_outlined, 'Share as Image makes a card of the ayah with its full tashkeel, ready to send.'),
    (Icons.bookmark_border, 'Tap the tassel at the top of a page to bookmark it. Tap it again to remove the bookmark.'),
    (
      Icons.swap_horiz,
      isDesktop
          ? 'Use the ← → keys, the toolbar arrows, the mouse wheel, or drag the page to turn pages.'
          : 'Swipe to turn pages. On a foldable, unfold the phone to see a two-page spread.'
    ),
    (Icons.linear_scale, "Drag the slider below the page to jump anywhere; it shows the surah, juz' and hizb."),
    (
      Icons.repeat,
      'In the recitation options, repeat each ayah or the whole selection (up to ∞) and pick a stopping point with Play To.'
    ),
    (Icons.search, 'The Search tab finds words in the Arabic text, with or without diacritics, or in the translation.'),
  ];
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Using Mushaf')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(tr(text))),
                ]),
              ),
          ]),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done')))],
    ),
  );
}
