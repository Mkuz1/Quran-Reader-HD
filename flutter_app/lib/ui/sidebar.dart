import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/arabic.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../data/page_store.dart';
import '../data/text_library.dart';
import '../data/user_library.dart';
import 'common.dart';

enum SidebarTab {
  surahs('Surahs', Icons.format_list_bulleted),
  juz('Juz', Icons.grid_view),
  search('Search', Icons.search),
  bookmarks('Marks', Icons.bookmark_border),
  notes('Notes', Icons.sticky_note_2_outlined);

  const SidebarTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

class Sidebar extends StatefulWidget {
  /// Called after navigating, so a drawer can close.
  final VoidCallback? onNavigate;
  const Sidebar({super.key, this.onNavigate});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  late SidebarTab _tab = SidebarTab.values.asNameMap()[model.prefs.getString('sidebarTab')] ?? SidebarTab.surahs;
  bool _sortByDate = model.prefs.getBool('bookmarkSortDate') ?? false;
  final _query = TextEditingController();
  int _limit = 50;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _go(VoidCallback action) {
    action();
    widget.onNavigate?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ModelBuilder(
      also: [model.library, model.text, model.pageStore],
      builder: (context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: SegmentedButton<SidebarTab>(
            segments: [
              for (final t in SidebarTab.values)
                ButtonSegment(value: t, icon: Icon(t.icon, size: 18), tooltip: tr(t.label)),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) {
              setState(() => _tab = s.first);
              model.prefs.setString('sidebarTab', _tab.name);
            },
          ),
        ),
        if (_tab == SidebarTab.surahs || _tab == SidebarTab.search)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: _searchField(context),
          ),
        Expanded(child: _list(context)),
        _downloadProgress(context),
      ]),
    );
  }

  Widget _searchField(BuildContext context) {
    final field = TextField(
      controller: _query,
      onChanged: (_) => setState(() => _limit = 50),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.search, size: 20),
        hintText: _tab == SidebarTab.search ? tr('Arabic or translation text') : tr('Surah name or number'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: _query.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() => _query.clear()),
              ),
      ),
    );
    final suggestions = _tab == SidebarTab.search ? model.text.suggestions(_query.text) : const <String>[];
    if (suggestions.isEmpty) return field;
    return Column(children: [
      field,
      const SizedBox(height: 4),
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final w in suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                label: Text(w, style: const TextStyle(fontFamily: arabicFont)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _query.text = w),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _list(BuildContext context) => switch (_tab) {
        SidebarTab.surahs => _surahs(context),
        SidebarTab.juz => _juz(context),
        SidebarTab.search => _search(context),
        SidebarTab.bookmarks => _bookmarks(context),
        SidebarTab.notes => _notes(context),
      };

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  int? get _currentSura => model.firstAyah(model.page)?.sura;

  Widget _surahs(BuildContext context) {
    final meta = model.meta;
    if (meta == null) return _hint(tr('Loading surah list…'));
    final q = _query.text.trim();
    final list = meta.surahs.where((s) =>
        q.isEmpty ||
        '${s.number}' == q ||
        s.englishName.toLowerCase().contains(q.toLowerCase()) ||
        s.englishNameTranslation.toLowerCase().contains(q.toLowerCase()) ||
        Arabic.normalize(s.name).contains(Arabic.normalize(q))).toList();
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final s = list[i];
        return ListTile(
          dense: true,
          selected: _currentSura == s.number,
          selectedTileColor: scheme.primary.withValues(alpha: 0.12),
          leading: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.outline)),
            child: Text('${s.number}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          title: Text(model.surahName(s.number), style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(
              '${tr(s.revelationType == 'Meccan' ? 'Makki' : 'Madani')} · ${tr('%d verses', [s.numberOfAyahs])} · '
              '${tr('Page %d', [model.startPage(s.number)])}'),
          trailing: Text(s.name, style: const TextStyle(fontFamily: quranFont, fontSize: 17)),
          onTap: () => _go(() => model.goTo(model.startPage(s.number))),
        );
      },
    );
  }

  Widget _juz(BuildContext context) {
    final quarters = model.meta?.quarterStarts ?? const <AyahKey>[];
    if (quarters.isEmpty) return _hint(tr('Loading index…'));
    final current = model.quarterIndex(model.page);
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: quarters.length + quarters.length ~/ 8,
      itemBuilder: (context, i) {
        // Each juz' is a header row followed by its eight quarters.
        final juz = i ~/ 9, inJuz = i % 9;
        if (inJuz == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(tr("Juz' %d", [juz + 1]), style: Theme.of(context).textTheme.titleSmall),
          );
        }
        final q = juz * 8 + inJuz - 1;
        final key = quarters[q];
        return ListTile(
          dense: true,
          selected: current == q,
          selectedTileColor: scheme.primary.withValues(alpha: 0.12),
          leading: SizedBox(
            width: 20,
            child: Text(const ['●', '¼', '½', '¾'][q % 4],
                style: const TextStyle(color: AppColors.frameGold, fontWeight: FontWeight.bold)),
          ),
          title: ArabicText(model.snippet(key), size: 15, maxLines: 1),
          subtitle: Text('${AppModel.quarterLabel(q)} · ${model.surahName(key.sura)} $key · '
              '${tr('Page %d', [model.db?.page(key) ?? 1])}'),
          onTap: () => _go(() => model.goToAyah(key)),
        );
      },
    );
  }

  Widget _search(BuildContext context) {
    final q = _query.text;
    if (q.trim().length < 2) {
      return _hint(tr('Search the Arabic text (without needing diacritics) or the %@ translation.',
          [Edition.named(model.translationID).title]));
    }
    final (hits, more) = model.text.search(q, model.translationID, _limit);
    if (hits.isEmpty) {
      return _hint(model.text.isLoaded(Edition.arabicSearch.id) ? tr('No results') : tr('Searching…'));
    }
    return ListView.builder(
      itemCount: hits.length + 1 + (more ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(tr('%@ results', ['${hits.length}${more ? '+' : ''}']),
                style: Theme.of(context).textTheme.titleSmall),
          );
        }
        if (i == hits.length + 1) {
          return TextButton(onPressed: () => setState(() => _limit += 50), child: Text(tr('Show more results…')));
        }
        final hit = hits[i - 1];
        final arabic = hit.edition == Edition.arabicSearch.id;
        return ListTile(
          dense: true,
          title: Text('${model.surahName(hit.key.sura)} : ${hit.key.ayah} · '
              '${tr('Page %d', [model.db?.page(hit.key) ?? 0])}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          subtitle: arabic
              ? ArabicText(model.text.text(Edition.arabic.id, hit.key), size: 15, maxLines: 2)
              : Text(model.text.text(hit.edition, hit.key) ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
          onTap: () => _go(() => model.goToAyah(hit.key)),
        );
      },
    );
  }

  Widget _bookmarks(BuildContext context) {
    final library = model.library;
    if (library.bookmarks.isEmpty) return _hint(tr('Tap the tassel at the top of a page to bookmark it.'));
    final sorted = [...library.bookmarks]
      ..sort((a, b) => _sortByDate ? b.created.compareTo(a.created) : a.page.compareTo(b.page));
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('Page'))),
            ButtonSegment(value: true, label: Text(tr('Date'))),
          ],
          selected: {_sortByDate},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            setState(() => _sortByDate = s.first);
            model.prefs.setBool('bookmarkSortDate', _sortByDate);
          },
        ),
      ),
      for (final b in sorted)
        ListTile(
          dense: true,
          title: Text(b.title ?? model.pageTitle(b.page), style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text('${tr('Page %d', [b.page])} · ${_date(b.created)}'),
          onTap: () => _go(() => model.goTo(b.page)),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => v == 'rename' ? _rename(b) : library.removeBookmark(b),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(tr('Rename…'))),
              PopupMenuItem(value: 'remove', child: Text(tr('Remove Bookmark'))),
            ],
          ),
        ),
    ]);
  }

  Future<void> _rename(Bookmark b) async {
    final controller = TextEditingController(text: b.title ?? model.pageTitle(b.page));
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Rename Bookmark')),
        content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(labelText: tr('Title'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Save'))),
        ],
      ),
    );
    if (title != null) model.library.rename(b, title);
  }

  Widget _notes(BuildContext context) {
    final notes = model.library.notes;
    if (notes.isEmpty) {
      return _hint(tr(isDesktop ? 'Right-click an ayah and choose Add Note.' : 'Long-press an ayah and choose Add Note.'));
    }
    final keys = notes.keys.toList()..sort();
    return ListView(children: [
      for (final key in keys)
        ListTile(
          dense: true,
          title: Text('${model.surahTitle(key.sura)} · $key', style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Text(notes[key]?.text ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => _go(() {
            model.goToAyah(key);
            model.showText(InspectorTab.note, key);
          }),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: tr('Delete Note'),
            onPressed: () => model.library.setNote('', key),
          ),
        ),
    ]);
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Widget _downloadProgress(BuildContext context) {
    final store = model.pageStore;
    return switch (store.state) {
      PageStoreState.downloading => Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Downloading pages… %d%%', [(store.progress * 100).round()]),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: store.progress),
          ]),
        ),
      PageStoreState.installing => Padding(
          padding: const EdgeInsets.all(10),
          child: Text(tr('Installing pages…'), style: Theme.of(context).textTheme.bodySmall),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
