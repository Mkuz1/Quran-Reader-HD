import Foundation
import Observation

struct Surah: Identifiable, Codable {
    let number: Int
    let name: String
    let englishName: String
    let englishNameTranslation: String
    let numberOfAyahs: Int
    let revelationType: String
    var id: Int { number }
}

/// Surah names and juz boundaries from alquran.cloud's /meta endpoint.
struct QuranMeta {
    let surahs: [Surah]
    let juzStarts: [AyahKey]
    /// 240 rub' al-hizb starts; quarter i (0-based) is hizb i/4 + 1, quarter i%4.
    let quarterStarts: [AyahKey]

    private struct Envelope: Decodable {
        struct Data: Decodable {
            struct Refs<T: Decodable>: Decodable { let references: [T] }
            struct Ref: Decodable { let surah: Int; let ayah: Int }
            let surahs: Refs<Surah>
            let juzs: Refs<Ref>
            let hizbQuarters: Refs<Ref>
        }
        let data: Data
    }

    static func load() async throws -> QuranMeta {
        let file = try await Downloader.fetch(Remote.meta, to: Paths.data.appendingPathComponent("meta.json"))
        let env = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        return QuranMeta(surahs: env.data.surahs.references,
                         juzStarts: env.data.juzs.references.map { AyahKey($0.surah, $0.ayah) },
                         quarterStarts: env.data.hizbQuarters.references.map { AyahKey($0.surah, $0.ayah) })
    }
}

struct Edition: Identifiable, Hashable {
    enum Kind { case arabic, translation, tafsir }
    enum Source: Hashable {
        case alquranCloud
        case quranComTranslation(Int)   // whole Quran in one request
        case quranComTafsir(Int)        // fetched per surah
        case quranEnc(String)           // quranenc.com translation key, fetched per surah
    }
    let id: String
    let title: String
    let kind: Kind
    let language: String
    var source: Source = .alquranCloud
    var isRTL: Bool { language == "ar" }

    static let arabic = Edition(id: "quran-uthmani", title: "Arabic (Uthmani)", kind: .arabic, language: "ar")
    /// Plain spelling without diacritics, used only as the Arabic search index.
    static let arabicSearch = Edition(id: "quran-simple-clean", title: "Arabic (plain)", kind: .arabic, language: "ar")
    static let all: [Edition] = [
        arabic,
        Edition(id: "en.sahih", title: "English — Saheeh International", kind: .translation, language: "en"),
        Edition(id: "en.pickthall", title: "English — Pickthall", kind: .translation, language: "en"),
        Edition(id: "fr.hamidullah", title: "Français — Hamidullah", kind: .translation, language: "fr"),
        Edition(id: "qc-tr-136", title: "Français — Montada Islamic Foundation", kind: .translation, language: "fr",
                source: .quranComTranslation(136)),
        Edition(id: "qc-tr-779", title: "Français — Rashid Maash", kind: .translation, language: "fr",
                source: .quranComTranslation(779)),
        Edition(id: "ar.muyassar", title: "التفسير الميسر — Al-Muyassar", kind: .tafsir, language: "ar"),
        Edition(id: "ar.jalalayn", title: "تفسير الجلالين — Al-Jalalayn", kind: .tafsir, language: "ar"),
        Edition(id: "qe-french_mokhtasar", title: "Français — Al-Mukhtasar (Exégèse abrégée)", kind: .tafsir, language: "fr",
                source: .quranEnc("french_mokhtasar")),
        Edition(id: "qc-tafsir-169", title: "English — Ibn Kathir (abridged)", kind: .tafsir, language: "en",
                source: .quranComTafsir(169)),
        Edition(id: "qc-tafsir-168", title: "English — Ma'arif al-Qur'an", kind: .tafsir, language: "en",
                source: .quranComTafsir(168)),
        Edition(id: "qc-tafsir-817", title: "English — Tazkirul Quran", kind: .tafsir, language: "en",
                source: .quranComTafsir(817)),
    ]
    static var translations: [Edition] { all.filter { $0.kind == .translation } }
    static var tafsirs: [Edition] { all.filter { $0.kind == .tafsir } }
    static func named(_ id: String) -> Edition { (all + [arabicSearch]).first { $0.id == id } ?? arabic }

