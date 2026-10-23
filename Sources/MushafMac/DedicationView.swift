import SwiftUI

/// Opening page: this app is a sadaqa jariyah (ongoing charity) on behalf of Mohamad Koussa and Dima Ghannoum.
struct DedicationView: View {
    @Environment(AppModel.self) private var model
    let onContinue: () -> Void
    @State private var appeared = false

    private static let gold = Color(red: 0.86, green: 0.72, blue: 0.42)
    private static let emerald = Color(red: 0.03, green: 0.20, blue: 0.15)
    private static let emeraldDeep = Color(red: 0.01, green: 0.11, blue: 0.08)

    private var language: AppLanguage { Localizer.shared.language }

    private var dedication: String {
        switch language {
        case .english: "On behalf of Mohamad Koussa and Dima Ghannoum\nand their families"
        case .french: "Au nom de Mohamad Koussa et Dima Ghannoum\net de leurs familles"
        case .arabic: "عن محمد كوسا وديما غنوم\nوعائلاتهم"
        }
    }

    private var duaTranslation: String? {
        switch language {
        case .english: "O Allah, place it in the scale of their good deeds."
        case .french: "Ô Allah, place-la dans la balance de leurs bonnes actions."
        case .arabic: nil
        }
    }

    private var hadithTranslation: String? {
        switch language {
        case .english: "“When a person dies, their deeds end except for three: an ongoing charity…” — Muslim"
        case .french: "« Quand l'homme meurt, ses œuvres cessent sauf trois : une aumône continue… » — Muslim"
        case .arabic: nil
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Self.emerald, Self.emeraldDeep], startPoint: .top, endPoint: .bottom)
            StarPattern().stroke(Self.gold.opacity(0.10), lineWidth: 1)
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 200, endRadius: 900)

            VStack(spacing: 22) {
                Text("بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")
                    .font(.custom("Diwan Thuluth", size: 30))
                    .foregroundStyle(Self.gold.opacity(0.9))

                ornament

                VStack(spacing: 4) {
                    Text("صدقة جارية")
                        .font(.custom("Diwan Thuluth", size: 84))
                        .foregroundStyle(LinearGradient(colors: [Self.gold, Color(red: 0.98, green: 0.88, blue: 0.62), Self.gold],
                                                        startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                    if language != .arabic {
                        Text(language == .french ? "SADAQA JARIYA" : "SADAQA JARIYAH")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .tracking(6)
                            .foregroundStyle(Self.gold.opacity(0.8))
                    }
                }

                Text(dedication)
                    .font(language == .arabic ? .custom("Geeza Pro", size: 30).bold() : .system(size: 26, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .foregroundStyle(.white)

                ornament

                VStack(spacing: 8) {
                    Text("اللَّهُمَّ اجْعَلْهُ فِي مِيزَانِ حَسَنَاتِهِمْ")
                        .font(.custom("Geeza Pro", size: 22))
                        .foregroundStyle(Self.gold)
                    if let duaTranslation {
                        Text(duaTranslation).font(.system(size: 15, design: .serif)).italic().foregroundStyle(.white.opacity(0.75))
                    }
                }

                VStack(spacing: 6) {
                    Text("إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَمَلُهُ إِلَّا مِنْ ثَلَاثٍ: صَدَقَةٍ جَارِيَةٍ… — رواه مسلم")
                        .font(.custom("Geeza Pro", size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                    if let hadithTranslation {
                        Text(hadithTranslation).font(.system(size: 12, design: .serif)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.top, 4)

                Picker("", selection: Binding(get: { language }, set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 10)
                .environment(\.colorScheme, .dark)

                Button(action: onContinue) {
                    Text(tr("Begin Reading"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Self.emeraldDeep)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .tint(Self.gold)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 44)
            // Liquid Glass card tinted emerald, with a fine double gold rule.
            .glassEffect(.regular.tint(Self.emerald.opacity(0.35)), in: RoundedRectangle(cornerRadius: 32))
            .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(Self.gold.opacity(0.55), lineWidth: 1.2))
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(Self.gold.opacity(0.25), lineWidth: 1).padding(7))
            .padding(30)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.97)
        }
        .ignoresSafeArea()
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { appeared = true } }
    }

    /// A thin gold rule with a diamond, between sections.
    private var ornament: some View {
        HStack(spacing: 10) {
            Rectangle().fill(LinearGradient(colors: [.clear, Self.gold], startPoint: .leading, endPoint: .trailing)).frame(width: 120, height: 1)
            Image(systemName: "seal.fill").font(.system(size: 9)).foregroundStyle(Self.gold)
            Rectangle().fill(LinearGradient(colors: [Self.gold, .clear], startPoint: .leading, endPoint: .trailing)).frame(width: 120, height: 1)
        }
    }
}

/// Tiled eight-pointed stars (two overlapping squares), a classic Islamic geometric motif.
private struct StarPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tile: CGFloat = 64
        let r: CGFloat = 22
        var y = rect.minY
        var row = 0
        while y < rect.maxY + tile {
            var x = rect.minX + (row.isMultiple(of: 2) ? 0 : tile / 2)
            while x < rect.maxX + tile {
                for rotation in [0.0, Double.pi / 4] {
                    var square = Path()
                    for i in 0..<4 {
                        let a = rotation + Double(i) * .pi / 2 + .pi / 4
                        let pt = CGPoint(x: x + r * cos(a), y: y + r * sin(a))
                        if i == 0 { square.move(to: pt) } else { square.addLine(to: pt) }
                    }
                    square.closeSubpath()
                    p.addPath(square)
                }
                x += tile
            }
            y += tile / 2
            row += 1
        }
        return p
    }
}
