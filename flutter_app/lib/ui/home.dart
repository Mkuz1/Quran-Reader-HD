import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import 'common.dart';
import 'dedication.dart';
import 'dock.dart';
import 'inspector.dart';
import 'reader.dart';
import 'settings.dart';
import 'sidebar.dart';
import 'text_mode.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _focus = FocusNode();
  Timer? _hideControls;
  bool _controlsWereVisible = false;

  @override
  void initState() {
    super.initState();
    model.bootstrap();
    model.addListener(_controlsChanged);
    Future<void>.delayed(const Duration(seconds: 3), model.updates.check);
  }

  @override
  void dispose() {
    model.removeListener(_controlsChanged);
    _hideControls?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// Controls shown over a full-screen page hide again after a few seconds without a touch.
  void _controlsChanged() {
    final visible = model.fullScreen && model.controlsVisible;
    if (visible && !_controlsWereVisible) _restartHideTimer();
    if (!visible) _hideControls?.cancel();
    _controlsWereVisible = visible;
  }

  void _restartHideTimer() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 5), () => model.showControls(false));
  }

  void _begin({bool resume = false, bool listen = false, bool fromStart = false}) {
    model.showDedication = false;
    model.update(() {});
    if (fromStart) model.goTo(1);
    if (resume) model.resume(listen: listen);
    // Reopened in full screen: hide the system bars again.
    if (model.fullScreen) model.applySystemBars();
    // First run: offer to install the pages (they are not shipped in the app).
    if (!model.pageStore.isInstalled && !(model.prefs.getBool('pagesChoiceMade') ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showPagesChoice(context);
      });
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return ModelBuilder(
      also: [model.updates],
      builder: (context) {
        if (model.showDedication) {
          return DedicationView(
            onContinue: () => _begin(resume: true),
            onListen: () => _begin(resume: true, listen: true),
            onStartOver: () => _begin(fromStart: true),
          );
        }
        return CallbackShortcuts(
          bindings: {
            // Arabic books open right-to-left: the left arrow is the next page.
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => model.turn(forward: true),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => model.turn(forward: false),
            const SingleActivator(LogicalKeyboardKey.space): playPause,
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                model.fullScreen ? model.setFullScreen(false) : model.select(null),
            const SingleActivator(LogicalKeyboardKey.f11): () => model.setFullScreen(!model.fullScreen),
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
                model.library.toggleBookmark(model.page, title: model.pageTitle(model.page)),
          },
          child: Focus(
            focusNode: _focus,
            autofocus: true,
            // Back leaves full screen before it leaves the app.
            child: PopScope(
              canPop: !model.fullScreen,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) model.setFullScreen(false);
              },
              child: _immersive ? _fullScreen(context) : _scaffoldFor(context),
            ),
          ),
        );
      },
    );
  }

  void _enterFullScreen(BuildContext context) {
    model.setFullScreen(true);
    toast(context, tr('Tap the page to show the controls.'));
  }

  bool get _immersive => model.fullScreen && model.mode == ReadingMode.mushaf && model.status == LoadStatus.ready;

  /// Full screen: the page alone, edge to edge. A tap shows the title bar and the player over the page (it
  /// doesn't move), and they hide again after a few seconds; recitation carries on underneath.
  Widget _fullScreen(BuildContext context) {
    final mq = MediaQuery.of(context);
    final compact = mq.size.width < 600;
    final shown = model.controlsVisible;
    final page = model.page;
    final scheme = Theme.of(context).colorScheme;
    void closeInspector() {
      model.showInspector = false;
      model.update(() {});
    }

    Widget overlay(Widget child, {required bool top}) => IgnorePointer(
          ignoring: !shown,
          child: AnimatedSlide(
            offset: shown ? Offset.zero : Offset(0, top ? -1 : 1),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Listener(onPointerDown: (_) => _restartHideTimer(), child: child),
            ),
          ),
        );

    return Scaffold(
      body: Stack(children: [
        // Taps beside the page (the desk) toggle the controls too.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => model.showControls(!shown),
            child: MushafReader(fold: verticalFold(mq), edgeToEdge: true),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: overlay(
            top: true,
            Material(
              color: scheme.surface.withValues(alpha: 0.92),
              elevation: 2,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(children: [
                    IconButton(
                      onPressed: () => model.setFullScreen(false),
                      icon: const Icon(Icons.fullscreen_exit),
                      tooltip: tr('Exit Full Screen'),
                    ),
                    Expanded(child: _title(context, page, compact)),
                    IconButton(
                      onPressed: () => model.library.toggleBookmark(page, title: model.pageTitle(page)),
                      icon: Icon(model.library.isBookmarked(page) ? Icons.bookmark : Icons.bookmark_border),
                      tooltip: tr('Bookmark this page'),
                    ),
                    IconButton(
                      onPressed: () {
                        model.showInspector = !model.showInspector;
                        model.update(() {});
                      },
                      icon: const Icon(Icons.vertical_split_outlined),
                      tooltip: tr('Translation, tafsir and notes'),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10 + mq.padding.bottom,
          child: overlay(
            top: false,
            Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: Dock(compact: compact)),
            ),
          ),
        ),
        if (model.showInspector)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: mq.size.height * 0.5,
            child: Material(
              elevation: 12,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(top: false, child: AyahInspector(onClose: closeInspector)),
            ),
          ),
      ]),
    );
  }

  Widget _scaffoldFor(BuildContext context) {
    final mq = MediaQuery.of(context);
    final vFold = verticalFold(mq);
    final hFold = horizontalFold(mq);
    final width = mq.size.width;
    final wide = width >= 1100 && vFold == null;
    final medium = width >= 760 && vFold == null;
    final compactBar = width < 600;
    final ready = model.status == LoadStatus.ready;

    Widget body;
    if (!ready) {
      body = _status(context);
    } else {
      // The dock's height (page slider and recitation row) plus its margin.
      final dockSpace = hFold == null ? 118 + mq.padding.bottom : 0.0;
      final reader = model.mode == ReadingMode.mushaf
          ? MushafReader(fold: vFold != null && !model.showInspector ? vFold : null, bottomInset: dockSpace)
          : const TextModeView();
      final readerWithDock = Stack(children: [
        Positioned.fill(child: reader),
        if (hFold == null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10 + mq.padding.bottom,
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980), child: Dock(compact: compactBar)),
            ),
          ),
      ]);
      void closeInspector() {
        model.showInspector = false;
        model.update(() {});
      }

      if (hFold != null) {
        // Tabletop posture: the page above the fold, controls and the inspector below it.
        final top = hFold.top - mq.padding.top - kToolbarHeight;
        body = Column(children: [
          SizedBox(height: top.clamp(100, mq.size.height), child: reader),
          SizedBox(height: hFold.height),
          Expanded(
            child: Column(children: [
              Padding(padding: const EdgeInsets.all(8), child: Dock(compact: compactBar)),
              if (model.showInspector) Expanded(child: AyahInspector(onClose: closeInspector)),
            ]),
          ),
        ]);
      } else if (vFold != null && model.showInspector) {
        // Unfolded: the page on one half of the hinge, its translation or tafsir on the other.
        body = Row(children: [
          SizedBox(width: vFold.left, child: readerWithDock),
          SizedBox(width: vFold.width),
          Expanded(child: Material(child: SafeArea(left: false, child: AyahInspector(onClose: closeInspector)))),
        ]);
      } else if (medium) {
        body = Row(children: [
          if (wide) SizedBox(width: 300, child: Material(child: Sidebar())),
          if (wide) const VerticalDivider(width: 1),
          Expanded(child: readerWithDock),
          if (model.showInspector) ...[
            const VerticalDivider(width: 1),
            SizedBox(width: wide ? 380 : 340, child: Material(child: AyahInspector(onClose: closeInspector))),
          ],
        ]);
      } else {
        // Phones: the inspector slides up over the lower part of the page.
        body = Stack(children: [
          Positioned.fill(child: readerWithDock),
          if (model.showInspector)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: mq.size.height * 0.55,
              child: Material(
                elevation: 12,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(top: false, child: AyahInspector(onClose: closeInspector)),
              ),
            ),
        ]);
      }
    }

    final update = model.updates.available;
    return Scaffold(
      key: _scaffold,
      appBar: _appBar(context, compact: compactBar, sidebarInDrawer: !wide),
      drawer: wide ? null : Drawer(width: 320, child: SafeArea(child: Sidebar(onNavigate: () => _scaffold.currentState?.closeDrawer()))),
      body: Column(children: [
        if (update != null)
          MaterialBanner(
            leading: const Icon(Icons.system_update, color: AppColors.accent),
            content: Text(tr('Quran Reader HD %@ is available. You have %@.', [update.version, model.updates.currentVersion])),
            actions: [
              TextButton(onPressed: model.updates.skip, child: Text(tr('Skip This Version'))),
              TextButton(onPressed: model.updates.dismiss, child: Text(tr('Later'))),
              FilledButton(
                onPressed: () {
                  launchUrl(update.download ?? update.page, mode: LaunchMode.externalApplication);
                  model.updates.dismiss();
                },
                child: Text(tr('Download')),
              ),
            ],
          ),
        Expanded(child: body),
      ]),
    );
  }

  Widget _status(BuildContext context) {
    if (model.status == LoadStatus.failed) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.wifi_off, size: 40),
          const SizedBox(height: 8),
          Text(tr("Couldn't load the mushaf"), style: Theme.of(context).textTheme.titleMedium),
          Padding(padding: const EdgeInsets.all(8), child: Text(model.statusMessage, textAlign: TextAlign.center)),
          FilledButton(onPressed: model.bootstrap, child: Text(tr('Try Again'))),
        ]),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(tr(model.statusMessage)),
      ]),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, {required bool compact, required bool sidebarInDrawer}) {
    final ready = model.status == LoadStatus.ready;
    final page = model.page;
    final marked = model.library.isBookmarked(page);
    return AppBar(
      titleSpacing: sidebarInDrawer ? 0 : 16,
      title: ready ? _title(context, page, compact) : Text(tr('Mushaf')),
      actions: compact ? _compactActions(context, ready: ready, marked: marked) : [
        if (ready) ...[
          // Book order whatever the UI language: "next" sits on the left.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                onPressed: page < Quran.pageCount ? () => model.turn(forward: true) : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: tr('Next page'),
              ),
              if (!compact) _PageField(page: page),
              IconButton(
                onPressed: page > 1 ? () => model.turn(forward: false) : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: tr('Previous page'),
              ),
            ]),
          ),
          IconButton(
            onPressed: () => model.update(
                () => model.mode = model.mode == ReadingMode.mushaf ? ReadingMode.text : ReadingMode.mushaf),
            icon: Icon(model.mode == ReadingMode.mushaf ? Icons.notes : Icons.menu_book),
            tooltip: tr(model.mode == ReadingMode.mushaf ? 'Translation & Tafsir' : 'Mushaf'),
          ),
          IconButton(
            onPressed: () => model.library.toggleBookmark(page, title: model.pageTitle(page)),
            icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
            tooltip: tr('Bookmark this page'),
          ),
          IconButton(
            onPressed: () {
              model.showInspector = !model.showInspector;
              model.update(() {});
            },
            icon: Icon(model.showInspector ? Icons.vertical_split : Icons.vertical_split_outlined),
            tooltip: tr('Translation, tafsir and notes'),
          ),
          if (model.mode == ReadingMode.mushaf)
            IconButton(
              onPressed: () => _enterFullScreen(context),
              icon: const Icon(Icons.fullscreen),
              tooltip: tr('Full Screen'),
            ),
        ],
        IconButton(
          onPressed: () => showSettings(context),
          icon: Badge(isLabelVisible: model.updates.available != null, child: const Icon(Icons.settings_outlined)),
          tooltip: tr('Settings'),
        ),
      ],
    );
  }

  /// "2. Al-Baqara · Page 17" over "Juz' 1 · ¼ Hizb 2"; on phones the surah alone over "Page 17 · Juz' 1 · …".
  Widget _title(BuildContext context, int page, bool compact) {
    final first = model.firstAyah(page);
    final position = "${tr("Juz' %d", [model.juzFor(page)])} · ${AppModel.quarterLabel(model.quarterIndex(page))}";
    final (title, subtitle) = compact
        ? (first == null ? tr('Page %d', [page]) : model.surahName(first.sura), '${tr('Page %d', [page])} · $position')
        : (model.pageTitle(page), position);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: compact ? const TextStyle(fontSize: 18) : null),
      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  /// Phones: the title needs the room, so only bookmark and the inspector stay in the bar (pages turn by
  /// swiping); the reading mode and settings move into a menu.
  List<Widget> _compactActions(BuildContext context, {required bool ready, required bool marked}) {
    final page = model.page;
    return [
      if (ready) ...[
        IconButton(
          onPressed: () => model.library.toggleBookmark(page, title: model.pageTitle(page)),
          icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
          tooltip: tr('Bookmark this page'),
        ),
        IconButton(
          onPressed: () {
            model.showInspector = !model.showInspector;
            model.update(() {});
          },
          icon: Icon(model.showInspector ? Icons.vertical_split : Icons.vertical_split_outlined),
          tooltip: tr('Translation, tafsir and notes'),
        ),
      ],
      PopupMenuButton<VoidCallback>(
        icon: Badge(isLabelVisible: model.updates.available != null, child: const Icon(Icons.more_vert)),
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          if (ready)
            PopupMenuItem(
              value: () => model.update(
                  () => model.mode = model.mode == ReadingMode.mushaf ? ReadingMode.text : ReadingMode.mushaf),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(model.mode == ReadingMode.mushaf ? Icons.notes : Icons.menu_book),
                title: Text(tr(model.mode == ReadingMode.mushaf ? 'Translation & Tafsir' : 'Mushaf')),
              ),
            ),
          if (ready && model.mode == ReadingMode.mushaf)
            PopupMenuItem(
              value: () => _enterFullScreen(context),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fullscreen),
                title: Text(tr('Full Screen')),
              ),
            ),
          PopupMenuItem(
            value: () => showSettings(context),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Badge(
                  isLabelVisible: model.updates.available != null, child: const Icon(Icons.settings_outlined)),
              title: Text(tr('Settings')),
            ),
          ),
        ],
      ),
    ];
  }
}

class _PageField extends StatefulWidget {
  final int page;
  const _PageField({required this.page});

  @override
  State<_PageField> createState() => _PageFieldState();
}

class _PageFieldState extends State<_PageField> {
  late final _controller = TextEditingController(text: '${widget.page}');

  @override
  void didUpdateWidget(_PageField old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page) _controller.text = '${widget.page}';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 56,
        child: Tooltip(
          message: tr('Go to page (1–604)'),
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            onSubmitted: (v) {
              final p = int.tryParse(v);
              if (p != null) {
                model.goTo(p);
              } else {
                _controller.text = '${model.page}';
              }
            },
          ),
        ),
      );
}
