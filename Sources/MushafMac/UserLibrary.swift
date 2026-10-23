import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var page: Int
    var created = Date()
    var title: String?
}

struct Note: Codable, Hashable {
    var text: String
    var updated = Date()
}

/// Notes, bookmarks and last-read page. Notes/bookmarks live in library.json;
/// the last page is mirrored to iCloud key-value storage when the app is signed for it.
@Observable
final class UserLibrary {
    private struct Snapshot: Codable {
        var bookmarks: [Bookmark] = []
        var notes: [String: Note] = [:]   // "sura:ayah" -> note
    }

    private(set) var bookmarks: [Bookmark] = []
    private(set) var notes: [AyahKey: Note] = [:]

    var lastPage: Int {
        didSet {
            UserDefaults.standard.set(lastPage, forKey: Self.lastPageKey)
            cloud.set(lastPage, forKey: Self.lastPageKey)
        }
    }

    private static let lastPageKey = "lastPage"
    private let cloud = NSUbiquitousKeyValueStore.default
    /// Called when another device reports a different last-read page.
    var onRemotePage: ((Int) -> Void)?

    init() {
        let local = UserDefaults.standard.integer(forKey: Self.lastPageKey)
        lastPage = (1...Quran.pageCount).contains(local) ? local : 1
        if let data = try? Data(contentsOf: Paths.library),
           let snap = try? JSONDecoder.iso.decode(Snapshot.self, from: data) {
            apply(snap, merge: false)
        }
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let remote = Int(self.cloud.longLong(forKey: Self.lastPageKey))
            if (1...Quran.pageCount).contains(remote), remote != self.lastPage { self.onRemotePage?(remote) }
        }
        cloud.synchronize()
    }

    // MARK: Bookmarks

    func isBookmarked(_ page: Int) -> Bool { bookmarks.contains { $0.page == page } }

    func toggleBookmark(_ page: Int, title: String? = nil) {
        if isBookmarked(page) { bookmarks.removeAll { $0.page == page } }
        else { bookmarks.append(Bookmark(page: page, title: title)) }
        save()
    }

    func rename(_ b: Bookmark, to title: String) {
        guard let i = bookmarks.firstIndex(where: { $0.id == b.id }) else { return }
        bookmarks[i].title = title.isEmpty ? nil : title
        save()
    }

    func removeBookmark(_ b: Bookmark) {
        bookmarks.removeAll { $0.id == b.id }
        save()
    }

    // MARK: Notes

    func setNote(_ text: String, for key: AyahKey) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { notes[key] = nil }
        else if notes[key]?.text != text { notes[key] = Note(text: text) }
        save()
    }

    // MARK: Persistence, export & import

    private var snapshot: Snapshot {
        Snapshot(bookmarks: bookmarks.sorted { $0.page < $1.page },
                 notes: Dictionary(uniqueKeysWithValues: notes.map { ($0.key.description, $0.value) }))
    }

    private func apply(_ snap: Snapshot, merge: Bool) {
        if !merge { bookmarks = []; notes = [:] }
        for b in snap.bookmarks where !isBookmarked(b.page) { bookmarks.append(b) }
        for (k, n) in snap.notes {
            guard let key = AyahKey(string: k) else { continue }
            if let existing = notes[key], existing.updated > n.updated { continue }
            notes[key] = n
        }
    }

    private func save() {
        guard let data = try? JSONEncoder.iso.encode(snapshot) else { return }
        try? data.write(to: Paths.library, options: .atomic)
    }

    @MainActor
    func exportWithPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Mushaf Notes & Bookmarks.json"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? JSONEncoder.iso.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    var isEmpty: Bool { bookmarks.isEmpty && notes.isEmpty }

    /// The same content as plain text, for an email body.
    func plainText(surahTitle: (Int) -> String, arabic: (AyahKey) -> String?, pageTitle: (Int) -> String) -> String {
        var t = "Mushaf Notes & Bookmarks\n"
        if !notes.isEmpty {
            t += "\nNOTES\n"
            for key in notes.keys.sorted() {
                t += "\n\(surahTitle(key.sura)) : \(key.ayah)\n"
                if let a = arabic(key) { t += "\(a)\n" }
                t += "\(notes[key]!.text)\n"
            }
        }
        if !bookmarks.isEmpty {
            t += "\nBOOKMARKS\n"
            for b in bookmarks.sorted(by: { $0.page < $1.page }) { t += "• \(b.title ?? pageTitle(b.page))\n" }
        }
        return t
    }

    /// A readable HTML page of all notes (with the ayah text) and bookmarks.
    func html(surahTitle: (Int) -> String, arabic: (AyahKey) -> String?, pageTitle: (Int) -> String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        var h = """
        <!doctype html><html><head><meta charset="utf-8"><title>Mushaf Notes & Bookmarks</title>
        <style>body{font:15px -apple-system,sans-serif;max-width:760px;margin:2em auto;padding:0 1em;color:#222}
        h1{font-size:22px}h2{font-size:17px;border-bottom:1px solid #ddd;padding-bottom:4px;margin-top:2em}
        .ar{font:22px 'Geeza Pro',serif;direction:rtl;text-align:right;line-height:1.9}
        .meta{color:#888;font-size:12px}.note{margin:1.2em 0}</style></head><body>
        <h1>Mushaf Notes &amp; Bookmarks</h1>
        """
        if !notes.isEmpty {
            h += "<h2>Notes</h2>"
            for key in notes.keys.sorted() {
                let n = notes[key]!
                h += "<div class='note'><b>\(esc(surahTitle(key.sura))) : \(key.ayah)</b> <span class='meta'>\(df.string(from: n.updated))</span>"
                if let a = arabic(key) { h += "<p class='ar'>\(esc(a))</p>" }
                h += "<p>\(esc(n.text))</p></div>"
            }
        }
        if !bookmarks.isEmpty {
            h += "<h2>Bookmarks</h2><ul>"
            for b in bookmarks.sorted(by: { $0.page < $1.page }) {
                h += "<li>\(esc(b.title ?? pageTitle(b.page))) <span class='meta'>\(df.string(from: b.created))</span></li>"
            }
            h += "</ul>"
        }
        return h + "</body></html>"
    }

    @MainActor
    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder.iso.decode(Snapshot.self, from: data) else { return }
        apply(snap, merge: true)
        save()
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
