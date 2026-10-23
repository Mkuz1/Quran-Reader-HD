import SwiftUI

/// Translation/tafsir-only mode: the current surah as a scrolling list of ayahs.
struct TextModeView: View {
    @Environment(AppModel.self) private var model
    @State private var showTafsir = false

    private var sura: Int { model.firstAyah(on: model.page)?.sura ?? 1 }

    var body: some View {
        let count = model.db?.ayahCounts[sura] ?? 0
        VStack(spacing: 0) {
            HStack {
                Button { jump(sura - 1) } label: { Image(systemName: "chevron.left") }.disabled(sura <= 1)
                VStack(spacing: 0) {
                    Text(model.surahTitle(sura)).font(.headline)
                    if let s = model.surah(sura) {
                        Text("\(Localizer.shared.language == .arabic ? s.englishName : s.englishNameTranslation) · \(tr(s.revelationType == "Meccan" ? "Makki" : "Madani")) · \(tr("%d verses", s.numberOfAyahs))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                Button { jump(sura + 1) } label: { Image(systemName: "chevron.right") }.disabled(sura >= 114)
                Picker(tr("Show"), selection: Binding(get: { model.studyDisplay }, set: { model.studyDisplay = $0 })) {
                    ForEach(StudyDisplay.allCases) { Text(tr($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Toggle(tr("Tafsir"), isOn: $showTafsir).toggleStyle(.switch).controlSize(.small)
            }
            .buttonStyle(.borderless)
            .padding(10)
            Divider()
            ScrollViewReader { proxy in
                List(1...max(count, 1), id: \.self) { ayah in
                    row(AyahKey(sura, ayah)).id(ayah)
                }
                .listStyle(.inset)
                .onChange(of: model.audio.current) { _, key in
                    if let key, key.sura == sura { withAnimation { proxy.scrollTo(key.ayah, anchor: .center) } }
                }
                .onAppear {
                    if let s = model.selected, s.sura == sura { proxy.scrollTo(s.ayah, anchor: .top) }
                }
            }
        }
        .background(Color.paper)
        .task(id: model.translationID) { await model.text.ensure(model.translationID) }
        .task(id: "\(showTafsir)-\(model.tafsirID)-\(sura)") { if showTafsir { await model.text.ensure(model.tafsirID, sura: sura) } }
    }

    private func jump(_ n: Int) {
        model.go(to: model.startPage(sura: n))
    }

    private func row(_ key: AyahKey) -> some View {
        let active = model.audio.current == key
        let translation = Edition.named(model.translationID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(key.description).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if model.studyDisplay != .translation {
                    ArabicText(text: model.text.text(Edition.arabic.id, key), size: 22)
                } else { Spacer() }
            }
            if model.studyDisplay != .arabic, let t = model.text.text(model.translationID, key) {
                if translation.isRTL { ArabicText(text: t, size: 16) } else { Text(t).textSelection(.enabled) }
            }
            if showTafsir, let t = model.text.text(model.tafsirID, key) {
                if Edition.named(model.tafsirID).isRTL { ArabicText(text: t, size: 15).foregroundStyle(.secondary) }
                else { Text(t).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            if let note = model.library.notes[key] {
                Label(note.text, systemImage: "note.text").font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(active ? Color.green.opacity(0.15) : model.selected == key ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.selected = key; model.audio.play(from: key) }
        .onTapGesture { model.selected = key }
        .contextMenu { AyahMenu(key: key) }
    }
}
