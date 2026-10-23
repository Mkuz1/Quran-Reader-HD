import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum ReadingMode: String, CaseIterable, Identifiable {
    case mushaf = "Mushaf"
    case text = "Translation & Tafsir"
    var id: String { rawValue }
}

enum PageTheme: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case coloured = "Coloured"
    case night = "Night"
    var id: String { rawValue }
}

enum StudyDisplay: String, CaseIterable, Identifiable {
    case arabic = "Arabic"
    case translation = "Translation"
    case both = "Both"
    var id: String { rawValue }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case translation = "Translation"
    case tafsir = "Tafsir"
    case note = "Note"
    var id: String { rawValue }
}

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case loading(String)
        case ready
        case failed(String)
    }

    var status: Status = .loading("Preparing…")
    private(set) var db: GlyphDB?
    private(set) var meta: QuranMeta?

    let text = TextLibrary()
    let library = UserLibrary()
    let audio = AudioController()
    let images = PageImages()
    let words = PageWords()
    let updates = UpdateChecker()

    /// Always set through go(to:), which clamps (re-assigning inside didSet recurses under @Observable).
    var page: Int = 1 {
        didSet { library.lastPage = page }
    }
    /// Direction of the last page turn, for the slide transition.
    var turningForward = true
    var dualPage: Bool = UserDefaults.standard.object(forKey: "dualPage") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dualPage, forKey: "dualPage") }
    }
    var mode: ReadingMode = .mushaf
    var selected: AyahKey? {
        didSet { if let selected { remember(selected, listening: false) } }
    }
    var hovered: AyahKey?
    var showInspector = false
    var inspectorTab: InspectorTab = .translation
    var translationID: String = UserDefaults.standard.string(forKey: "translation") ?? "en.sahih" {
        didSet { UserDefaults.standard.set(translationID, forKey: "translation") }
    }
    var tafsirID: String = UserDefaults.standard.string(forKey: "tafsir") ?? "ar.jalalayn" {
        didSet { UserDefaults.standard.set(tafsirID, forKey: "tafsir") }
    }
    let pageStore = PageStore()
    /// First-run choice between downloading the pages and reading online.
    var showPagesChoice = false

    // Display settings (the original's brightness window, swipe toggle and study display modes).
    var theme: PageTheme = PageTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .coloured {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    var brightness: Double = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(brightness, forKey: "brightness") }
    }
    var swipeEnabled: Bool = UserDefaults.standard.object(forKey: "swipe") as? Bool ?? true {
        didSet { UserDefaults.standard.set(swipeEnabled, forKey: "swipe") }
    }
    var studyDisplay: StudyDisplay = StudyDisplay(rawValue: UserDefaults.standard.string(forKey: "study") ?? "") ?? .both {
        didSet { UserDefaults.standard.set(studyDisplay.rawValue, forKey: "study") }
    }
    var showHelp = false
    /// The ayah whose share card is open.
    var shareCardKey: AyahKey?
    /// The Sadaqa Jariyah opening page, shown at every launch and from the Help menu.
    var showDedication = true

    /// Switches the UI language and moves translation/tafsir to that language's defaults.
    func setLanguage(_ language: AppLanguage) {
        guard language != Localizer.shared.language else { return }
        Localizer.shared.language = language
        let d = Edition.defaults(for: language)
        translationID = d.translation
        tafsirID = d.tafsir
    }

    init() {
        // French used to default to English Ibn Kathir for lack of a French tafsir; move those users to the French one once.
        if !UserDefaults.standard.bool(forKey: "frenchTafsirAdded") {
            UserDefaults.standard.set(true, forKey: "frenchTafsirAdded")
            if Localizer.shared.language == .french, tafsirID == "qc-tafsir-169" {
                tafsirID = Edition.defaults(for: .french).tafsir
            }
        }
        page = library.lastPage
        library.onRemotePage = { [weak self] remote in self?.go(to: remote) }
    }

    func bootstrap() async {
        do {
            let dbURL = Paths.data.appendingPathComponent("ayahinfo_1024.db")
            if !FileManager.default.fileExists(atPath: dbURL.path) {
                status = .loading("Downloading ayah coordinates…")
                try await Downloader.fetch(Remote.ayahInfoDB, to: dbURL)
            }
            let db = try GlyphDB(url: dbURL)
            self.db = db
            audio.db = db
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        meta = try? await QuranMeta.load()
        await text.ensure(Edition.arabic.id)
        await text.ensure(translationID)
        await text.ensure(Edition.arabicSearch.id)
    }

    // MARK: Where reading stopped

    /// The ayah last selected or recited, kept across launches with the last page, for "continue reading".
    private(set) var lastAyah: AyahKey? = UserDefaults.standard.string(forKey: "lastAyah").flatMap(AyahKey.init(string:))
    /// Whether that ayah was being recited, to offer "continue listening".
    private(set) var lastListening = UserDefaults.standard.bool(forKey: "lastListening")

    func remember(_ key: AyahKey, listening: Bool) {
        lastAyah = key
        lastListening = listening
        UserDefaults.standard.set(key.description, forKey: "lastAyah")
        UserDefaults.standard.set(listening, forKey: "lastListening")
    }

    /// The remembered ayah, if it is still on the pages reading stopped at (paging on drops it).
    var resumeAyah: AyahKey? {
        guard let key = lastAyah else { return nil }
        guard let p = db?.page(of: key) else { return key }   // ayah positions not loaded yet: trust it
        return visiblePages.contains(p) ? key : nil
    }

    /// Opens the book at the remembered ayah once the ayah positions are loaded, and recites from it when `listen`.
    func resume(listen: Bool) {
        Task {
            while db == nil {
                if case .failed = status { return }
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard let key = resumeAyah else { return }
            go(to: key)
            if listen { audio.play(from: key) }
        }
    }

    // MARK: Navigation

    /// Madani mushaf spreads: odd pages on the right, the following even page on the left.
    var spread: (right: Int, left: Int?) {
        let right = page % 2 == 1 ? page : page - 1
        return (right, right + 1 <= Quran.pageCount ? right + 1 : nil)
    }

    var visiblePages: [Int] {
        dualPage ? [spread.right, spread.left].compactMap { $0 } : [page]
    }

    func go(to newPage: Int) {
        let target = min(max(newPage, 1), Quran.pageCount)
        guard target != page else { return }
        turningForward = target > page
        withAnimation(.easeInOut(duration: 0.3)) { page = target }
    }

    func go(to key: AyahKey, select: Bool = true) {
        if select { selected = key }
        if let p = db?.page(of: key), !visiblePages.contains(p) { go(to: p) }
    }

    func turn(forward: Bool) {
        let step = dualPage ? 2 : 1
        let base = dualPage ? spread.right : page
        go(to: base + (forward ? step : -step))
    }

    // MARK: Lookups

    func surah(_ n: Int) -> Surah? { meta?.surahs.first { $0.number == n } }

    /// Surah name in the UI language: the Arabic name in Arabic, the transliteration otherwise.
    func surahName(_ n: Int) -> String {
        guard let s = surah(n) else { return "\(n)" }
        return Localizer.shared.language == .arabic ? s.name : s.englishName
    }

    func surahTitle(_ n: Int) -> String { "\(n). \(surahName(n))" }

    func startPage(sura: Int) -> Int { db?.page(of: AyahKey(sura, 1)) ?? 1 }

    var juzStartPages: [Int] {
        guard let db, let meta else { return [] }
        return meta.juzStarts.compactMap { db.page(of: $0) }
    }

    func juz(for page: Int) -> Int {
        let starts = juzStartPages
        return (starts.lastIndex { $0 <= page } ?? 0) + 1
    }

    var quarterStartPages: [Int] {
        guard let db, let meta else { return [] }
        return meta.quarterStarts.compactMap { db.page(of: $0) }
    }

    /// 0-based rub' al-hizb index the page falls in.
    func quarterIndex(for page: Int) -> Int {
        quarterStartPages.lastIndex { $0 <= page } ?? 0
    }

    static func quarterLabel(_ index: Int) -> String {
        let hizb = index / 4 + 1
        return tr(["Hizb %d", "¼ Hizb %d", "½ Hizb %d", "¾ Hizb %d"][index % 4], hizb)
    }

    /// Opening words of an ayah, like the original's index snippets.
    func snippet(_ key: AyahKey, words count: Int = 5) -> String {
        guard let t = text.text(Edition.arabic.id, key) else { return "" }
        let w = t.split(separator: " ")
        return w.prefix(count).joined(separator: " ") + (w.count > count ? " …" : "")
    }

    func firstAyah(on page: Int) -> AyahKey? { db?.ayahs(page: page).first }

    func pageTitle(_ page: Int) -> String {
        guard let first = firstAyah(on: page) else { return tr("Page %d", page) }
        return "\(surahTitle(first.sura)) · \(tr("Page %d", page))"
    }

    // MARK: Actions

    func showText(_ tab: InspectorTab, for key: AyahKey) {
        selected = key
        inspectorTab = tab
        showInspector = true
    }

    /// "Surah Al-Baqara : Verse 255 : Page 42", the original's citation format.
    func citation(_ key: AyahKey) -> String {
        let name = surah(key.sura)?.englishName ?? "\(key.sura)"
        return "Surah \(name) : Verse \(key.ayah) : Page \(db?.page(of: key) ?? 0)"
    }

    /// Arabic, the selected translation and the citation, for copying and sharing.
    func shareText(_ key: AyahKey) -> String {
        var parts: [String] = []
        if let a = text.text(Edition.arabic.id, key) { parts.append("\(a) ﴿\(key.ayah)﴾") }
        if let t = text.text(translationID, key) { parts.append(t) }
        parts.append(citation(key))
        return parts.joined(separator: "\n\n")
    }

    func copyArabic(_ key: AyahKey) {
        guard let t = text.text(Edition.arabic.id, key) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(t) ﴿\(key.ayah)﴾\n\(citation(key))", forType: .string)
    }

    func copyWithTranslation(_ key: AyahKey) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareText(key), forType: .string)
    }

    // MARK: Export

    private func notesHTML() -> String {
        library.html(surahTitle: surahTitle, arabic: { self.text.text(Edition.arabic.id, $0) }, pageTitle: pageTitle)
    }

    private func noExportAlert() {
        let alert = NSAlert()
        alert.messageText = tr("There are no notes or bookmarks to export")
        alert.runModal()
    }

    func exportHTMLWithPanel() {
        guard !library.isEmpty else { return noExportAlert() }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "Mushaf Notes & Bookmarks.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? notesHTML().write(to: url, atomically: true, encoding: .utf8)
    }

    func emailNotes() {
        guard !library.isEmpty else { return noExportAlert() }
        // A mailto: link works with whichever mail app is the default; the Mail share extension can be disabled.
        var c = URLComponents()
        c.scheme = "mailto"
        c.queryItems = [
            URLQueryItem(name: "subject", value: "Mushaf Notes & Bookmarks"),
            URLQueryItem(name: "body", value: library.plainText(surahTitle: surahTitle,
                                                                arabic: { self.text.text(Edition.arabic.id, $0) },
                                                                pageTitle: pageTitle)),
        ]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    // MARK: Deep links

    /// mushaf://page/128, mushaf://ayah/2/255 (also mushaf://2:255) and mushaf://surah/18.
    func handle(_ url: URL) {
        guard url.scheme == "mushaf" else { return }
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        switch parts.first {
        case "page": if let p = parts.dropFirst().first.flatMap(Int.init) { go(to: p) }
        case "surah": if let n = parts.dropFirst().first.flatMap(Int.init), (1...114).contains(n) { go(to: startPage(sura: n)) }
        case "ayah":
            let nums = parts.dropFirst().compactMap(Int.init)
            if nums.count == 2 { go(to: AyahKey(nums[0], nums[1])) }
        default:
            // mushaf://36:1 parses as host "36", port 1.
            if let host = url.host.flatMap(Int.init), let port = url.port { go(to: AyahKey(host, port)) }
            else if let first = parts.first, let key = AyahKey(string: first) { go(to: key) }
        }
    }

}

/// Page PNG cache: memory (NSCache) over disk over network.
final class PageImages {
    private let cache = NSCache<NSNumber, NSImage>()

    init() { cache.countLimit = 16 }

    func cached(_ page: Int) -> NSImage? { cache.object(forKey: page as NSNumber) }

    /// The installed page if present, otherwise fetched from GitHub into the online cache.
    func file(for page: Int) async throws -> URL {
        let name = String(format: "page%03d.png", page)
        let installed = Paths.pages.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: installed.path) { return installed }
        return try await Downloader.fetch(Remote.pageImage(page), to: Paths.onlinePages.appendingPathComponent(name))
    }

    func image(_ page: Int) async throws -> NSImage {
        if let img = cached(page) { return img }
        let url = try await file(for: page)
        guard let img = NSImage(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url)
            throw DownloadError.http(0, url)
        }
        cache.setObject(img, forKey: page as NSNumber)
        return img
    }
}
