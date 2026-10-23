import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
        NavigationSplitView {
            SidebarView()
                .appLayoutDirection()
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 360)
        } detail: {
            VStack(spacing: 0) {
                switch model.status {
                case let .loading(message):
                    ProgressView(tr(message)).frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(message):
                    ContentUnavailableView {
                        Label(tr("Couldn't load the mushaf"), systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button(tr("Try Again")) { Task { await model.bootstrap() } }
                    }
                case .ready:
                    Group {
                        switch model.mode {
                        case .mushaf: MushafReader()
                        case .text: TextModeView().appLayoutDirection()
                        }
                    }
                    // Floating Liquid Glass controls; the page background continues underneath them.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 10) {
                            PageSlider()
                            AudioBar()
                        }
                        .appLayoutDirection()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .padding(.top, 6)
                    }
                }
            }
            // Keeps the reading area (and its glass dock) from being squeezed below what the dock needs.
            .frame(minWidth: 460)
            .inspector(isPresented: $model.showInspector) {
                AyahInspector()
                    .appLayoutDirection()
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 520)
            }
        }
        .navigationTitle(model.showDedication ? "" : model.status == .ready ? model.pageTitle(model.page) : tr("Mushaf"))
        .navigationSubtitle(model.status == .ready && !model.showDedication
            ? "\(tr("Juz' %d", model.juz(for: model.page))) · \(AppModel.quarterLabel(model.quarterIndex(for: model.page)))" : "")
        // Hiding the window toolbar here changes safe areas mid-layout and can crash AppKit on macOS 26,
        // so the toolbar stays and only its items are left out while the opening page shows.
        .toolbar { if !model.showDedication { toolbar } }
        .onChange(of: model.audio.current) { _, key in
            if let key { model.go(to: key, select: false) }
        }
        .onOpenURL { model.handle($0) }
        .sheet(isPresented: Binding(get: { model.showHelp }, set: { model.showHelp = $0 })) { HelpView().appLayoutDirection() }
        .onChange(of: model.translationID) { _, id in Task { await model.text.ensure(id) } }
        .onChange(of: model.tafsirID) { _, id in Task { await model.text.ensure(id, sura: model.selected?.sura) } }

            if model.showDedication {
                DedicationView { withAnimation(.easeInOut(duration: 0.5)) { model.showDedication = false } }
                    .appLayoutDirection()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .tint(Color.appAccent)
        // Right-to-left is applied per pane (.appLayoutDirection()), not here: on the NavigationSplitView root it
        // makes AppKit (macOS 26) loop on split-view minimum sizes and abort.
        .environment(\.locale, Locale(identifier: Localizer.shared.language.rawValue))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            // Arabic books open right-to-left: "next" sits on the left, whatever the UI language.
            HStack(spacing: 4) {
                Button { model.turn(forward: true) } label: { Image(systemName: "chevron.left") }
                    .help(tr("Next page"))
                    .disabled(model.page >= Quran.pageCount - (model.dualPage ? 1 : 0))
                PageField()
                Button { model.turn(forward: false) } label: { Image(systemName: "chevron.right") }
                    .help(tr("Previous page"))
                    .disabled(model.page <= (model.dualPage ? 2 : 1))
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        ToolbarItem(placement: .principal) {
            Picker(tr("Mode"), selection: Binding(get: { model.mode }, set: { model.mode = $0 })) {
                ForEach(ReadingMode.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { model.dualPage }, set: { model.dualPage = $0 })) {
                Image(systemName: "book.pages")
            }
            .help(tr("Two-page spread"))
            DisplayButton()
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button { model.setLanguage(lang) } label: {
                        if lang == Localizer.shared.language { Label(lang.nativeName, systemImage: "checkmark") } else { Text(lang.nativeName) }
                    }
                }
            } label: { Image(systemName: "globe") }
            .help(tr("Language"))
            Button { model.library.toggleBookmark(model.page) } label: {
                Image(systemName: model.library.isBookmarked(model.page) ? "bookmark.fill" : "bookmark")
            }
            .help(tr("Bookmark this page"))
            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                .help(tr("Translation, tafsir and notes"))
        }
    }
}

private struct PageField: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""

    var body: some View {
        TextField("Page", text: $text)
            .frame(width: 52)
            .multilineTextAlignment(.center)
            .onSubmit { if let p = Int(text) { model.go(to: p) } else { text = "\(model.page)" } }
            .onAppear { text = "\(model.page)" }
            .onChange(of: model.page) { _, p in text = "\(p)" }
            .help(tr("Go to page (1–604)"))
    }
}

/// Context-menu items shared by the page view and the translation list.
struct AyahMenu: View {
    @Environment(AppModel.self) private var model
    let key: AyahKey

