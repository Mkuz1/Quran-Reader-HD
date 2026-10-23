import 'dart:io';

import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/l10n.dart';

class AppColors {
  static const paperLight = Color(0xFFFCF7E8);
  static const paperDark = Color(0xFF1C1C1A);
  static const parchment = Color(0xFFF5E8C9);
  static const parchmentDesk = Color(0xFFCCB894);
  static const deskDark = Color(0xFF403629);
  static const night = Color(0xFF141417);
  static const frameGold = Color(0xFFB08A3D);
  static const frameGreen = Color(0xFF3D6B4A);
  static const allahRed = Color(0xFFC7211A);

  /// App accent: the emerald of the icon and the opening page.
  static const accent = Color(0xFF0D785C);
  static const gold = Color(0xFFDBB86B);
  static const emerald = Color(0xFF083326);
  static const emeraldDeep = Color(0xFF031C14);
}

const quranFont = 'Amiri Quran';
const arabicFont = 'Amiri';

bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Right-aligned, right-to-left Quran or Arabic text.
class ArabicText extends StatelessWidget {
  final String? text;
  final double size;
  final Color? color;
  final bool quran;
  final int? maxLines;
  const ArabicText(this.text, {super.key, this.size = 22, this.color, this.quran = true, this.maxLines});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Text(
          text ?? '…',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: TextStyle(fontFamily: quran ? quranFont : arabicFont, fontSize: size, height: 1.9, color: color),
        ),
      );
}

/// Rebuilds when the model, the language or any of the given notifiers change.
class ModelBuilder extends StatelessWidget {
  final List<Listenable> also;
  final WidgetBuilder builder;
  const ModelBuilder({super.key, this.also = const [], required this.builder});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([model, Localizer.shared, ...also]),
        builder: (context, _) => builder(context),
      );
}

void toast(BuildContext context, String message) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