    /// Defaults when the UI language changes.
    static func defaults(for language: AppLanguage) -> (translation: String, tafsir: String) {
        switch language {
        case .english: ("en.sahih", "qc-tafsir-169")
        case .french: ("fr.hamidullah", "qe-french_mokhtasar")
        case .arabic: ("en.sahih", "ar.muyassar")
        }
    }
}

/// quran.com text is HTML: footnote markers are dropped, block tags become paragraph breaks.
enum HTMLText {
    static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<sup[^>]*>.*?</sup>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"</(p|h[1-6]|li|div)>"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in ["&nbsp;": " ", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&amp;": "&"] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Full-Quran text editions, downloaded once per edition and cached as JSON.
@Observable
final class TextLibrary {
    private(set) var texts: [String: [[String]]] = [:]   // edition -> [sura-1][ayah-1]
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: String] = [:]
    /// Per-surah texts for editions fetched one surah at a time (quran.com tafsir, quranenc): edition -> sura -> ayahs.
    private(set) var chapters: [String: [Int: [String]]] = [:]
    /// Arabic.normalize applied to every ayah of the plain edition, built once it loads.
    @ObservationIgnored private var normalizedArabic: [[String]] = []

    private struct Envelope: Decodable {
        struct Data: Decodable {
            struct S: Decodable { let ayahs: [A] }
            struct A: Decodable { let text: String }
            let surahs: [S]
        }
        let data: Data
    }

    func text(_ edition: String, _ key: AyahKey) -> String? {
        switch Edition.named(edition).source {
        case .quranEnc:
            guard let ayahs = chapters[edition]?[key.sura], key.ayah - 1 < ayahs.count else { return nil }
            return ayahs[key.ayah - 1].isEmpty ? nil : ayahs[key.ayah - 1]
        case .quranComTafsir:
            guard let ayahs = chapters[edition]?[key.sura], !ayahs.isEmpty else { return nil }
            if key.ayah - 1 < ayahs.count, !ayahs[key.ayah - 1].isEmpty { return ayahs[key.ayah - 1] }
            // Grouped commentary: an empty (or trailing, omitted) entry belongs to the nearest earlier ayah that has text.
            let last = min(key.ayah - 1, ayahs.count)
            guard last >= 1, let first = (1...last).reversed().first(where: { !ayahs[$0 - 1].isEmpty }) else { return nil }
            let note = tr("Commentary for ayahs %@ is under %@.", "\(key.sura):\(first)–\(key.ayah)", "\(key.sura):\(first)")
            return note + "\n\n" + ayahs[first - 1]
        default: break
        }
        guard let t = texts[edition], key.sura - 1 < t.count, key.ayah - 1 < t[key.sura - 1].count else { return nil }
        let text = t[key.sura - 1][key.ayah - 1]
        // The Arabic editions prefixes each surah's first ayah with the four-word basmala; it isn't part of the ayah.
        if edition == Edition.arabic.id || edition == Edition.arabicSearch.id, key.ayah == 1, key.sura != 1 {
            let words = text.split(separator: " ")
            let baseLetters = words.first?.unicodeScalars.filter { (0x0621...0x064A).contains($0.value) }
            if words.count > 4, let baseLetters, String(String.UnicodeScalarView(baseLetters)) == "بسم" {
                return words.dropFirst(4).joined(separator: " ")
            }
        }
        return text
    }

    struct SearchHit: Identifiable, Hashable {
        let key: AyahKey
        let edition: String
        var id: String { "\(edition)/\(key)" }
    }

    /// Ayahs whose Arabic (diacritic-insensitive) or translation text contains `query`, Arabic matches first.
    func search(_ query: String, translation: String, limit: Int) -> (hits: [SearchHit], more: Bool) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return ([], false) }
        var hits: [SearchHit] = []
        func scan(_ edition: String, _ matches: (String) -> Bool) {
            guard let t = texts[edition] else { return }
            for (si, ayahs) in t.enumerated() {
                for ai in ayahs.indices {
                    let key = AyahKey(si + 1, ai + 1)
                    if let text = text(edition, key), matches(text) {
                        hits.append(SearchHit(key: key, edition: edition))
                        if hits.count > limit { return }
                    }
                }
            }
        }
        let arabicQuery = Arabic.normalize(q)
        if !arabicQuery.isEmpty, q.unicodeScalars.contains(where: { (0x0600...0x06FF).contains($0.value) }) {
            outer: for (si, ayahs) in normalizedArabic.enumerated() {
                for (ai, text) in ayahs.enumerated() where text.contains(arabicQuery) {
                    hits.append(SearchHit(key: AyahKey(si + 1, ai + 1), edition: Edition.arabicSearch.id))
                    if hits.count > limit { break outer }
                }
            }
        } else {
            scan(translation) { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let more = hits.count > limit
        return (Array(hits.prefix(limit)), more)
    }

    /// Distinct Arabic words starting with the typed prefix, for search suggestions.
    func suggestions(for prefix: String, max: Int = 8) -> [String] {
        let p = Arabic.normalize(prefix)
        guard p.count >= 2, !p.contains(" ") else { return [] }
        var counts: [String: Int] = [:]
        for ayahs in normalizedArabic { for a in ayahs { for w in a.split(separator: " ") where w.hasPrefix(p) { counts[String(w), default: 0] += 1 } } }
        return counts.sorted { $0.value > $1.value }.prefix(max).map(\.key)
    }

    @MainActor
    func ensure(_ edition: String, sura: Int? = nil) async {
        switch Edition.named(edition).source {
        case .alquranCloud: await ensureAlquran(edition)
        case let .quranComTranslation(id): await ensureQuranComTranslation(edition, id)
        case let .quranComTafsir(id): if let sura { await ensureQuranComTafsir(edition, id, sura) }
        case let .quranEnc(key): if let sura { await ensureQuranEnc(edition, key, sura) }
        }
    }

    /// quranenc.com returns numbers as strings; accept either.
    private struct QESura: Decodable {
        struct A: Decodable {
            let aya: Int
            let translation: String
            enum CodingKeys: String, CodingKey { case aya, translation }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let n = try? c.decode(Int.self, forKey: .aya) { aya = n }
                else if let n = Int(try c.decode(String.self, forKey: .aya)) { aya = n }
                else { throw DecodingError.dataCorruptedError(forKey: .aya, in: c, debugDescription: "aya") }
                translation = try c.decode(String.self, forKey: .translation)
            }
        }
        let result: [A]
    }