    var body: some View {
        Text(tr("%@ — Ayah %d", model.surahTitle(key.sura), key.ayah))
        Button(tr("Play From Here")) { model.selected = key; model.audio.play(from: key) }
        Button(tr("Play This Ayah Only")) { model.selected = key; model.audio.play(from: key, to: key) }
        Menu(tr("Memorisation Range")) {
            Button(tr("Set as Range Start")) { model.audio.rangeStart = key; model.audio.rangeEnd = max(model.audio.rangeEnd ?? key, key) }
            Button(tr("Set as Range End")) { model.audio.rangeEnd = key; if model.audio.rangeStart.map({ $0 > key }) ?? true { model.audio.rangeStart = key } }
            Button(tr("Play Range")) { model.audio.playRange() }.disabled(model.audio.rangeStart == nil)
        }
        Divider()
        Button(tr("Translation")) { model.showText(.translation, for: key) }
        Button(tr("Tafsir")) { model.showText(.tafsir, for: key) }
        Button(model.library.notes[key] == nil ? "Add Note…" : "Edit Note…") { model.showText(.note, for: key) }
        Divider()
        Button(tr("Copy Arabic Text")) { model.copyArabic(key) }
            .disabled(model.text.text(Edition.arabic.id, key) == nil)
        Button(tr("Copy with Translation")) { model.copyWithTranslation(key) }
            .disabled(model.text.text(Edition.arabic.id, key) == nil)
        ShareLink(tr("Share…"), item: model.shareText(key), subject: Text(model.citation(key)))
        if let page = model.db?.page(of: key) {
            Button(model.library.isBookmarked(page) ? tr("Remove Page Bookmark") : tr("Bookmark Page %d", page)) {
                model.library.toggleBookmark(page)
            }
        }
    }
}

/// The original's brightness window plus page theme and swipe settings.
private struct DisplayButton: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        @Bindable var model = model
        Button { shown.toggle() } label: { Image(systemName: "textformat.size") }
            .help(tr("Page appearance"))
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Form {
                    Picker(tr("Pages"), selection: $model.theme) {
                        ForEach(PageTheme.allCases) { Text(tr($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(tr("Brightness")) {
                        HStack {
                            Image(systemName: "sun.min")
                            Slider(value: $model.brightness, in: 0.35...1)
                            Image(systemName: "sun.max")
                        }
                    }
                    Toggle(tr("Swipe to turn pages"), isOn: $model.swipeEnabled)
                    Toggle(tr("Two-page spread"), isOn: $model.dualPage)
                }
                .formStyle(.grouped)
                .frame(width: 340)
            }
    }
}

/// Jump bar (the original's page slider): page 1 sits on the right, like the book.
struct PageSlider: View {
    @Environment(AppModel.self) private var model
    @State private var dragValue: Double?

    var body: some View {
        let shown = Int(dragValue ?? Double(model.page))
        // Constant, small minimum width: the label truncates (see AudioBar for why this matters).
        HStack(spacing: 12) {
            Text(label(for: shown))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: 300, alignment: .leading)
                .layoutPriority(-1)
            scrubber.frame(minWidth: 80)
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
        .glassEffect(.regular, in: Capsule())
    }

    private var scrubber: some View {
        PageScrubber(value: dragValue ?? Double(model.page),
                     onChange: { dragValue = $0 },
                     onEnd: { if let v = dragValue { model.go(to: Int(v)) }; dragValue = nil })
    }

    private func label(for page: Int) -> String {
        let sura = model.firstAyah(on: page).map { model.surahName($0.sura) } ?? ""
        return "\(tr("Page %d", page)) · \(sura) · \(tr("Juz' %d", model.juz(for: page))) · \(AppModel.quarterLabel(model.quarterIndex(for: page)))"
    }
}

/// SwiftUI page scrubber: page 1 at the right edge, like the book. Drawn by hand rather than with
/// Slider, whose AppKit control loops on layout in this window when linked against macOS 26.
private struct PageScrubber: View {
    let value: Double
    let onChange: (Double) -> Void
    let onEnd: () -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fraction = (value - 1) / Double(Quran.pageCount - 1)
            let x = w - CGFloat(fraction) * w          // right-to-left
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12)).frame(height: 5)
                Capsule().fill(Color.appAccent.opacity(0.85))
                    .frame(width: max(w - x, 0), height: 5)
                    .offset(x: x)
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .offset(x: min(max(x - 8, 0), w - 16))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    let f = 1 - min(max(g.location.x / w, 0), 1)
                    onChange((1 + f * Double(Quran.pageCount - 1)).rounded())
                }
                .onEnded { _ in onEnd() })
        }
        .frame(height: 20)
        // Positions are computed right-to-left by hand; don't let an Arabic environment mirror them again.
        .environment(\.layoutDirection, .leftToRight)
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let tips: [(String, String)] = [
        ("hand.tap", "Click an ayah to select it and see its translation, tafsir and note. Double-click to recite from it."),
        ("contextualmenu.and.cursorarrow", "Right-click an ayah for the menu: play, memorisation range, translation, tafsir, note, copy and share."),
        ("bookmark", "Tap the tassel at the top of a page to bookmark it. Tap it again to remove the bookmark."),
        ("arrow.left.arrow.right", "Use the ← → keys, the toolbar arrows or a two-finger swipe to turn pages. Swiping can be turned off under Page Appearance."),
        ("slider.horizontal.below.rectangle", "Drag the slider below the page to jump anywhere; it shows the surah, juz' and hizb."),
        ("repeat", "In the recitation options, repeat each ayah or the whole selection (up to ∞) and pick a stopping point with Play To."),
        ("note.text", "Notes appear as yellow tabs in the page margin. Export them with your bookmarks from the File menu, as HTML, JSON or by email."),
        ("magnifyingglass", "The Search tab finds words in the Arabic text, with or without diacritics, or in the translation."),
        ("link", "Links like mushaf://ayah/2/255 or mushaf://page/50 open the app at that place."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Using Mushaf")).font(.title2.bold())
            ForEach(tips, id: \.1) { icon, text in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon).frame(width: 22).foregroundStyle(.tint)
                    Text(tr(text)).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack { Spacer(); Button(tr("Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 520)
    }
}
