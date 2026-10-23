import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import '../core/quran.dart';
import '../core/storage.dart';
import '../data/text_library.dart';
import 'ayah_menu.dart';
import 'common.dart';

enum CardStyle { emerald('Emerald'), parchment('Parchment');
  const CardStyle(this.label); final String label; }

/// Logical width of the card; it is exported at 1080 px.
const _cardWidth = 540.0;

Future<void> showShareCard(BuildContext context, AyahKey key) =>
    showDialog(context: context, builder: (_) => _ShareCardDialog(ayah: key));

class _ShareCardDialog extends StatefulWidget {
  final AyahKey ayah;
  const _ShareCardDialog({required this.ayah});

  @override
  State<_ShareCardDialog> createState() => _ShareCardDialogState();
}

class _ShareCardDialogState extends State<_ShareCardDialog> {
  final _boundary = GlobalKey();
  bool _translation = model.prefs.getBool('cardTranslation') ?? true;
  CardStyle _style = CardStyle.values.asNameMap()[model.prefs.getString('cardStyle')] ?? CardStyle.emerald;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    model.text.ensure(model.translationID);
  }

  Future<File> _render() async {
    final boundary = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1080 / _cardWidth);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final name = 'Quran ${widget.ayah.sura}-${widget.ayah.ayah}.png';
    final file = File(p.join(Paths.cards.path, name));
    await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
    return file;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() => _run(() async {
        final file = await _render();
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: model.citation(widget.ayah),
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ));
      });

  Future<void> _save() => _run(() async {
        final file = await _render();
        final location = await getSaveLocation(
          suggestedName: p.basename(file.path),
          acceptedTypeGroups: const [XTypeGroup(label: 'PNG', extensions: ['png'])],
        );
        if (location == null) return;
        await file.copy(location.path);
        if (mounted) toast(context, tr('Saved'));
      });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ModelBuilder(
          also: [model.text],
          builder: (context) => Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(children: [
                Expanded(child: Text(tr('Share as Image'), style: Theme.of(context).textTheme.titleLarge)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _boundary,
                    child: AyahCard(ayah: widget.ayah, translation: _translation, style: _style),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SegmentedButton<CardStyle>(
                  segments: [for (final s in CardStyle.values) ButtonSegment(value: s, label: Text(tr(s.label)))],
                  selected: {_style},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() => _style = s.first);
                    model.prefs.setString('cardStyle', _style.name);
                  },
                ),
                FilterChip(
                  label: Text(tr('Translation')),
                  selected: _translation,
                  onSelected: (v) {
                    setState(() => _translation = v);
                    model.prefs.setBool('cardTranslation', v);
                  },
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                TextButton.icon(
                  onPressed: () => copyText(context, model.shareText(widget.ayah)),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(tr('Copy Text')),
                ),
                if (isDesktop)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: Text(tr('Save Image…')),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.share, size: 18),
                  label: Text(tr('Share…')),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The shareable card: the ayah with full tashkeel, its surah, an optional translation and the app's name.
class AyahCard extends StatelessWidget {
  final AyahKey ayah;
  final bool translation;
  final CardStyle style;
  const AyahCard({super.key, required this.ayah, required this.translation, required this.style});

  @override
  Widget build(BuildContext context) {
    final emerald = style == CardStyle.emerald;
    final ink = emerald ? Colors.white : const Color(0xFF2A2116);
    final accent = emerald ? AppColors.gold : AppColors.frameGreen;
    final rule = emerald ? AppColors.gold : AppColors.frameGold;
    final arabic = model.text.text(Edition.arabic.id, ayah) ?? '';
    final translationText = translation ? model.text.text(model.translationID, ayah) : null;
    final edition = Edition.named(model.translationID);
    final surah = model.surah(ayah.sura);
    final size = switch (arabic.length) { < 120 => 31.0, < 300 => 27.0, < 600 => 23.0, _ => 19.0 };
    final english = Localizer.shared.language == AppLanguage.arabic
        ? '${surah?.name ?? ''} · ${arabicDigits(ayah.ayah)}'
        : '${surah?.englishName ?? 'Surah ${ayah.sura}'} · ${ayah.sura}:${ayah.ayah}';

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: _cardWidth,
        decoration: BoxDecoration(
          gradient: emerald
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.emerald, AppColors.emeraldDeep])
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFBF3DE), AppColors.parchment]),
        ),
        child: CustomPaint(
          painter: StarPatternPainter(rule.withValues(alpha: emerald ? 0.09 : 0.12)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: rule.withValues(alpha: 0.6), width: 1.2),
              ),
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: rule.withValues(alpha: 0.28)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(surah?.name ?? 'سورة ${arabicDigits(ayah.sura)}',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontFamily: quranFont, fontSize: 24, color: accent, height: 1.6)),
                  const SizedBox(height: 6),
                  Ornament(color: rule),
                  const SizedBox(height: 14),
                  Text(
                    '$arabic ﴿${arabicDigits(ayah.ayah)}﴾',
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: quranFont, fontSize: size, color: ink, height: 2.05),
                  ),
                  if (translationText != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      translationText,
                      textDirection: edition.isRTL ? TextDirection.rtl : TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        // Amiri for Latin too, so the card looks the same on every platform.
                        fontFamily: arabicFont,
                        fontSize: translationText.length > 500 ? 13.5 : 15.5,
                        height: 1.5,
                        fontStyle: edition.isRTL ? null : FontStyle.italic,
                        color: ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Ornament(color: rule),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: Text(english,
                          style: TextStyle(
                              fontFamily: arabicFont,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              letterSpacing: 0.4)),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset('assets/AppIcon.png', width: 22, height: 22),
                    ),
                    const SizedBox(width: 7),
                    Text('Quran Reader HD',
                        style: TextStyle(
                            fontFamily: arabicFont,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: ink.withValues(alpha: 0.8),
                            letterSpacing: 0.6)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A thin gold rule with a diamond, between sections.
class Ornament extends StatelessWidget {
  final Color color;
  const Ornament({super.key, required this.color});

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
            width: 110,
            height: 1,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withValues(alpha: 0), color]))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Transform.rotate(angle: math.pi / 4, child: Container(width: 7, height: 7, color: color)),
        ),
        Container(
            width: 110,
            height: 1,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [color, color.withValues(alpha: 0)]))),
      ]);
}

/// Tiled eight-pointed stars (two overlapping squares), a classic Islamic geometric motif.
class StarPatternPainter extends CustomPainter {
  final Color color;
  StarPatternPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 64.0, r = 22.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    var row = 0;
    for (var y = 0.0; y < size.height + tile; y += tile / 2, row++) {
      for (var x = row.isEven ? 0.0 : tile / 2; x < size.width + tile; x += tile) {
        for (final rotation in [0.0, math.pi / 4]) {
          final path = Path();
          for (var i = 0; i < 4; i++) {
            final a = rotation + i * math.pi / 2 + math.pi / 4;
            final pt = Offset(x + r * math.cos(a), y + r * math.sin(a));
            i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(path..close(), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(StarPatternPainter old) => old.color != color;
}
