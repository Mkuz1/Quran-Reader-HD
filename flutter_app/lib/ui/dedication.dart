import 'package:flutter/material.dart';

import '../app_model.dart';
import '../core/l10n.dart';
import 'common.dart';
import 'share_card.dart';

/// Opening page: this app is a sadaqa jariyah (ongoing charity) on behalf of Mohamad Koussa and Dima Ghannoum.
class DedicationView extends StatelessWidget {
  final VoidCallback onContinue;
  const DedicationView({super.key, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Localizer.shared,
      builder: (context, _) {
        final language = Localizer.shared.language;
        final dedication = switch (language) {
          AppLanguage.english => 'On behalf of Mohamad Koussa and Dima Ghannoum\nand their families',
          AppLanguage.french => 'Au nom de Mohamad Koussa et Dima Ghannoum\net de leurs familles',
          AppLanguage.arabic => 'عن محمد كوسا وديما غنوم\nوعائلاتهم',
        };
        final dua = switch (language) {
          AppLanguage.english => 'O Allah, place it in the scale of their good deeds.',
          AppLanguage.french => 'Ô Allah, place-la dans la balance de leurs bonnes actions.',
          AppLanguage.arabic => null,
        };
        final hadith = switch (language) {
          AppLanguage.english => '“When a person dies, their deeds end except for three: an ongoing charity…” — Muslim',
          AppLanguage.french => '« Quand l\'homme meurt, ses œuvres cessent sauf trois : une aumône continue… » — Muslim',
          AppLanguage.arabic => null,
        };
        const gold = AppColors.gold;
        return Material(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.emerald, AppColors.emeraldDeep]),
            ),
            child: CustomPaint(
              painter: StarPatternPainter(gold.withValues(alpha: 0.10)),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 640),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                      decoration: BoxDecoration(
                        color: AppColors.emerald.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: gold.withValues(alpha: 0.55), width: 1.2),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(fontFamily: quranFont, fontSize: 26, color: gold.withValues(alpha: 0.9))),
                        const SizedBox(height: 16),
                        const Ornament(color: gold),
                        const SizedBox(height: 12),
                        ShaderMask(
                          shaderCallback: (r) =>
                              const LinearGradient(colors: [gold, Color(0xFFFAE09E), gold]).createShader(r),
                          child: const FittedBox(
                            child: Text('صدقة جارية',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                    fontFamily: arabicFont, fontWeight: FontWeight.bold, fontSize: 72, color: Colors.white)),
                          ),
                        ),
                        if (language != AppLanguage.arabic)
                          Text(language == AppLanguage.french ? 'SADAQA JARIYA' : 'SADAQA JARIYAH',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 6,
                                  color: gold.withValues(alpha: 0.8))),
                        const SizedBox(height: 18),
                        Text(dedication,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: language == AppLanguage.arabic ? arabicFont : null,
                                fontSize: language == AppLanguage.arabic ? 28 : 22,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                                color: Colors.white)),
                        const SizedBox(height: 16),
                        const Ornament(color: gold),
                        const SizedBox(height: 14),
                        const Text('اللَّهُمَّ اجْعَلْهُ فِي مِيزَانِ حَسَنَاتِهِمْ',
                            textDirection: TextDirection.rtl,
                            style: TextStyle(fontFamily: arabicFont, fontSize: 21, color: gold)),
                        if (dua != null)
                          Text(dua,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white.withValues(alpha: 0.75))),
                        const SizedBox(height: 14),
                        Text('إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ: صَدَقَةٍ جَارِيَةٍ… — رواه مسلم',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(fontFamily: arabicFont, fontSize: 15, color: Colors.white.withValues(alpha: 0.6))),
                        if (hadith != null)
                          Text(hadith,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                        const SizedBox(height: 20),
                        Theme(
                          data: ThemeData(colorSchemeSeed: gold, brightness: Brightness.dark),
                          child: SegmentedButton<AppLanguage>(
                            segments: [
                              for (final l in AppLanguage.values) ButtonSegment(value: l, label: Text(l.nativeName))
                            ],
                            selected: {language},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) => model.setLanguage(s.first),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: gold,
                            foregroundColor: AppColors.emeraldDeep,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          onPressed: onContinue,
                          child: Text(tr('Begin Reading')),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
