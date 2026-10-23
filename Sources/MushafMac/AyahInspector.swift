import SwiftUI

struct AyahInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let key = model.selected {
                VStack(alignment: .leading, spacing: 12) {
                    header(key)
                    ArabicText(text: model.text.text(Edition.arabic.id, key), size: 24)
                    Picker("", selection: $model.inspectorTab) {
                        ForEach(InspectorTab.allCases) { Text(tr($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch model.inspectorTab {
                    case .translation: EditionText(key: key, editionID: $model.translationID, choices: Edition.translations)
                    case .tafsir: EditionText(key: key, editionID: $model.tafsirID, choices: Edition.tafsirs)
                    case .note: NoteEditor(key: key).id(key)
                    }
                }
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ContentUnavailableView(tr("No Ayah Selected"), systemImage: "hand.tap",
                                       description: Text(tr("Click an ayah on the page to see its translation, tafsir and your notes.")))
            }
        }
        .task(id: model.inspectorTab) {
            await model.text.ensure(model.inspectorTab == .tafsir ? model.tafsirID : model.translationID, sura: model.selected?.sura)
        }
    }

    private func header(_ key: AyahKey) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.surahTitle(key.sura)).font(.headline)
                Text(tr("Ayah %d", key.ayah)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.audio.play(from: key, to: key) } label: { Image(systemName: "play.circle") }
                .help(tr("Recite this ayah"))
            Button { model.copyArabic(key) } label: { Image(systemName: "doc.on.doc") }
                .help(tr("Copy Arabic text"))
            ShareLink(item: model.shareText(key), subject: Text(model.citation(key))) { Image(systemName: "square.and.arrow.up") }
                .help(tr("Share this ayah"))
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }
}

struct ArabicText: View {
    let text: String?
    var size: CGFloat = 22

    var body: some View {
        Text(text ?? "…")
            .font(.custom("Geeza Pro", size: size))
            .lineSpacing(size * 0.4)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .environment(\.layoutDirection, .rightToLeft)
            .textSelection(.enabled)
    }
}

private struct EditionText: View {
    @Environment(AppModel.self) private var model
    let key: AyahKey
    @Binding var editionID: String
    let choices: [Edition]

    var body: some View {
        let edition = Edition.named(editionID)
        VStack(alignment: .leading, spacing: 8) {
            Picker(tr("Source"), selection: $editionID) {
                ForEach(choices) { Text($0.title).tag($0.id) }
            }
            ScrollView {
                if let t = model.text.text(editionID, key) {
                    if edition.isRTL { ArabicText(text: t, size: 17) }
                    else { Text(t).font(.body).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                } else if let err = model.text.errors[editionID] {
                    Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else {
                    ProgressView(tr("Downloading %@…", edition.title)).frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
        }
        .task(id: "\(editionID)-\(key.sura)") { await model.text.ensure(editionID, sura: key.sura) }
    }
}

private struct NoteEditor: View {
    @Environment(AppModel.self) private var model
    let key: AyahKey
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
            if let n = model.library.notes[key] {
                Text(tr("Saved %@", n.updated.formatted(date: .abbreviated, time: .shortened)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { draft = model.library.notes[key]?.text ?? "" }
        .onChange(of: draft) { _, text in model.library.setNote(text, for: key) }
    }
}
