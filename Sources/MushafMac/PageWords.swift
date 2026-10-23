import Foundation
import Observation

/// Identifies one word glyph on a page: ayah plus its word position.
struct WordRef: Hashable {
    let key: AyahKey
    let position: Int   // glyph position in ayahinfo, not quran.com's word position
}

enum Arabic {
    /// Base letters only: drops harakat, Quranic marks and tatweel, and folds alef/ya/ta-marbuta variants,
    /// so typed queries match the printed text.
    static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            switch u.value {
            case 0x0622, 0x0623, 0x0625, 0x0671: out.append("ا")   // آ أ إ ٱ
            case 0x0649: out.append("ي")                            // ى
            case 0x0629: out.append("ه")                            // ة
            case 0x0621...0x063A, 0x0641...0x064A: out.append(u)
            case 0x0020: out.append(u)
            default:
                if CharacterSet.letters.contains(u), u.value < 0x0600 { out.append(u) }  // keep Latin for mixed input
            }
        }
        return String(out).split(separator: " ").joined(separator: " ")
    }

    /// The name of Allah (lafz al-jalala), with attached prefixes و ف ب ت ل and the vocative اللهم.
    static func isNameOfAllah(_ word: String) -> Bool {
        let w = normalize(word)
        return w.range(of: #"^(و|ف)?(ب|ت|ل)?ا?لله(م)?$"#, options: .regularExpression) != nil
    }
}

/// Word layout per page, used to colour the name of Allah on the monochrome page images.
@Observable
final class PageWords {
    private(set) var allahWords: [Int: Set<WordRef>] = [:]
    private var inFlight: Set<Int> = []

    private struct Envelope: Decodable {
        struct Verse: Decodable {
            struct Word: Decodable {
                let position: Int
                let char_type_name: String
                let text_uthmani: String?
            }
            let verse_key: String
            let words: [Word]
        }
        let verses: [Verse]
    }

    /// Glyphs a quran.com token occupies on the page image: a saktah sign (ۜ) glued to its word is its own glyph.
    private static func glyphCount(_ token: String) -> Int {
        let hasLetters = token.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) || $0.value == 0x0671 }
        return hasLetters && token.unicodeScalars.contains { $0.value == 0x06DC } ? 2 : 1
    }

    /// quran.com words can hold several printed glyphs ("بَعْدَ مَا", a word followed by its pause mark), so the
    /// mapping walks space-separated tokens. Ayahs whose total disagrees with the page's glyph count stay uncoloured.
    @MainActor
    func ensure(_ page: Int, glyphCounts: [AyahKey: Int]) async {
        guard allahWords[page] == nil, !inFlight.contains(page) else { return }
        inFlight.insert(page)
        defer { inFlight.remove(page) }
        let dest = Paths.words.appendingPathComponent(String(format: "page%03d.json", page))
        guard let file = try? await Downloader.fetch(Remote.pageWords(page), to: dest),
              let env = try? JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file)) else {
            try? FileManager.default.removeItem(at: dest)
            return
        }
        var refs = Set<WordRef>()
        for v in env.verses {
            guard let key = AyahKey(string: v.verse_key) else { continue }
            var glyph = 1
            var found: [WordRef] = []
            for w in v.words where w.char_type_name == "word" {
                // Split on scalars: a pause mark is a combining character, so Swift fuses " ۚ" into one Character.
                for scalars in (w.text_uthmani ?? "").unicodeScalars.split(separator: " ") {
                    let token = String(String.UnicodeScalarView(scalars))
                    if Arabic.isNameOfAllah(token) { found.append(WordRef(key: key, position: glyph)) }
                    glyph += Self.glyphCount(token)
                }
            }
            // `glyph` is now one past the last word: the ayah-end marker's position.
            if glyphCounts[key] == glyph { refs.formUnion(found) }
        }
        allahWords[page] = refs
    }
}
