import AVFoundation
import Foundation
import Observation

/// Verse-by-verse recitation with per-verse and per-range repeat, for memorisation.
@MainActor
@Observable
final class AudioController {
    enum Scope: String, CaseIterable, Identifiable {
        case ayah = "This ayah"
        case surah = "To end of surah"
        case quran = "Continue through Quran"
        var id: String { rawValue }
    }

    struct Reciter: Identifiable, Hashable {
        let id: String   // EveryAyah folder name
        let name: String
        let arabicName: String
        var localizedName: String { Localizer.shared.language == .arabic ? arabicName : name }
    }

    static let reciters = [
        Reciter(id: "Abdul_Basit_Murattal_192kbps", name: "Abdul Basit — Murattal", arabicName: "عبد الباسط عبد الصمد — مرتل"),
        Reciter(id: "Abdul_Basit_Mujawwad_128kbps", name: "Abdul Basit — Mujawwad", arabicName: "عبد الباسط عبد الصمد — مجود"),
        Reciter(id: "Husary_128kbps", name: "Mahmoud Khalil Al-Husary", arabicName: "محمود خليل الحصري"),
        Reciter(id: "Minshawy_Murattal_128kbps", name: "Al-Minshawi — Murattal", arabicName: "محمد صديق المنشاوي — مرتل"),
        Reciter(id: "Alafasy_128kbps", name: "Mishary Alafasy", arabicName: "مشاري راشد العفاسي"),
        Reciter(id: "Salaah_AbdulRahman_Bukhatir_128kbps", name: "Salah Bukhatir", arabicName: "صلاح بو خاطر"),
    ]

    var reciter: String = UserDefaults.standard.string(forKey: "reciter") ?? reciters[0].id {
        didSet { UserDefaults.standard.set(reciter, forKey: "reciter") }
    }
    var scope: Scope = .surah
    /// Repeat counts; Int.max loops until stopped (the original's ∞ loop mode).
    var verseRepeat = 1
    var rangeRepeat = 1
    static let repeatChoices = [1, 2, 3, 5, 7, 10, Int.max]
    static func repeatLabel(_ n: Int) -> String { n == Int.max ? "∞" : n == 1 ? tr("Once") : "\(n)×" }
    var rangeStart: AyahKey?
    var rangeEnd: AyahKey?

    private(set) var current: AyahKey?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var db: GlyphDB?

    private let player = AVPlayer()
    private var start = AyahKey(1, 1)
    private var end: AyahKey?          // nil: run to the end of the Quran
    private var verseCount = 0
    private var rangeCount = 0
    private var inBismillah = false
    private var generation = 0
    private var endObserver: NSObjectProtocol?

    var isActive: Bool { current != nil }

    // MARK: Controls

    /// Starts at `key`. Without an explicit `end`, the current scope decides where to stop.
    func play(from key: AyahKey, to explicitEnd: AyahKey? = nil) {
        guard let db else { return }
        start = key
        if let explicitEnd {
            end = max(explicitEnd, key)
        } else {
            switch scope {
            case .ayah: end = key
            case .surah: end = AyahKey(key.sura, db.ayahCounts[key.sura])
            case .quran: end = nil
            }
        }
        verseCount = 0
        rangeCount = 0
        load(key, withBismillah: true)
    }

    func playRange() {
        guard let s = rangeStart else { return }
        play(from: s, to: rangeEnd ?? s)
    }

    func togglePause() {
        guard current != nil else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func stop() {
        generation += 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
        isLoading = false
        inBismillah = false
    }

    func skip(_ forward: Bool) {
        guard let c = current, let db,
              let target = forward ? db.next(after: c) : db.previous(before: c) else { return }
        verseCount = 0
        if let e = end, target > e { end = target }
        if target < start { start = target }
        load(target, withBismillah: true)
    }

    // MARK: Playback

    private func load(_ key: AyahKey, withBismillah: Bool) {
        generation += 1
        let gen = generation
        current = key
        errorMessage = nil
        // Every surah except Al-Fatiha (where it is ayah 1) and At-Tawbah opens with the basmala.
        let bismillah = withBismillah && key.ayah == 1 && key.sura != 1 && key.sura != 9
        inBismillah = bismillah
        let fileKey = bismillah ? AyahKey(1, 1) : key
        isLoading = true
        Task {
            do {
                let url = try await file(for: fileKey)
                guard gen == generation else { return }
                startItem(url)
                prefetch(after: key)
            } catch {
                guard gen == generation else { return }
                errorMessage = error.localizedDescription
                stop()
            }
        }
    }

    private func startItem(_ url: URL) {
        let item = AVPlayerItem(url: url)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemFinished() }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        isLoading = false
    }

    private func itemFinished() {
        guard let c = current, let db else { return }
        if inBismillah { return load(c, withBismillah: false) }
        verseCount += 1
        if verseCount < verseRepeat { return load(c, withBismillah: false) }
        verseCount = 0
        let next = db.next(after: c)
        if next == nil || (end.map { c >= $0 } ?? false) {
            rangeCount += 1
            if rangeCount < rangeRepeat { return load(start, withBismillah: true) }
            return stop()
        }
        load(next!, withBismillah: true)
    }

    private func file(for key: AyahKey) async throws -> URL {
        let dest = Paths.audio(reciter).appendingPathComponent(String(format: "%03d%03d.mp3", key.sura, key.ayah))
        return try await Downloader.fetch(Remote.audio(reciter, key), to: dest)
    }

    private func prefetch(after key: AyahKey) {
        guard let db else { return }
        var keys: [AyahKey] = []
        var k = key
        for _ in 0..<3 {
            guard let n = db.next(after: k) else { break }
            keys.append(n)
            k = n
        }
        Task {
            for key in keys { _ = try? await file(for: key) }
        }
    }
}
