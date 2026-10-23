import Foundation
import Observation

/// The mushaf pages are not shipped in the app. Users either install all 604 from the GitHub release
/// (one zip) or read online, where each page is fetched from the repository as it is opened.
@MainActor
@Observable
final class PageStore {
    enum State: Equatable {
        case online
        case downloading(Double)   // 0...1
        case installing
        case installed
        case failed(String)
    }

    private(set) var state: State

    private static var marker: URL { Paths.pages.appendingPathComponent(".installed") }
    private var task: Task<Void, Never>?

    var isInstalled: Bool { state == .installed }
    var isBusy: Bool {
        switch state {
        case .downloading, .installing: true
        default: false
        }
    }

    init() {
        state = FileManager.default.fileExists(atPath: Self.marker.path) ? .installed : .online
    }

    func install() {
        guard !isBusy, !isInstalled else { return }
        state = .downloading(0)
        task = Task {
            do {
                let zip = try await ProgressDownload.run(Remote.pagesArchive) { [weak self] fraction in
                    Task { @MainActor in
                        if case .downloading = self?.state { self?.state = .downloading(fraction) }
                    }
                }
                state = .installing
                try await Task.detached { try Self.unpack(zip) }.value
                try? FileManager.default.removeItem(at: zip)
                state = .installed
            } catch is CancellationError {
                state = .online
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .online
    }

    /// Deletes installed pages; reading continues online.
    func remove() {
        guard !isBusy else { return }
        try? FileManager.default.removeItem(at: Paths.pages)
        _ = Paths.pages   // recreates the empty folder
        state = .online
    }

    /// Unzips into a staging folder, checks all 604 pages are present, then moves them into place.
    nonisolated private static func unpack(_ zip: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("QuranReaderHD-pages-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try Downloader.unzip(zip, into: staging)
        let names = (1...Quran.pageCount).map { String(format: "page%03d.png", $0) }
        // The archive may hold the files at its root or inside one folder.
        let root = names.allSatisfy({ fm.fileExists(atPath: staging.appendingPathComponent($0).path) })
            ? staging
            : try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                .first { $0.hasDirectoryPath && fm.fileExists(atPath: $0.appendingPathComponent(names[0]).path) }
                ?? staging
        guard names.allSatisfy({ fm.fileExists(atPath: root.appendingPathComponent($0).path) }) else {
            throw DownloadError.unzip
        }
        let dest = Paths.pages
        for name in names {
            let target = dest.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try fm.moveItem(at: root.appendingPathComponent(name), to: target)
        }
        try Data().write(to: dest.appendingPathComponent(".installed"))
        // Pages now installed don't need their online copies.
        try? fm.removeItem(at: Paths.onlinePages)
    }
}

/// A download that reports progress, for the ~75 MB page archive.
private final class ProgressDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    private init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    static func run(_ url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = ProgressDownload(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: url)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                delegate.continuation = cont
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : Int64(Remote.pagesArchiveMB) * 1_000_000
        onProgress(min(Double(totalBytesWritten) / Double(total), 1))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            continuation?.resume(throwing: DownloadError.http(code, Remote.pagesArchive))
            continuation = nil
            return
        }
        // The temporary file is deleted when this method returns, so move it first.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("QuranReaderHD-Pages-\(UUID().uuidString).zip")
        do {
            try FileManager.default.moveItem(at: location, to: keep)
            continuation?.resume(returning: keep)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        continuation?.resume(throwing: (error as? URLError)?.code == .cancelled ? CancellationError() : error)
        continuation = nil
    }
}
