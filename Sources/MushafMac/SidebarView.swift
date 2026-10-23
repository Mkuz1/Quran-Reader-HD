import SwiftUI

struct SidebarView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case surahs = "Surahs", juz = "Juz", search = "Search", bookmarks = "Marks", notes = "Notes"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .surahs: "list.bullet"
            case .juz: "square.split.2x2"
            case .search: "magnifyingglass"
            case .bookmarks: "bookmark"
            case .notes: "note.text"
            }
        }
    }

    enum BookmarkSort: String, CaseIterable, Identifiable {
        case page = "Page", date = "Date"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("sidebarTab") private var tab: Tab = .surahs
    @AppStorage("bookmarkSort") private var bookmarkSort: BookmarkSort = .page
    @State private var query = ""
    @State private var searchLimit = 50
    @State private var renaming: Bookmark?
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .padding(8)
            .help(tr(tab.rawValue))

            List {
                switch tab {
                case .surahs: surahs
                case .juz: juzAndHizb
                case .search: search
                case .bookmarks: bookmarks
                case .notes: notes
                }
            }
            .listStyle(.sidebar)

            if let progress = model.offlineProgress {
                ProgressView(value: progress) {
                    Text(tr("Downloading pages for offline use…")).font(.caption)
                }
                .padding(10)
            }
        }
        .searchable(text: $query, placement: .sidebar,
                    prompt: tab == .search ? tr("Arabic or translation text") : tr("Surah name or number"))
        .searchSuggestions {
            if tab == .search {
                ForEach(model.text.suggestions(for: query), id: \.self) { word in
                    Text(word).searchCompletion(word)
                }
            }
        }
        .onChange(of: query) { _, _ in searchLimit = 50 }
        .alert("Rename Bookmark", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button(tr("Save")) { if let b = renaming { model.library.rename(b, to: newTitle) } }
            Button(tr("Cancel"), role: .cancel) {}
        }
    }

    private var currentSura: Int? { model.firstAyah(on: model.page)?.sura }

    // MARK: Surahs

    @ViewBuilder
    private var surahs: some View {
        let list = (model.meta?.surahs ?? []).filter { s in
            query.isEmpty || "\(s.number)" == query
                || s.englishName.localizedCaseInsensitiveContains(query)
                || s.englishNameTranslation.localizedCaseInsensitiveContains(query)
                || Arabic.normalize(s.name).contains(Arabic.normalize(query))
        }
        if model.meta == nil {
            Text(tr("Loading surah list…")).foregroundStyle(.secondary)
        }
        ForEach(list) { s in
            Button { model.go(to: model.startPage(sura: s.number)) } label: {
                HStack(spacing: 10) {
                    Text("\(s.number)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().strokeBorder(.secondary.opacity(0.5)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.surahName(s.number)).fontWeight(.medium)
                        Text("\(tr(s.revelationType == "Meccan" ? "Makki" : "Madani")) · \(tr("%d verses", s.numberOfAyahs)) · \(tr("Page %d", model.startPage(sura: s.number)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(s.name).font(.system(size: 15))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(currentSura == s.number ? Color.accentColor.opacity(0.15) : nil)
        }
    }

    // MARK: Juz & Hizb (the original's combined index)

    @ViewBuilder
    private var juzAndHizb: some View {
        let quarters = model.meta?.quarterStarts ?? []
        let currentQuarter = model.quarterIndex(for: model.page)
        ForEach(0..<(quarters.count / 8), id: \.self) { juz in
            Section(tr("Juz' %d", juz + 1)) {
                ForEach(juz * 8..<(juz * 8 + 8), id: \.self) { q in
                    let key = quarters[q]
                    let page = model.db?.page(of: key) ?? 1
                    Button { model.go(to: key) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Text(["●", "¼", "½", "¾"][q % 4])
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.frameGold)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.snippet(key))
                                    .font(.custom("Geeza Pro", size: 14))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .environment(\.layoutDirection, .rightToLeft)
                                Text("\(AppModel.quarterLabel(q)) · \(model.surahName(key.sura)) \(key.description) · \(tr("Page %d", page))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(currentQuarter == q ? Color.accentColor.opacity(0.15) : nil)
                }
            }
        }
        if quarters.isEmpty {
            Text(tr("Loading index…")).foregroundStyle(.secondary)
        }
    }

    // MARK: Search

    @ViewBuilder
    private var search: some View {
        let result = model.text.search(query, translation: model.translationID, limit: searchLimit)
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            Text(tr("Search the Arabic text (without needing diacritics) or the %@ translation.", Edition.named(model.translationID).title))
                .font(.callout).foregroundStyle(.secondary)
        } else if result.hits.isEmpty {
            Text(model.text.texts[Edition.arabicSearch.id] == nil ? "Searching…" : "No results")
                .foregroundStyle(.secondary)
        } else {
            Section(tr("%@ results", "\(result.hits.count)\(result.more ? "+" : "")")) {
                ForEach(result.hits) { hit in
                    Button { model.go(to: hit.key) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(model.surahName(hit.key.sura)) : \(hit.key.ayah) · \(tr("Page %d", model.db?.page(of: hit.key) ?? 0))")
                                .font(.caption.weight(.semibold))
                            if hit.edition == Edition.arabicSearch.id {
                                Text(model.text.text(Edition.arabic.id, hit.key) ?? "")
                                    .font(.custom("Geeza Pro", size: 14)).lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .environment(\.layoutDirection, .rightToLeft)
                            } else {
                                Text(model.text.text(hit.edition, hit.key) ?? "").font(.caption).lineLimit(3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if result.more {
                    Button(tr("Show more results…")) { searchLimit += 50 }
                }
            }
        }
    }

    // MARK: Bookmarks & notes

    @ViewBuilder
    private var bookmarks: some View {
        if model.library.bookmarks.isEmpty {
            Text(tr("Tap the tassel at the top of a page to bookmark it."))
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Picker(tr("Sort by"), selection: $bookmarkSort) {
                ForEach(BookmarkSort.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        let sorted = model.library.bookmarks.sorted {
            bookmarkSort == .page ? $0.page < $1.page : $0.created > $1.created
        }
        ForEach(sorted) { b in
            Button { model.go(to: b.page) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.title ?? model.pageTitle(b.page)).fontWeight(.medium)
                    Text("\(tr("Page %d", b.page)) · \(b.created.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(tr("Rename…")) { newTitle = b.title ?? model.pageTitle(b.page); renaming = b }
                Button(tr("Remove Bookmark"), role: .destructive) { model.library.removeBookmark(b) }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        if model.library.notes.isEmpty {
            Text(tr("Right-click an ayah and choose Add Note."))
                .font(.callout).foregroundStyle(.secondary)
        }
        ForEach(model.library.notes.keys.sorted(), id: \.self) { key in
            Button {
                model.go(to: key)
                model.showText(.note, for: key)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.surahTitle(key.sura)) · \(key.description)").fontWeight(.medium)
                    Text(model.library.notes[key]?.text ?? "").font(.caption).lineLimit(2).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(tr("Delete Note"), role: .destructive) { model.library.setNote("", for: key) }
            }
        }
    }
}
