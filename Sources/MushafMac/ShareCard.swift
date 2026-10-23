import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CardStyle: String, CaseIterable, Identifiable {
    case emerald = "Emerald"
    case parchment = "Parchment"
    var id: String { rawValue }
}

/// Western digits to Arabic-Indic, for ayah numbers set in Arabic text.
func arabicDigits(_ n: Int) -> String {
    String(String(n).unicodeScalars.map { Character(UnicodeScalar(0x0660 + $0.value - 0x30)!) })
}

/// The shareable card: the ayah with full tashkeel, its surah, an optional translation and the app's name.
/// Kept in step with AyahCard in the Windows/Android app (flutter_app/lib/ui/share_card.dart).
struct AyahCard: View {
    let key: AyahKey
    let arabic: String
    let surahName: String   // in Arabic
    let footer: String
    let translation: String?
    let translationIsRTL: Bool
    let style: CardStyle

    static let width: CGFloat = 540
    private static let gold = Color(red: 0.86, green: 0.72, blue: 0.42)
    private static let emerald = Color(red: 0.03, green: 0.20, blue: 0.15)
    private static let emeraldDeep = Color(red: 0.01, green: 0.11, blue: 0.08)

    /// Amiri Quran ships in the app bundle (Contents/Resources/Fonts); Geeza Pro when run unbundled.
    static func quranFont(_ size: CGFloat) -> Font {
        NSFont(name: "AmiriQuran-Regular", size: size) != nil ? .custom("Amiri Quran", size: size) : .custom("Geeza Pro", size: size)
    }

    private var isEmerald: Bool { style == .emerald }
    private var ink: Color { isEmerald ? .white : Color(red: 0.16, green: 0.13, blue: 0.09) }
    private var accent: Color { isEmerald ? Self.gold : Color.frameGreen }
    private var rule: Color { isEmerald ? Self.gold : Color.frameGold }

    private var arabicSize: CGFloat {
        switch arabic.count {
        case ..<120: 31
        case ..<300: 27
        case ..<600: 23
        default: 19
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(surahName)
                .font(Self.quranFont(24))
                .foregroundStyle(accent)
            ornament.padding(.top, 6)
            Text("\(arabic) ﴿\(arabicDigits(key.ayah))﴾")
                .font(Self.quranFont(arabicSize))
                .lineSpacing(arabicSize * 0.75)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            if let translation {
                Text(translation)
                    .font(translationIsRTL ? Font.custom("Geeza Pro", size: 15)
                                          : Font.system(size: translation.count > 500 ? 13 : 15, design: .serif).italic())
                    .lineSpacing(4)
                    .foregroundStyle(ink.opacity(0.78))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, translationIsRTL ? .rightToLeft : .leftToRight)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            ornament.padding(.top, 16)
            HStack(spacing: 7) {
                Text(footer)
                    .font(.system(size: 13.5, weight: .bold, design: .serif))
                    .foregroundStyle(accent)
                Spacer(minLength: 8)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                Text("Quran Reader HD")
                    .font(.system(size: 13.5, weight: .bold, design: .serif))
                    .foregroundStyle(ink.opacity(0.8))
            }
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 22, leading: 26, bottom: 18, trailing: 26))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(rule.opacity(0.28), lineWidth: 1))
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(rule.opacity(0.6), lineWidth: 1.2))
        .padding(18)
        .frame(width: Self.width)
        .background {
            ZStack {
                LinearGradient(colors: isEmerald ? [Self.emerald, Self.emeraldDeep]
                                                 : [Color(red: 0.98, green: 0.95, blue: 0.87), Color.parchment],
                               startPoint: .top, endPoint: .bottom)
                StarPattern().stroke(rule.opacity(isEmerald ? 0.09 : 0.12), lineWidth: 1)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private var ornament: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LinearGradient(colors: [rule.opacity(0), rule], startPoint: .leading, endPoint: .trailing))
                .frame(width: 110, height: 1)
            Rectangle().fill(rule).frame(width: 7, height: 7).rotationEffect(.degrees(45))
            Rectangle().fill(LinearGradient(colors: [rule, rule.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 110, height: 1)
        }
    }
}

/// Preview of the card with its style and translation options, and copy / save / share.
struct ShareCardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let key: AyahKey
    @AppStorage("cardStyle") private var style: CardStyle = .emerald
    @AppStorage("cardTranslation") private var withTranslation = true

    private var card: AyahCard {
        let surah = model.surah(key.sura)
        let footer = Localizer.shared.language == .arabic
            ? "\(surah?.name ?? "") · \(arabicDigits(key.ayah))"
            : "\(surah?.englishName ?? "Surah \(key.sura)") · \(key.sura):\(key.ayah)"
        return AyahCard(key: key,
                        arabic: model.text.text(Edition.arabic.id, key) ?? "",
                        surahName: surah?.name ?? "سورة \(arabicDigits(key.sura))",
                        footer: footer,
                        translation: withTranslation ? model.text.text(model.translationID, key) : nil,
                        translationIsRTL: Edition.named(model.translationID).isRTL,
                        style: style)
    }

    /// 1080 px wide, for messaging apps and social posts.
    private func render() -> NSImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / AyahCard.width
        return renderer.nsImage
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    var body: some View {
        let image = render()
        VStack(spacing: 14) {
            Text(tr("Share as Image")).font(.title2.bold())
            ScrollView {
                card.clipShape(RoundedRectangle(cornerRadius: 6)).shadow(radius: 4, y: 2).padding(8)
            }
            .frame(maxHeight: 560)
            HStack {
                Picker("", selection: $style) {
                    ForEach(CardStyle.allCases) { Text(tr($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle(tr("Translation on the card"), isOn: $withTranslation)
            }
            HStack {
                Button(tr("Copy Image")) {
                    guard let image else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
                Button(tr("Save Image…")) { save(image) }
                Spacer()
                if let image {
                    ShareLink(item: Image(nsImage: image), preview: SharePreview(model.citation(key), image: Image(nsImage: image))) {
                        Label(tr("Share…"), systemImage: "square.and.arrow.up")
                    }
                }
                Button(tr("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: AyahCard.width + 60)
        .task { await model.text.ensure(model.translationID) }
    }

    private func save(_ image: NSImage?) {
        guard let image, let data = Self.png(image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Quran \(key.sura)-\(key.ayah).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}
