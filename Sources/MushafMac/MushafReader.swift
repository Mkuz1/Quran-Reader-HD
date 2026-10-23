import AppKit
import SwiftUI

extension Color {
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.10, alpha: 1)
            : NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.91, alpha: 1)
    })
    static let parchment = Color(red: 0.96, green: 0.91, blue: 0.79)
    static let parchmentDesk = Color(red: 0.80, green: 0.72, blue: 0.58)
    static let night = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let frameGold = Color(red: 0.69, green: 0.54, blue: 0.24)
    static let frameGreen = Color(red: 0.24, green: 0.42, blue: 0.29)
    static let allahRed = Color(red: 0.78, green: 0.13, blue: 0.10)
    /// App accent: the emerald of the icon and the opening page.
    static let appAccent = Color(red: 0.05, green: 0.47, blue: 0.36)
}

extension AppModel {
    /// Night is forced; Classic follows the system appearance.
    func invertsInk(_ scheme: ColorScheme) -> Bool {
        theme == .night || (theme == .classic && scheme == .dark)
    }
}

/// One page or a two-page spread, with a slide transition when turning.
struct MushafReader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focused: Bool
    @State private var swipe = SwipeMonitor()

    var body: some View {
        let pages = model.visiblePages
        HStack(spacing: model.theme == .coloured ? 6 : 0) {
            // visiblePages is [right, left]; lay out left-to-right on screen.
            ForEach(pages.reversed(), id: \.self) { p in
                PageView(page: p, outerEdgeIsRight: !(pages.count == 2 && p == pages.last))
                if model.dualPage, model.theme != .coloured, p == pages.last, pages.count == 2 {
                    Rectangle().fill(.black.opacity(0.12)).frame(width: 1).padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(pages.first)
        .transition(.push(from: model.turningForward ? .leading : .trailing))
        .background(background)
        .overlay {
            // The original's brightness control: dims the page without touching the app chrome.
            Color.black.opacity((1 - model.brightness) * 0.75).allowsHitTesting(false)
        }
        .clipped()
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            focused = true
            swipe.start { forward in
                guard model.swipeEnabled, model.mode == .mushaf else { return }
                model.turn(forward: forward)
            }
        }
        .onDisappear { swipe.stop() }
        .onKeyPress(.leftArrow) { model.turn(forward: true); return .handled }
        .onKeyPress(.rightArrow) { model.turn(forward: false); return .handled }
        .onKeyPress(.space) { AudioBar.playPause(model); return .handled }
        .onKeyPress(.escape) { model.selected = nil; return .handled }
        // The spread is laid out in book order; don't let an Arabic UI mirror it.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var background: Color {
        switch model.theme {
        case .classic: .paper
        case .coloured: scheme == .dark ? Color(red: 0.25, green: 0.21, blue: 0.16) : .parchmentDesk
        case .night: .night
        }
    }
}

struct PageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let page: Int
    /// Side of the page facing away from the spine: where the tassel hangs and note tabs sit.
    let outerEdgeIsRight: Bool
    @State private var image: NSImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image {
                framed(
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(Quran.pageImageSize, contentMode: .fit)
                        .modifier(InkForScheme(dark: model.invertsInk(scheme)))
                        .overlay { allahLayer(image) }
                        .overlay { GeometryReader { geo in interactionLayer(size: geo.size) } }
                        .overlay { GeometryReader { geo in noteTabs(size: geo.size) } }
                )
                .overlay(alignment: outerEdgeIsRight ? .topTrailing : .topLeading) { tassel }
            } else if let error {
                VStack(spacing: 8) {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Button(tr("Retry")) { Task { await load() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            Text(page, format: .number).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .offset(y: 12)
        }
        .task(id: page) { await load() }
        .task(id: "\(page)-\(model.theme.rawValue)") {
            if model.theme == .coloured, let db = model.db {
                let counts = Dictionary(uniqueKeysWithValues: db.ayahs(page: page).map { ($0, db.glyphTotal($0)) })
                await model.words.ensure(page, glyphCounts: counts)
            }
        }
    }

    /// Coloured theme: parchment page inside a gold-and-green double rule, like a printed colour mushaf.
    @ViewBuilder
    private func framed<V: View>(_ content: V) -> some View {
        if model.theme == .coloured {
            content
                .padding(14)
                .background(Color.parchment)
                .overlay(Rectangle().strokeBorder(Color.frameGold, lineWidth: 3))
                .overlay(Rectangle().strokeBorder(Color.frameGreen, lineWidth: 1).padding(6))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .aspectRatio(contentMode: .fit)
        } else {
            content
        }
    }

    private func load() async {
        image = model.images.cached(page)
        if image != nil { return }
        error = nil
        do { image = try await model.images.image(page) }
        catch { self.error = error.localizedDescription }
    }

    private func toImage(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * Quran.pageImageSize.width / size.width,
                y: p.y * Quran.pageImageSize.height / size.height)
    }

    private func toView(_ r: CGRect, _ size: CGSize) -> CGRect {
        let sx = size.width / Quran.pageImageSize.width
        let sy = size.height / Quran.pageImageSize.height
        return CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy)
    }

    // MARK: Layers

    /// Recolours each name of Allah: the page's own ink (its alpha) drawn in red, masked to those words.
    @ViewBuilder
    private func allahLayer(_ image: NSImage) -> some View {
        if model.theme == .coloured, let refs = model.words.allahWords[page], let db = model.db {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color.allahRed)
                .mask {
                    Canvas { ctx, size in
                        for g in db.glyphs(page: page) where refs.contains(WordRef(key: g.key, position: g.position)) {
                            ctx.fill(Path(toView(g.rect, size).insetBy(dx: -1, dy: -2)), with: .color(.white))
                        }
                    }
                }
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func interactionLayer(size: CGSize) -> some View {
        let db = model.db
        Canvas { ctx, size in
            guard let db else { return }
            func fill(_ key: AyahKey?, _ color: Color) {
                guard let key else { return }
                for r in db.highlightRects(for: key, page: page) {
                    ctx.fill(Path(roundedRect: toView(r, size).insetBy(dx: -2, dy: -1), cornerRadius: 4), with: .color(color))
                }
            }
            for key in db.ayahs(page: page) where model.library.notes[key] != nil {
                fill(key, .yellow.opacity(0.16))
            }
            if model.hovered != model.selected { fill(model.hovered, .primary.opacity(0.06)) }
            fill(model.selected, .accentColor.opacity(0.22))
            fill(model.audio.current, .green.opacity(0.28))
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(loc): model.hovered = db?.ayah(at: toImage(loc, size), page: page)
            case .ended: model.hovered = nil
            }
        }
        .onTapGesture(count: 2) { loc in
            if let key = db?.ayah(at: toImage(loc, size), page: page) {
                model.selected = key
                model.audio.play(from: key)
            }
        }
        .onTapGesture { loc in
            let key = db?.ayah(at: toImage(loc, size), page: page)
            model.selected = key == model.selected ? nil : key
        }
        .contextMenu {
            if let key = model.hovered ?? model.selected { AyahMenu(key: key) }
        }
    }

    /// Sticky-note tabs in the outer margin beside each annotated ayah; notes on one line stack into a menu.
    @ViewBuilder
    private func noteTabs(size: CGSize) -> some View {
        if let db = model.db {
            let noted = db.ayahs(page: page).filter { model.library.notes[$0] != nil }
            let byLine = Dictionary(grouping: noted) { key in
                Int((db.highlightRects(for: key, page: page).first?.midY ?? 0) / 40)
            }
            ForEach(byLine.keys.sorted(), id: \.self) { line in
                let keys = byLine[line]!.sorted()
                let y = toView(db.highlightRects(for: keys[0], page: page).first ?? .zero, size).midY
                NoteTab(keys: keys)
                    .position(x: outerEdgeIsRight ? size.width + 10 : -10, y: y)
            }
        }
    }

    private var tassel: some View {
        let marked = model.library.isBookmarked(page)
        return Tassel(marked: marked)
            .frame(width: 18, height: marked ? 64 : 40)
            .padding(.horizontal, 26)
            .offset(y: -4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    model.library.toggleBookmark(page, title: model.pageTitle(page))
                }
            }
            .help(marked ? "Remove bookmark" : "Tap the tassel to bookmark this page")
            .animation(.spring(duration: 0.3), value: marked)
    }
}

