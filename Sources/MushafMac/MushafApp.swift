import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (swift run) rather than from the .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Not quitting after the last window closes: at launch the system's "reopen windows?" alert can be the
    // only window, and quitting when it closes would end the app before the main window appears.
}

@main
struct MushafApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Mushaf") {
            ContentView()
                .environment(model)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .frame(minWidth: 820, minHeight: 600)
                .task {
                    await model.bootstrap()
                    await model.updates.check()
                }
        }
        .defaultSize(width: 1280, height: 900)
        .commands { AppCommands(model: model) }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button(tr("Export Notes & Bookmarks as HTML…")) { model.exportHTMLWithPanel() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button(tr("Export Notes & Bookmarks as JSON…")) { model.library.exportWithPanel() }
            Button(tr("Email Notes & Bookmarks…")) { model.emailNotes() }
            Button(tr("Import Notes & Bookmarks…")) { model.library.importWithPanel() }
            Divider()
            if model.pageStore.isInstalled {
                Button(tr("Remove Downloaded Pages")) { model.pageStore.remove() }
            } else {
                Button(tr("Download Pages for Offline Reading…")) { model.showPagesChoice = true }
            }
        }
        CommandGroup(replacing: .help) {
            Button(tr("Mushaf Help")) { model.showHelp = true }
                .keyboardShortcut("?", modifiers: [.command])
            Button(tr("About This Sadaqa Jariyah")) { withAnimation { model.showDedication = true } }
            Button(tr("Check for Updates…")) { Task { await model.updates.check(manual: true) } }
            Divider()
            Picker(tr("Language"), selection: Binding(get: { Localizer.shared.language }, set: { model.setLanguage($0) })) {
                ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
            }
        }
        CommandMenu(tr("Navigate")) {
            Button(tr("Next Page")) { model.turn(forward: true) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button(tr("Previous Page")) { model.turn(forward: false) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Divider()
            Button(model.library.isBookmarked(model.page) ? "Remove Bookmark" : "Bookmark This Page") {
                model.library.toggleBookmark(model.page, title: model.pageTitle(model.page))
            }
            .keyboardShortcut("b")
            Toggle(tr("Two-Page Spread"), isOn: Binding(get: { model.dualPage }, set: { model.dualPage = $0 }))
                .keyboardShortcut("2", modifiers: [.command, .option])
            Toggle(tr("Swipe to Turn Pages"), isOn: Binding(get: { model.swipeEnabled }, set: { model.swipeEnabled = $0 }))
            Picker(tr("Page Theme"), selection: Binding(get: { model.theme }, set: { model.theme = $0 })) {
                ForEach(PageTheme.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
            Picker(tr("Reading Mode"), selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                ForEach(ReadingMode.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
        }
        CommandMenu(tr("Recitation")) {
            Button(model.audio.isPlaying ? "Pause" : "Play") { AudioBar.playPause(model) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button(tr("Stop")) { model.audio.stop() }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.audio.isActive)
            Button(tr("Next Ayah")) { model.audio.skip(true) }
                .disabled(!model.audio.isActive)
            Button(tr("Previous Ayah")) { model.audio.skip(false) }
                .disabled(!model.audio.isActive)
        }
    }
}
