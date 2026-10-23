// Renders Assets/AppIcon.png (1024×1024): emerald glass squircle, gold Rub el Hizb, "قرآن" on a glass disc.
// Run: swift scripts/make-icon.swift Assets/AppIcon.png
import AppKit
import SwiftUI

let gold = [Color(red: 1.00, green: 0.90, blue: 0.62), Color(red: 0.86, green: 0.68, blue: 0.33), Color(red: 0.62, green: 0.44, blue: 0.16)]

/// Eight-pointed star: two overlapping squares, the Rub el Hizb.
struct RubElHizb: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), rad = min(r.width, r.height) / 2
        for rotation in [0.0, Double.pi / 4] {
            for i in 0..<4 {
                let a = rotation + Double(i) * .pi / 2 + .pi / 4
                let pt = CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
        return p
    }
}

struct Icon: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            // Body: deep emerald with a lighter teal light source at the top left.
            shape.fill(LinearGradient(colors: [Color(red: 0.10, green: 0.62, blue: 0.50), Color(red: 0.03, green: 0.30, blue: 0.24),
                                               Color(red: 0.01, green: 0.14, blue: 0.11)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            // Faint geometric lattice.
            ForEach(0..<5) { row in
                ForEach(0..<5) { col in
                    RubElHizb().stroke(.white.opacity(0.05), lineWidth: 3)
                        .frame(width: 150, height: 150)
                        .position(x: 100 + CGFloat(col) * 156, y: 100 + CGFloat(row) * 156)
                }
            }
            .frame(width: 824, height: 824)
            .clipShape(shape)

            // Gold star with depth.
            RubElHizb()
                .fill(LinearGradient(colors: gold, startPoint: .top, endPoint: .bottom))
                .frame(width: 600, height: 600)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 18)
            RubElHizb()
                .stroke(LinearGradient(colors: [.white.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 6)
                .frame(width: 594, height: 594)

            // Glass disc at the centre.
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.42, blue: 0.33), Color(red: 0.02, green: 0.20, blue: 0.16)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 400, height: 400)
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 7))
                .overlay(Circle().stroke(Color(red: 0.62, green: 0.44, blue: 0.16), lineWidth: 3).padding(16))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            Text("قرآن")
                .font(.custom("Diwan Thuluth", size: 235))
                .foregroundStyle(LinearGradient(colors: gold, startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 3)
                .offset(y: -10)

            // Liquid Glass sheen: bright upper rim and a soft highlight.
            shape.fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.0)], startPoint: .top, endPoint: .center))
                .frame(width: 824, height: 824)
                .allowsHitTesting(false)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.2)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 5)
                .frame(width: 824, height: 824)
        }
        .frame(width: 824, height: 824)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        .frame(width: 1024, height: 1024)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    print("wrote \(out.path) \(cg.width)x\(cg.height)")
}
