import SwiftUI

struct AudioBar: View {
    @Environment(AppModel.self) private var model
    @State private var showOptions = false

    private var rangeStartBinding: Binding<AyahKey> {
        Binding(get: { model.audio.rangeStart ?? model.selected ?? model.firstAyah(on: model.page) ?? AyahKey(1, 1) },
                set: { model.audio.rangeStart = $0; if let e = model.audio.rangeEnd, e < $0 { model.audio.rangeEnd = $0 } })
    }

    private var rangeEndBinding: Binding<AyahKey> {
        Binding(get: { model.audio.rangeEnd ?? rangeStartBinding.wrappedValue },
                set: { model.audio.rangeEnd = $0; if rangeStartBinding.wrappedValue > $0 { model.audio.rangeStart = $0 } })
    }

    private func optionsSummary(_ audio: AudioController) -> String {
        let reciter = AudioController.reciters.first { $0.id == audio.reciter }?.localizedName ?? audio.reciter
        var parts = [reciter]
        if audio.verseRepeat > 1 { parts.append("\(tr("Ayah")) \(AudioController.repeatLabel(audio.verseRepeat))") }
        if audio.rangeRepeat > 1 { parts.append("\(tr("Repeat selection")) \(AudioController.repeatLabel(audio.rangeRepeat))") }
        return parts.joined(separator: " · ")
    }

    /// Pause/resume if something is loaded; otherwise start from the selection or the top of the page.
    @MainActor
    static func playPause(_ model: AppModel) {
        if model.audio.isActive { return model.audio.togglePause() }
        let start = model.selected ?? model.visiblePages.compactMap { model.firstAyah(on: $0) }.min()
        if let start { model.audio.play(from: start) }
    }

    var body: some View {
        // Liquid Glass dock. Its minimum width must be small and constant: the split view re-lays out whenever
        // a child's minimum size changes, and on macOS 26 a growing or flip-flopping minimum (ViewThatFits,
        // fixed-width labels) loops until AppKit aborts. Only the buttons are fixed; every text truncates.
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                transport
                nowPlaying
                Spacer(minLength: 4)
                rangeChip
                optionsButton
            }
        }
        .popover(isPresented: $showOptions, arrowEdge: .top) { optionsForm }
        .onChange(of: model.audio.reciter) { _, _ in
            if let c = model.audio.current { model.audio.play(from: c) }
        }
    }

    private var transport: some View {
        let audio = model.audio
        return HStack(spacing: 6) {
            Button { audio.skip(false) } label: { Image(systemName: "backward.fill") }
                .disabled(!audio.isActive).help(tr("Previous ayah"))
            Button { Self.playPause(model) } label: {
                Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glassProminent)
            .help(tr(audio.isPlaying ? "Pause" : "Play"))
            Button { audio.skip(true) } label: { Image(systemName: "forward.fill") }
                .disabled(!audio.isActive).help(tr("Next ayah"))
            Button { audio.stop() } label: { Image(systemName: "stop.fill") }
                .disabled(!audio.isActive).help(tr("Stop"))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .fixedSize()
    }

    private var nowPlaying: some View {
        let audio = model.audio
        return Group {
            if let err = audio.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            } else if let key = audio.current {
                HStack(spacing: 8) {
                    if audio.isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: audio.isPlaying) }
                    Text("\(model.surahTitle(key.sura)) · \(key.description)").monospacedDigit()
                }
            } else {
                Text(tr("Double-click an ayah to recite")).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(minWidth: 0, maxWidth: 340, minHeight: 40, maxHeight: 40)
        .layoutPriority(-1)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private var rangeChip: some View {
        let audio = model.audio
        if let s = audio.rangeStart {
            HStack(spacing: 6) {
                Button(tr("Range %@–%@", s.description, (audio.rangeEnd ?? s).description)) { audio.playRange() }
                    .buttonStyle(.plain)
                    .help(tr("Play the memorisation range"))
                Button { audio.rangeStart = nil; audio.rangeEnd = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minWidth: 0, minHeight: 40, maxHeight: 40)
            .layoutPriority(-2)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    private var optionsButton: some View {
        Button { showOptions.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                Text(optionsSummary(model.audio)).lineLimit(1).frame(minWidth: 0, maxWidth: 240)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .layoutPriority(-1)
        .help(tr("Reciter, scope and repeat"))
    }

    private var optionsForm: some View {
        @Bindable var audio = model.audio
        return Form {
            Picker(tr("Reciter"), selection: $audio.reciter) {
                ForEach(AudioController.reciters) { Text($0.localizedName).tag($0.id) }
            }
            Picker(tr("Play"), selection: $audio.scope) {
                ForEach(AudioController.Scope.allCases) { Text(tr($0.rawValue)).tag($0) }
            }
            Picker(tr("Repeat each ayah"), selection: $audio.verseRepeat) {
                ForEach(AudioController.repeatChoices, id: \.self) { Text(AudioController.repeatLabel($0)).tag($0) }
            }
            Picker(tr("Repeat selection"), selection: $audio.rangeRepeat) {
                ForEach(AudioController.repeatChoices, id: \.self) { Text(AudioController.repeatLabel($0)).tag($0) }
            }
            Section(tr("Play To — choose a stopping point")) {
                AyahPicker(label: "From", key: rangeStartBinding)
                AyahPicker(label: "To", key: rangeEndBinding)
                Button(tr("Play Selection")) {
                    // From may still be showing its default (selection or page start), so commit both ends.
                    let from = rangeStartBinding.wrappedValue, to = rangeEndBinding.wrappedValue
                    audio.rangeStart = from
                    audio.rangeEnd = to
                    audio.play(from: from, to: to)
                    showOptions = false
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}

/// Surah + ayah chooser for the Play To range.
struct AyahPicker: View {
    @Environment(AppModel.self) private var model
    let label: String
    @Binding var key: AyahKey

    var body: some View {
        let count = model.db?.ayahCounts[key.sura] ?? 1
        HStack(spacing: 6) {
            Text(tr(label))
            Spacer(minLength: 4)
            Picker(tr("Surah"), selection: Binding(get: { key.sura }, set: { key = AyahKey($0, 1) })) {
                ForEach(1...114, id: \.self) { n in Text(model.surahTitle(n)).tag(n) }
            }
            .labelsHidden()
            .frame(width: 160)
            Picker(tr("Ayah"), selection: Binding(get: { key.ayah }, set: { key = AyahKey(key.sura, $0) })) {
                ForEach(1...max(count, 1), id: \.self) { Text(tr("Ayah %d", $0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 96)
        }
    }
}
