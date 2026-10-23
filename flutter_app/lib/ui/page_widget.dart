import 'dart:io';

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../data/glyph_db.dart';
import '../data/page_store.dart';
import '../data/page_words.dart';
import 'ayah_menu.dart';
import 'common.dart';

final Map<int, Future<File>> _pageFutures = {};

@visibleForTesting
void clearPageCache() => _pageFutures.clear();

/// One download per page; a failed one is forgotten so Retry fetches again.
Future<File> _loadPage(int page) {
  final existing = _pageFutures[page];
  if (existing != null) return existing;
  final f = _pageFutures[page] = pageFile(page);
  f.then((_) {}, onError: (_) {
    _pageFutures.remove(page);
  });
  return f;
}

/// Night is forced; Classic follows the system appearance.
bool invertsInk(BuildContext context) =>
    model.theme == PageTheme.night ||
    (model.theme == PageTheme.classic && Theme.of(context).brightness == Brightness.dark);

/// One mushaf page: the image, ayah highlights, the name of Allah in red (Coloured theme), note tabs,
/// the bookmark tassel and the page number.
class MushafPage extends StatefulWidget {
  final int page;

  /// Side of the page facing away from the spine: where the tassel hangs and note tabs sit.
  final bool outerEdgeIsRight;
  const MushafPage({super.key, required this.page, required this.outerEdgeIsRight});

  @override
  State<MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<MushafPage> {
  AyahKey? _hovered;
  Offset? _doubleTapAt;
  late Future<File> _file = _loadPage(widget.page);

  int get page => widget.page;

  @override
  void didUpdateWidget(MushafPage old) {
    super.didUpdateWidget(old);
    if (old.page != page) _file = _loadPage(page);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${snap.error}', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              FilledButton.tonal(
                  onPressed: () => setState(() => _file = _loadPage(page)), child: Text(tr('Retry'))),
            ]),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return ModelBuilder(
          also: [model.library, model.audio, model.words],
          builder: (context) => _page(context, snap.data!),
        );
      },
    );
  }

  Widget _page(BuildContext context, File file) {
    final coloured = model.theme == PageTheme.coloured;
    if (coloured) model.words.ensure(page, _glyphCounts());
    final dark = invertsInk(context);
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Decoded at the size it is shown (in steps, so small resizes reuse it) and drawn without mipmaps:
    // on Android's GPU renderer, mipmapped sampling of these palette PNGs (transparent paper, black ink)
    // averaged the page into a flat grey.
    Widget image(Color? tint, double width) => Image.file(file,
        cacheWidth: ((width * pixelRatio / 128).ceil() * 128).clamp(128, Quran.pageWidth.toInt()),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        color: tint,
        colorBlendMode: tint == null ? null : BlendMode.srcIn);

    final content = AspectRatio(
      aspectRatio: Quran.pageWidth / Quran.pageHeight,
      child: LayoutBuilder(builder: (context, c) {
        final scale = c.maxWidth / Quran.pageWidth;
        final refs = coloured ? model.words.allahWords[page] : null;
        return Stack(fit: StackFit.expand, children: [
          image(dark ? Colors.white.withValues(alpha: 0.9) : null, c.maxWidth),
          if (refs != null && refs.isNotEmpty)
            ClipPath(clipper: _RectsClipper(_allahRects(refs), scale), child: image(AppColors.allahRed, c.maxWidth)),
          CustomPaint(painter: _HighlightPainter(page, scale, _hovered)),
          _gestures(context, scale),
          ..._noteTabs(scale, c.maxWidth),
        ]);
      }),
    );

    final framed = coloured
        ? Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.parchment,
              border: Border.all(color: AppColors.frameGold, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
            ),
            foregroundDecoration: BoxDecoration(border: Border.all(color: AppColors.frameGreen, width: 1)),
            child: content,
          )
        : content;

    // Sized to the page itself, so a spread can set its two pages against the spine.
    return Stack(clipBehavior: Clip.none, children: [
      framed,
      Positioned(
        top: 0,
        left: widget.outerEdgeIsRight ? null : 18,
        right: widget.outerEdgeIsRight ? 18 : null,
        child: _Tassel(page: page),
      ),
    ]);
  }

  Map<AyahKey, int> _glyphCounts() {
    final db = model.db;
    if (db == null) return const {};
    return {for (final k in db.ayahs(page)) k: db.glyphTotal(k)};
  }

  List<Rect> _allahRects(Set<WordRef> refs) => [
        for (final g in model.db?.glyphs(page) ?? const <Glyph>[])
          if (refs.contains(WordRef(g.key, g.position))) g.rect.inflate(2),
      ];

  AyahKey? _hit(Offset local, double scale) => model.db?.ayahAt(local / scale, page);

  Widget _gestures(BuildContext context, double scale) {
    return MouseRegion(
      onHover: (e) {
        final k = _hit(e.localPosition, scale);
        if (k != _hovered) setState(() => _hovered = k);
      },
      onExit: (_) => setState(() => _hovered = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          // Full screen: a tap shows or hides the controls; long-press still opens the ayah menu.
          if (model.fullScreen) return model.showControls(!model.controlsVisible);
          final key = _hit(d.localPosition, scale);
          model.select(key == model.selected ? null : key);
        },
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onDoubleTap: () {
          final at = _doubleTapAt;
          final key = at == null ? null : _hit(at, scale);
          if (key == null) return;
          model.select(key);
          model.audio.play(key);
        },
        onLongPressStart: (d) => _menu(context, d.localPosition, d.globalPosition, scale),
        onSecondaryTapUp: (d) => _menu(context, d.localPosition, d.globalPosition, scale),
      ),
    );
  }

  void _menu(BuildContext context, Offset local, Offset global, double scale) {
    // The ayah under this press, never a previously hovered or selected one.
    final key = _hit(local, scale);
    if (key != null) showAyahMenu(context, key, global);
  }

  /// Sticky-note tabs at the outer edge beside each annotated ayah; notes on one line share a tab.
  List<Widget> _noteTabs(double scale, double width) {
    final db = model.db;
    if (db == null) return const [];
    final noted = db.ayahs(page).where(model.library.notes.containsKey).toList();
    final byLine = <int, List<AyahKey>>{};
    for (final k in noted) {
      final rects = db.highlightRects(k, page);
      if (rects.isEmpty) continue;
      (byLine[rects.first.center.dy ~/ 40] ??= []).add(k);
    }
    return [
      for (final keys in byLine.values)
        Positioned(
          top: db.highlightRects(keys.first, page).first.center.dy * scale - 10,
          left: widget.outerEdgeIsRight ? null : 0,
          right: widget.outerEdgeIsRight ? 0 : null,
          child: _NoteTab(keys: keys..sort()),
        ),
    ];
  }
}