private struct NoteTab: View {
    @Environment(AppModel.self) private var model
    let keys: [AyahKey]

    var body: some View {
        let icon = ZStack(alignment: .topTrailing) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.yellow))
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            if keys.count > 1 {
                Text("\(keys.count)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    .padding(2).background(Circle().fill(.red)).offset(x: 5, y: -5)
            }
        }
        if keys.count == 1 {
            icon.onTapGesture { model.showText(.note, for: keys[0]) }
                .help(model.library.notes[keys[0]]?.text ?? "")
        } else {
            Menu {
                ForEach(keys, id: \.self) { key in
                    Button("\(key.description) — \(model.library.notes[key]?.text.prefix(40) ?? "")") {
                        model.showText(.note, for: key)
                    }
                }
            } label: { icon }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

/// Silk bookmark ribbon with a notched tail.
private struct Tassel: View {
    let marked: Bool

    var body: some View {
        RibbonShape()
            .fill(marked ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.70, green: 0.10, blue: 0.12), Color(red: 0.52, green: 0.05, blue: 0.08)], startPoint: .leading, endPoint: .trailing))
                         : AnyShapeStyle(Color.secondary.opacity(0.18)))
            .overlay(RibbonShape().stroke(marked ? .clear : Color.secondary.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(marked ? 0.35 : 0), radius: 2, x: 1, y: 2)
    }
}

private struct RibbonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.width * 0.45))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The page PNGs are black ink on transparency; invert the ink for dark themes.
private struct InkForScheme: ViewModifier {
    let dark: Bool
    func body(content: Content) -> some View {
        if dark { content.colorInvert().opacity(0.9) } else { content }
    }
}

/// Two-finger horizontal trackpad swipes turn pages (the original's swipe-to-turn, which can be disabled).
@MainActor
final class SwipeMonitor {
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private var fired = false

    func start(_ onSwipe: @escaping (_ forward: Bool) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return event }
            if event.phase.contains(.began) { accumulated = 0; fired = false }
            // With natural scrolling, fingers moving right give a positive delta: pull the next (left) page in.
            let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { accumulated += dx }
            if !fired, abs(accumulated) > 60 {
                fired = true
                onSwipe(accumulated > 0)
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
