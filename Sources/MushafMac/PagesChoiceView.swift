import SwiftUI

/// Offered once after the opening page, and from File → Download Pages: install all pages from GitHub
/// for offline reading, or keep reading online.
struct PagesChoiceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var store: PageStore { model.pageStore }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.appAccent)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 84, height: 84)
                .glassEffect(.regular.tint(Color.appAccent.opacity(0.15)), in: Circle())

            Text(tr("Mushaf Pages")).font(.title2.bold())

            switch store.state {
            case .online, .failed:
                Text(tr("Download all 604 pages (about %d MB) from GitHub to read offline, or read online: each page loads as you open it.", Remote.pagesArchiveMB))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if case let .failed(message) = store.state {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                }
                HStack(spacing: 12) {
                    Button(tr("Read Online")) { choose() }
                        .buttonStyle(.glass)
                    Button(tr("Download (%d MB)", Remote.pagesArchiveMB)) {
                        UserDefaults.standard.set(true, forKey: "pagesChoiceMade")
                        store.install()   // the sheet stays open to show progress
                    }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)

            case let .downloading(fraction):
                ProgressView(value: fraction) {
                    Text(tr("Downloading pages… %d%%", Int(fraction * 100))).monospacedDigit()
                }
                .frame(width: 320)
                Text(tr("You can keep reading online while the pages download.")).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(tr("Cancel Download"), role: .cancel) { store.cancel() }
                        .buttonStyle(.glass)
                    Button(tr("Continue Reading")) { dismiss() }
                        .buttonStyle(.glassProminent)
                }
                .controlSize(.large)

            case .installing:
                ProgressView(tr("Installing pages…")).frame(width: 320)

            case .installed:
                Text(tr("All pages are installed. The mushaf now works offline.")).foregroundStyle(.secondary)
                Button(tr("Done")) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 480)
        .appLayoutDirection()
    }

    private var icon: String {
        switch store.state {
        case .installed: "checkmark.circle"
        case .downloading, .installing: "arrow.down.circle"
        case .online, .failed: "book.pages"
        }
    }

    private func choose() {
        UserDefaults.standard.set(true, forKey: "pagesChoiceMade")
        dismiss()
    }
}
