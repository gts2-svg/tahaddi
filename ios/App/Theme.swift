// الشكل «نهار» (من الويب 1.7): خلفية فاتحة، وبطاقات بيضاء، ولون حيّ لكل قسم، وأربعة ألوان قوية للخيارات.
// الخط Readex Pro للواجهة وAmiri للشعر، محفوظان داخل التطبيق. حجم الخط من الإعدادات (uiScale).
import SwiftUI
import UIKit
import CoreText

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x5B4A8A
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

enum C {
    static let bg = Color(hex: "#F3F5FA")
    static let text = Color(hex: "#111827")
    static let muted = Color(hex: "#4B5563")
    static let soft = Color(hex: "#6B7280")
    static let line = Color(hex: "#111827").opacity(0.1)
    static let accent = Color(hex: "#2563EB")
    static let accentD = Color(hex: "#1E40AF")
    static let ok = Color(hex: "#15803D")
    static let bad = Color(hex: "#DC2626")
    static let gold = Color(hex: "#FFD23F")
    static let goldD = Color(hex: "#B88700")
    static let goldL = Color(hex: "#FFF1B8")
    static let ink = Color(hex: "#1A0B4A")
    static let amberText = Color(hex: "#B45309")
    static let seg = Color(hex: "#E5E7EB")

