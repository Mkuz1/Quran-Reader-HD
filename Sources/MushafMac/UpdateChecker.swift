import AppKit
import Foundation
import Observation

/// Checks GitHub for a newer release at launch (at most every 6 hours) and from Help → Check for Updates.
@MainActor
@Observable
final class UpdateChecker {
    struct Update: Equatable {
        let version: String
        let page: URL
        /// The release's DMG, when it has one.
        let download: URL?
    }

    private(set) var available: Update?
    private(set) var checking = false

    /// nil when run as a bare executable (swift run), which has no version to compare.
    static var currentVersion: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    /// Numeric version parts, so 1.10 sorts after 1.9; "v1.2" and "1.2.0" compare equal.
    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let d = (i < x.count ? x[i] : 0) - (i < y.count ? y[i] : 0)
            if d != 0 { return d > 0 ? 1 : -1 }
        }
        return 0
    }

    func check(manual: Bool = false) async {
        guard !checking, let current = Self.currentVersion else { return }
        let defaults = UserDefaults.standard
        if !manual, Date().timeIntervalSince1970 - defaults.double(forKey: "lastUpdateCheck") < 6 * 3600 {
            // Still show an update found earlier and not yet installed or skipped.
            if let cached = defaults.data(forKey: "cachedReleases") { apply(cached, current: current, manual: false) }
            return
        }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: Remote.releases)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw DownloadError.http(code, Remote.releases) }
            defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            defaults.set(data, forKey: "cachedReleases")
            apply(data, current: current, manual: manual)
            if manual, available == nil {
                alert(tr("You have the latest version"), tr("Version %@", current))
            }
        } catch {
            if manual { alert(tr("Couldn't check for updates"), error.localizedDescription) }
        }
    }

    private func apply(_ data: Data, current: String, manual: Bool) {
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return }
        // App releases are tagged v1.2, v1.3, …; other releases (pages-v1) are ignored.
        let latest = releases
            .filter { !$0.draft && !$0.prerelease && $0.tag_name.range(of: #"^v\d+(\.\d+)*$"#, options: .regularExpression) != nil }
            .max { Self.compare($0.tag_name, $1.tag_name) < 0 }
        guard let latest, Self.compare(latest.tag_name, current) > 0 else {
            available = nil
            return
        }
        let version = String(latest.tag_name.dropFirst())
        // A version the user chose to skip is only offered again when they check by hand.
        if !manual, UserDefaults.standard.string(forKey: "skippedVersion") == version { return }
        available = Update(version: version, page: latest.html_url,
                           download: latest.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url)
    }

    func download() {
        if let a = available { NSWorkspace.shared.open(a.download ?? a.page) }
        available = nil
    }

    func skip() {
        UserDefaults.standard.set(available?.version, forKey: "skippedVersion")
        available = nil
    }

    func dismiss() { available = nil }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
