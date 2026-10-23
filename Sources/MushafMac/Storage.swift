import Foundation

/// Identifies one verse.
struct AyahKey: Hashable, Codable, Comparable, CustomStringConvertible {
    var sura: Int
    var ayah: Int

    var description: String { "\(sura):\(ayah)" }

    init(_ sura: Int, _ ayah: Int) {
        self.sura = sura
        self.ayah = ayah
    }

    init?(string: String) {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(parts[0], parts[1])
    }

    static func < (a: AyahKey, b: AyahKey) -> Bool {
        (a.sura, a.ayah) < (b.sura, b.ayah)
    }
}

enum Quran {
    static let pageCount = 604
    static let pageImageSize = CGSize(width: 1024, height: 1656)
}

/// On-disk cache locations under ~/Library/Application Support/MushafMac.
enum Paths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MushafMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func dir(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Installed (downloaded) pages, kept until the user removes them.
    static var pages: URL { dir("pages") }
    /// Pages fetched while reading online: in Caches, so macOS may purge them.
    static let onlinePages: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MushafMac/pages", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static var data: URL { dir("data") }
    static var text: URL { dir("text") }
    static var words: URL { dir("words") }
    static func audio(_ reciter: String) -> URL { dir("audio/\(reciter)") }
    static var library: URL { root.appendingPathComponent("library.json") }
}

/// Data sources. Mushaf pages and ayah positions are served from this project's GitHub repository
/// (one file per page for online reading, a release zip for installing); audio is EveryAyah; text is
/// alquran.cloud and quran.com.
enum Remote {
    static let repository = "Mkuz1/Quran-Reader-HD"
    private static let raw = "https://raw.githubusercontent.com/\(repository)/main"

    static func pageImage(_ page: Int) -> URL {
        URL(string: String(format: "\(raw)/pages/page%03d.png", page))!
    }
    static let ayahInfoDB = URL(string: "\(raw)/data/ayahinfo_1024.db")!
    /// All 604 pages in one archive, attached to the repository's "pages-v1" release.
    static let pagesArchive = URL(string: "https://github.com/\(repository)/releases/download/pages-v1/QuranReaderHD-Pages.zip")!
    static let pagesArchiveMB = 57
    static let meta = URL(string: "https://api.alquran.cloud/v1/meta")!
    static func edition(_ id: String) -> URL {
        URL(string: "https://api.alquran.cloud/v1/quran/\(id)")!
    }
    /// Word-level layout for one page (position and line of every word), from quran.com.
    static func pageWords(_ page: Int) -> URL {
        URL(string: "https://api.quran.com/api/v4/verses/by_page/\(page)?words=true&word_fields=text_uthmani&per_page=50")!
    }
    /// This repository's releases, newest first, for the update check.
    static let releases = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
    static func audio(_ reciter: String, _ key: AyahKey) -> URL {
        URL(string: String(format: "https://everyayah.com/data/%@/%03d%03d.mp3", reciter, key.sura, key.ayah))!
    }
}

enum DownloadError: LocalizedError {
    case http(Int, URL)
    case unzip

    var errorDescription: String? {
        switch self {
        case let .http(code, url): "Download failed (\(code)): \(url.lastPathComponent)"
        case .unzip: "Could not unpack the downloaded archive."
        }
    }
}

enum Downloader {
    /// Returns `dest`, downloading `url` to it first if it isn't cached yet.
    @discardableResult
    static func fetch(_ url: URL, to dest: URL) async throws -> URL {
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        let (tmp, response) = try await downloadWithRetry(url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            try? FileManager.default.removeItem(at: tmp)
            throw DownloadError.http(code, url)
        }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Transport errors (not HTTP statuses) are retried, since the first request after launch can fail.
    private static func downloadWithRetry(_ url: URL, attempts: Int = 3) async throws -> (URL, URLResponse) {
        for attempt in 1... {
            do { return try await URLSession.shared.download(from: url) }
            catch where attempt < attempts && (error as? URLError) != nil {
                try await Task.sleep(for: .seconds(attempt))
            }
        }
        fatalError("unreachable")
    }

    static func unzip(_ zip: URL, into dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw DownloadError.unzip }
    }
}