    /// ألوان الفرق: [بداية التدرّج، نهايته]
    static let teamHex: [(String, String)] = [("#D7334C", "#9E1F37"), ("#11837A", "#0B5C55"), ("#1F6FE0", "#1449A0"), ("#8A47D6", "#4B2181"),
                                               ("#B35F0F", "#7A3E07"), ("#188646", "#0C4F28"), ("#C2408A", "#6B1F4B"), ("#127E9C", "#0A4F63")]
    static func team(_ i: Int) -> Color { Color(hex: teamHex[((i % 8) + 8) % 8].0) }
    static func team2(_ i: Int) -> Color { Color(hex: teamHex[((i % 8) + 8) % 8].1) }
    static func teamGrad(_ i: Int) -> LinearGradient {
        LinearGradient(colors: [team(i), team2(i)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// لون ثابت لكل مستوى: سهل أخضر، متوسط أزرق، صعب كهرماني، صعب جداً أحمر
    static func level(_ d: Int) -> Color {
        switch d { case 1: return Color(hex: "#16A34A"); case 2: return Color(hex: "#2563EB"); case 3: return Color(hex: "#D97706"); default: return Color(hex: "#DC2626") }
    }
    static func levelDark(_ d: Int) -> Color {
        switch d { case 1: return Color(hex: "#15803D"); case 2: return Color(hex: "#1D4ED8"); case 3: return Color(hex: "#B45309"); default: return Color(hex: "#B91C1C") }
    }
    static func levelDeep(_ d: Int) -> Color {
        switch d { case 1: return Color(hex: "#14532D"); case 2: return Color(hex: "#1E3A8A"); case 3: return Color(hex: "#78350F"); default: return Color(hex: "#7F1D1D") }
    }

    /// ألوان الخيارات الأربعة: (بداية، نهاية، ظل، نص)
    static let opts: [(Color, Color, Color, Color)] = [
        (Color(hex: "#D7334C"), Color(hex: "#A82A3E"), Color(hex: "#7E1D2E"), .white),
        (Color(hex: "#1F6FE0"), Color(hex: "#14499A"), Color(hex: "#0E3570"), .white),
        (Color(hex: "#FFC233"), Color(hex: "#E59A00"), Color(hex: "#A86F00"), Color(hex: "#2A1300")),
        (Color(hex: "#108559"), Color(hex: "#0A6A47"), Color(hex: "#064A31"), .white),
    ]
    static func cat(_ c: Category?) -> (Color, Color) {
        guard let c else { return (Color(hex: "#5B4A8A"), Color(hex: "#3B2E63")) }
        return (Color(hex: c.c1), Color(hex: c.c2))
    }
    static func catGrad(_ c: Category?) -> LinearGradient {
        let (a, b) = cat(c)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - الخطوط
enum Fonts {
    static func register() {
        guard let dir = Bundle.main.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }
    static func readex(_ w: Font.Weight) -> String {
        switch w {
        case .bold, .heavy, .black: return "ReadexPro-Bold"
        case .semibold: return "ReadexPro-SemiBold"
        case .medium: return "ReadexPro-Medium"
        default: return "ReadexPro-Regular"
        }
    }
    static var available: Bool = UIFont(name: "ReadexPro-Regular", size: 12) != nil
}

private struct UIScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 0.8 }
private struct WideKey: EnvironmentKey { static let defaultValue: Bool = false }
private struct RoomyKey: EnvironmentKey { static let defaultValue: Bool = false }
extension EnvironmentValues {
    /// مضاعف الأحجام: «حجم الخط» في الإعدادات (0.7–1.0) × 1.3 في الآيباد
    var uiScale: CGFloat { get { self[UIScaleKey.self] } set { self[UIScaleKey.self] = newValue } }
    /// شاشة عريضة (الآيباد) تستحق تخطيطاً بعمودين
    var wide: Bool { get { self[WideKey.self] } set { self[WideKey.self] = newValue } }
    /// عرض كبير جداً (الآيباد أفقياً): الرئيسية بعمودين
    var roomy: Bool { get { self[RoomyKey.self] } set { self[RoomyKey.self] = newValue } }
}

struct TF: ViewModifier {
    @Environment(\.uiScale) var k
    let px: CGFloat
    let w: Font.Weight
    let amiri: Bool
    func body(content: Content) -> some View {
        let size = px * k
        let f: Font
        if amiri { f = Font.custom(w == .regular ? "Amiri-Regular" : "Amiri-Bold", fixedSize: size) }
        else if Fonts.available { f = Font.custom(Fonts.readex(w), fixedSize: size) }
        else { f = Font.system(size: size, weight: w) }
        return content.font(f)
    }
}
extension View {
    /// خط الواجهة بحجم «بكسل الويب» مضروباً في مضاعف الحجم
    func tf(_ px: CGFloat, _ w: Font.Weight = .regular, amiri: Bool = false) -> some View { modifier(TF(px: px, w: w, amiri: amiri)) }
    func card(_ k: CGFloat, radius: CGFloat = 20, pad: CGFloat = 14) -> some View {
        padding(pad * k)
            .background(RoundedRectangle(cornerRadius: radius * k, style: .continuous).fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 6 * k, x: 0, y: 2 * k))
    }
}

// MARK: - الأزرار
struct PrimaryStyle: ButtonStyle {
    var k: CGFloat
    var big = false
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let depth: CGFloat = (big ? 7 : 6) * k
        return configuration.label
            .tf(big ? 22 : 16, .bold)
            .foregroundColor(C.ink)
            .padding(.horizontal, 18 * k)
            .frame(maxWidth: big ? .infinity : nil, minHeight: (big ? 64 : 46) * k)
            .background(
                RoundedRectangle(cornerRadius: (big ? 22 : 16) * k, style: .continuous).fill(C.gold)
                    .shadow(color: C.goldD, radius: 0, x: 0, y: pressed ? depth / 3 : depth)
            )
            .offset(y: pressed ? depth * 0.6 : 0)
            .opacity(enabled ? 1 : 0.45)
            .padding(.bottom, depth)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}
struct GhostStyle: ButtonStyle {
    var k: CGFloat
    var small = false
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tf(small ? 15 : 16, .bold)
            .foregroundColor(danger ? Color(hex: "#B91C1C") : C.text)
            .padding(.horizontal, (small ? 14 : 18) * k)
            .frame(minHeight: 46 * k)
            .background(
                RoundedRectangle(cornerRadius: (small ? 14 : 16) * k, style: .continuous)
                    .fill(danger ? Color(hex: "#FEF2F2") : Color.white)
                    .overlay(RoundedRectangle(cornerRadius: (small ? 14 : 16) * k, style: .continuous)
                        .stroke(danger ? Color(hex: "#FCA5A5") : Color.black.opacity(0.12), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.06), radius: 3 * k, x: 0, y: 2 * k)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
struct FillStyle: ButtonStyle {
    var k: CGFloat
    var top: Color
    var bottom: Color
    var shadow: Color
    var fg: Color = .white
    var minH: CGFloat = 50
    var radius: CGFloat = 16
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundColor(fg)
            .padding(.horizontal, 14 * k)
            .frame(minHeight: minH * k)
            .background(
                RoundedRectangle(cornerRadius: radius * k, style: .continuous)
                    .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: shadow, radius: 0, x: 0, y: pressed ? 1 : 4 * k)
            )
            .offset(y: pressed ? 3 * k : 0)
            .padding(.bottom, 4 * k)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

// MARK: - قطع مشتركة
/// شارة المستوى: الكلمة بلونها الثابت، والنقاط صغيرة بجانبها
struct DiffChip: View {
    @Environment(\.uiScale) var k
    let d: Int
    var pts: String? = nil
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 5 * k) {
            Circle().fill(C.level(d)).frame(width: 8 * k, height: 8 * k)
            Text(DIFF_NAME[d] ?? "").tf(size, .bold).foregroundColor(C.levelDark(d))
            if let pts { Text(pts).tf(size - 2, .medium).foregroundColor(C.levelDark(d).opacity(0.8)) }
        }
        .padding(.horizontal, 10 * k).padding(.vertical, 4 * k)
        .background(Capsule().fill(C.level(d).opacity(0.13)))
        .overlay(Capsule().stroke(C.level(d).opacity(0.35), lineWidth: 1))
        .fixedSize()
    }
}

struct TeamPill: View {
    @Environment(\.uiScale) var k
    let i: Int
    let name: String
    var size: CGFloat = 16
    var body: some View {
        Text(name).tf(size, .bold).foregroundColor(.white).lineLimit(1)
            .padding(.horizontal, 12 * k).padding(.vertical, 3 * k)
            .background(Capsule().fill(C.teamGrad(i)))
            .overlay(Capsule().stroke(Color.white, lineWidth: 2 * k))
    }
}

/// صورة القسم المصغّرة (أو تدرّج لونه مع حرفه)
struct CatThumb: View {
    @Environment(\.uiScale) var k
    let cat: Category?
    var size: CGFloat = 30
    var body: some View {
        C.catGrad(cat)
            .overlay(Text(cat?.glyph ?? "").tf(size * 0.5, .bold).foregroundColor(.white.opacity(0.85)))
            .overlay(CachedImage(url: cat?.photoURL(200)))
            .frame(width: size * k, height: size * k)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.33 * k, style: .continuous))
    }
}

/// الحرف الأول من الاسم (بلا «ال»)
func initialOf(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("ال") && t.count >= 4 { t.removeFirst(2) }
    return t.first.map { String($0) } ?? "؟"
}

/// زر أيقونة دائري أبيض
struct IconButton: View {
    @Environment(\.uiScale) var k
    let system: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 19 * k, weight: .semibold))
                .foregroundColor(C.text)
                .frame(width: 46 * k, height: 46 * k)
                .background(RoundedRectangle(cornerRadius: 14 * k, style: .continuous).fill(Color.white)
                    .shadow(color: .black.opacity(0.08), radius: 5 * k, x: 0, y: 2 * k))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }
}
