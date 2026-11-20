// المؤثرات: قصاصات ملونة (دفعة عند الصواب، ومطر في شاشة الفوز)، واهتزاز عند الخطأ، وتخطيط يلتف، وأشعة الفوز.
import SwiftUI

struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = animatableData - animatableData.rounded(.down)
        let x = 10 * sin(t * .pi * 4) * (1 - t)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

private struct Piece {
    var x: CGFloat
    var w: CGFloat
    var color: Color
    var dx: CGFloat
    var dur: Double
    var delay: Double
    var spin: Double
}

/// قصاصات: bursts يزيد عند كل دفعة؛ rain مطر خفيف متواصل
struct ConfettiLayer: View {
    var bursts: Int = 0
    var rain: Bool = false
    @Environment(\.accessibilityReduceMotion) var rm
    @State private var pieces: [Piece] = []
    @State private var start = Date()
    @State private var active = false
    static let colors: [Color] = [Color(hex: "#FFD23F"), Color(hex: "#FF5A5F"), Color(hex: "#2EC4B6"), Color(hex: "#7B4DFF"), Color(hex: "#3BD67F"), Color(hex: "#1F6FE0")]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !active)) { tl in
            Canvas { ctx, size in
                let now = tl.date.timeIntervalSince(start)
                for p in pieces {
                    var t = now - p.delay
                    if t < 0 { continue }
                    if rain { t = t.truncatingRemainder(dividingBy: p.dur) } else if t > p.dur { continue }
                    let prog = t / p.dur
                    let y = -40 + (size.height + 80) * prog
                    let x = p.x * size.width + p.dx * prog
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(560 * prog * p.spin))
                    c.fill(Path(CGRect(x: -p.w / 2, y: -p.w * 0.8, width: p.w, height: p.w * 1.6)), with: .color(p.color.opacity(rain ? 0.85 : 1)))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: bursts) { _ in fire() }
        .onAppear { if rain { fire() } }
    }

    func fire() {
        if rm { return }
        let n = rain ? 26 : 40
        pieces = (0..<n).map { i in
            let w = CGFloat(6 + (i % 3) * 3)
            return Piece(x: CGFloat((Double(i) * 37 + Double.random(in: 0..<20)).truncatingRemainder(dividingBy: 100)) / 100,
                         w: w, color: ConfettiLayer.colors[i % ConfettiLayer.colors.count],
                         dx: CGFloat.random(in: -60...60),
                         dur: rain ? 3.5 + Double(i % 4) * 0.8 : 1.6 + Double(i % 5) * 0.25,
                         delay: rain ? Double(i % 10) * 0.6 : Double(i % 9) * 0.07,
                         spin: Double.random(in: 0.6...1.4) * (i % 2 == 0 ? 1 : -1))
        }
        start = Date()
        active = true
        if !rain {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_300_000_000)
                if Date().timeIntervalSince(start) >= 3.2 { active = false; pieces = [] }
            }
        }
    }
}

/// صفوف تلتف، متوسطة
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowW: CGFloat = 0
        for s in subviews {
            let sz = fit(s, maxW)
            if !rows[rows.count - 1].isEmpty && rowW + spacing + sz.width > maxW { rows.append([]); rowW = 0 }
            rowW += (rows[rows.count - 1].isEmpty ? 0 : spacing) + sz.width
            rows[rows.count - 1].append(sz)
        }
        let h = rows.reduce(CGFloat(0)) { $0 + ($1.map { $0.height }.max() ?? 0) } + rowSpacing * CGFloat(max(0, rows.count - 1))
        let w = rows.map { r in r.reduce(CGFloat(0)) { $0 + $1.width } + spacing * CGFloat(max(0, r.count - 1)) }.max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }
    /// المقاس الطبيعي للعنصر (بلا التفاف)، ولا يزيد على العرض المتاح
    func fit(_ s: LayoutSubview, _ maxW: CGFloat) -> CGSize {
        let ideal = s.sizeThatFits(.unspecified)
        if ideal.width <= maxW { return ideal }
        return s.sizeThatFits(ProposedViewSize(width: maxW, height: nil))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(Subviews.Element, CGSize)]] = [[]]
        var rowW: CGFloat = 0
        for s in subviews {
            let sz = fit(s, bounds.width)
            if !rows[rows.count - 1].isEmpty && rowW + spacing + sz.width > bounds.width { rows.append([]); rowW = 0 }
            rowW += (rows[rows.count - 1].isEmpty ? 0 : spacing) + sz.width
            rows[rows.count - 1].append((s, sz))
        }
        var y = bounds.minY
        for r in rows {
            let w = r.reduce(CGFloat(0)) { $0 + $1.1.width } + spacing * CGFloat(max(0, r.count - 1))
            let h = r.map { $0.1.height }.max() ?? 0
            var x = bounds.minX + (bounds.width - w) / 2
            for (s, sz) in r {
                // +1 حتى لا يلتف النص بسبب كسور التقريب
                s.place(at: CGPoint(x: x, y: y + (h - sz.height) / 2), proposal: ProposedViewSize(width: sz.width + 1, height: sz.height))
                x += sz.width + spacing
            }
            y += h + rowSpacing
        }
    }
}

/// أشعة دوّارة خلف الفائز
struct Rays: View {
    @Environment(\.accessibilityReduceMotion) var rm
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: rm)) { tl in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = max(size.width, size.height)
                let a0 = rm ? 0 : tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 30) / 30 * 2 * .pi
                for i in 0..<15 {
                    let a = a0 + Double(i) * (2 * .pi / 15)
                    var p = Path()
                    p.move(to: c)
                    p.addArc(center: c, radius: r, startAngle: .radians(a), endAngle: .radians(a + 0.17), clockwise: false)
                    p.closeSubpath()
                    ctx.fill(p, with: .color(Color(hex: "#F59E0B").opacity(0.18)))
                }
            }
        }
        .mask(RadialGradient(colors: [.black, .black.opacity(0)], center: .center, startRadius: 40, endRadius: 300))
        .allowsHitTesting(false)
    }
}