    @MainActor
    private func ensureQuranEnc(_ edition: String, _ key: String, _ sura: Int) async {
        let tag = "\(edition)/\(sura)"
        guard chapters[edition]?[sura] == nil, !loading.contains(tag) else { return }
        loading.insert(tag)
        defer { loading.remove(tag) }
        let dest = Paths.text.appendingPathComponent("\(edition)-\(sura).json")
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                let url = URL(string: "https://quranenc.com/api/v1/translation/sura/\(key)/\(sura)")!
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadError.http(0, url) }
                var byAyah: [Int: String] = [:]
                for a in try JSONDecoder().decode(QESura.self, from: data).result { byAyah[a.aya] = HTMLText.plain(a.translation) }
                let count = byAyah.keys.max() ?? 0
                let ayahs = (0..<count).map { byAyah[$0 + 1] ?? "" }
                try JSONEncoder().encode(ayahs).write(to: dest, options: .atomic)
            }
            chapters[edition, default: [:]][sura] = try JSONDecoder().decode([String].self, from: Data(contentsOf: dest))
            errors[edition] = nil
        } catch {
            errors[edition] = error.localizedDescription
        }
    }

    private struct QCTranslations: Decodable {
        struct T: Decodable { let verse_key: String; let text: String }
        let translations: [T]
    }

    private struct QCTafsirPage: Decodable {
        struct T: Decodable { let verse_key: String; let text: String }
        struct P: Decodable { let next_page: Int? }
        let tafsirs: [T]
        let pagination: P
    }

    @MainActor
    private func ensureQuranComTranslation(_ edition: String, _ id: Int) async {
        guard texts[edition] == nil, !loading.contains(edition) else { return }
        loading.insert(edition)
        defer { loading.remove(edition) }
        let dest = Paths.text.appendingPathComponent("\(edition).json")
        do {
            let url = URL(string: "https://api.quran.com/api/v4/quran/translations/\(id)?fields=verse_key")!
            let file = try await Downloader.fetch(url, to: dest)
            texts[edition] = try await Task.detached {
                var out: [[String]] = Array(repeating: [], count: 114)
                for t in try JSONDecoder().decode(QCTranslations.self, from: Data(contentsOf: file)).translations {
                    guard let key = AyahKey(string: t.verse_key), (1...114).contains(key.sura) else { continue }
                    out[key.sura - 1].append(HTMLText.plain(t.text))
                }
                return out
            }.value
            errors[edition] = nil
        } catch {
            errors[edition] = error.localizedDescription
            try? FileManager.default.removeItem(at: dest)
        }
    }

    @MainActor
    private func ensureQuranComTafsir(_ edition: String, _ id: Int, _ sura: Int) async {
        let tag = "\(edition)/\(sura)"
        guard chapters[edition]?[sura] == nil, !loading.contains(tag) else { return }
        loading.insert(tag)
        defer { loading.remove(tag) }
        let dest = Paths.text.appendingPathComponent("\(edition)-\(sura).json")
        do {
            if !FileManager.default.fileExists(atPath: dest.path) {
                var byAyah: [Int: String] = [:]
                var page: Int? = 1
                while let p = page {
                    let url = URL(string: "https://api.quran.com/api/v4/tafsirs/\(id)/by_chapter/\(sura)?per_page=50&page=\(p)")!
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadError.http(0, url) }
                    let decoded = try JSONDecoder().decode(QCTafsirPage.self, from: data)
                    for t in decoded.tafsirs { if let k = AyahKey(string: t.verse_key) { byAyah[k.ayah] = HTMLText.plain(t.text) } }
                    page = decoded.pagination.next_page
                }
                let count = byAyah.keys.max() ?? 0
                let ayahs = (0..<count).map { byAyah[$0 + 1] ?? "" }
                try JSONEncoder().encode(ayahs).write(to: dest, options: .atomic)
            }
            chapters[edition, default: [:]][sura] = try JSONDecoder().decode([String].self, from: Data(contentsOf: dest))
            errors[edition] = nil
        } catch {
            errors[edition] = error.localizedDescription
        }
    }

    @MainActor
    private func ensureAlquran(_ edition: String) async {
        guard texts[edition] == nil, !loading.contains(edition) else { return }
        loading.insert(edition)
        defer { loading.remove(edition) }
        do {
            let file = try await Downloader.fetch(Remote.edition(edition),
                                                  to: Paths.text.appendingPathComponent("\(edition).json"))
            let parsed = try await Task.detached {
                try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
                    .data.surahs.map { $0.ayahs.map { $0.text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}")) } }
            }.value
            texts[edition] = parsed
            if edition == Edition.arabicSearch.id {
                normalizedArabic = await Task.detached {
                    parsed.enumerated().map { si, ayahs in
                        ayahs.indices.map { ai in
                            var t = ayahs[ai]
                            // Drop the basmala prefix on first ayahs so it doesn't match every surah.
                            let basmala = "بسم الله الرحمن الرحيم "
                            if ai == 0, si > 0, t.hasPrefix(basmala) { t = String(t.dropFirst(basmala.count)) }
                            return Arabic.normalize(t)
                        }
                    }
                }.value
            }
            errors[edition] = nil
        } catch {
            errors[edition] = error.localizedDescription
            try? FileManager.default.removeItem(at: Paths.text.appendingPathComponent("\(edition).json"))
        }
    }
}