class _RectsClipper extends CustomClipper<Path> {
  final List<Rect> rects;
  final double scale;
  _RectsClipper(this.rects, this.scale);

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final r in rects) {
      path.addRect(Rect.fromLTRB(r.left * scale, r.top * scale, r.right * scale, r.bottom * scale));
    }
    return path;
  }

  @override
  bool shouldReclip(_RectsClipper old) => old.rects.length != rects.length || old.scale != scale;
}

class _HighlightPainter extends CustomPainter {
  final int page;
  final double scale;
  final AyahKey? hovered;
  _HighlightPainter(this.page, this.scale, this.hovered);

  @override
  void paint(Canvas canvas, Size size) {
    final db = model.db;
    if (db == null) return;
    void fill(AyahKey? key, Color color) {
      if (key == null) return;
      final paint = Paint()..color = color;
      for (final r in db.highlightRects(key, page)) {
        final v = Rect.fromLTRB(r.left * scale - 2, r.top * scale - 1, r.right * scale + 2, r.bottom * scale + 1);
        canvas.drawRRect(RRect.fromRectAndRadius(v, const Radius.circular(4)), paint);
      }
    }

    for (final k in db.ayahs(page)) {
      if (model.library.notes.containsKey(k)) fill(k, Colors.yellow.withValues(alpha: 0.16));
    }
    if (hovered != model.selected) fill(hovered, Colors.grey.withValues(alpha: 0.12));
    fill(model.selected, AppColors.accent.withValues(alpha: 0.22));
    fill(model.audio.current, Colors.green.withValues(alpha: 0.28));
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => true;
}

class _NoteTab extends StatelessWidget {
  final List<AyahKey> keys;
  const _NoteTab({required this.keys});

  @override
  Widget build(BuildContext context) {
    final icon = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.yellow.shade600,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        const Center(child: Icon(Icons.sticky_note_2_outlined, size: 14, color: Colors.black87)),
        if (keys.length > 1)
          Positioned(
            right: -6,
            top: -6,
            child: CircleAvatar(
                radius: 7,
                backgroundColor: Colors.red,
                child: Text('${keys.length}', style: const TextStyle(fontSize: 8, color: Colors.white))),
          ),
      ]),
    );
    if (keys.length == 1) {
      return Tooltip(
        message: model.library.notes[keys.first]?.text ?? '',
        child: GestureDetector(onTap: () => model.showText(InspectorTab.note, keys.first), child: icon),
      );
    }
    return PopupMenuButton<AyahKey>(
      tooltip: '',
      padding: EdgeInsets.zero,
      onSelected: (k) => model.showText(InspectorTab.note, k),
      itemBuilder: (_) => [
        for (final k in keys)
          PopupMenuItem(
            value: k,
            child: Text('$k — ${(model.library.notes[k]?.text ?? '').characters.take(40)}'),
          ),
      ],
      child: icon,
    );
  }
}

/// Silk bookmark ribbon with a notched tail; tap to bookmark the page.
class _Tassel extends StatelessWidget {
  final int page;
  const _Tassel({required this.page});

  @override
  Widget build(BuildContext context) {
    final marked = model.library.isBookmarked(page);
    return Tooltip(
      message: marked ? tr('Remove bookmark') : tr('Tap the tassel to bookmark this page'),
      child: GestureDetector(
        onTap: () => model.library.toggleBookmark(page, title: model.pageTitle(page)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          width: 18,
          height: marked ? 64 : 40,
          child: CustomPaint(painter: _RibbonPainter(marked)),
        ),
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final bool marked;
  _RibbonPainter(this.marked);

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height - s.width * 0.6)
      ..lineTo(0, s.height)
      ..close();
    if (marked) {
      canvas.drawShadow(path, Colors.black, 2, false);
      canvas.drawPath(
          path,
          Paint()
            ..shader = const LinearGradient(colors: [Color(0xFFB31A1F), Color(0xFF850D14)])
                .createShader(Offset.zero & s));
    } else {
      canvas.drawPath(path, Paint()..color = Colors.grey.withValues(alpha: 0.18));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.grey.withValues(alpha: 0.5));
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.marked != marked;
}
