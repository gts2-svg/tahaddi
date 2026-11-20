// شاشة اللعب: الشريط العلوي، ولوحة النقاط، وسطر الدور، والسؤال وخياراته، وما بعد الإجابة (السرقة، وحكم المضيف)،
// واختيار المستوى، وشاشة «دور الفريق». الخلفية كلها بلون الفريق صاحب الدور، وبطاقة السؤال بيضاء.
import SwiftUI
import UIKit

let LETTERS = ["أ", "ب", "ج", "د"]

struct GameView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    @State private var bursts = 0

    var body: some View {
        ZStack {
            if let g = m.game {
                VStack(spacing: 0) {
                    TopBar().padding(.horizontal, (wide ? 24 : 14) * k).padding(.top, 6 * k).padding(.bottom, 10 * k)
                    if wide {
                        HStack(alignment: .top, spacing: 22 * k) {
                            ScrollView(showsIndicators: false) { Scoreboard(vertical: true).padding(.bottom, 20 * k) }
                                .frame(width: 290 * k)
                            Stage(g: g).frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 24 * k)
                    } else {
                        Scoreboard(vertical: false).padding(.horizontal, 14 * k)
                        Stage(g: g)
                    }
                }
            }
            ConfettiLayer(bursts: bursts)
            if let s = m.splash, let g = m.game, s < g.teams.count {
                TurnSplash(i: s, name: g.teams[s].name, steal: false)
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(20)
            }
        }
        .onChange(of: m.fx) { f in
            if let f, f.ok, f.burst { bursts += 1 }
        }
        .onAppear { m.validateCurrent() }
    }
}

struct TopBar: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    var body: some View {
        HStack(spacing: 8 * k) {
            IconButton(system: "line.3.horizontal") { m.open(.menu) }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("القائمة")
            Text(progress).tf(16, .bold).foregroundColor(C.muted).frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.7)
            IconButton(system: "arrow.uturn.backward", disabled: m.undoCount == 0) { m.undo() }
                .accessibilityLabel("تراجع عن آخر إجراء")
        }
    }
    var progress: String {
        guard let g = m.game else { return "" }
        if g.mode == 1 {
            let all = g.boardCells.count
            let done = g.boardCells.filter { $0.used }.count
            return g.qid != nil ? "سؤال \(done + 1) من \(all)" : "تمّ \(done) من \(all)"
        }
        let r = g.ti < g.turns.count ? g.turns[g.ti].round : 0
        return "الجولة \(r + 1) من \(g.rounds)"
    }
}

// MARK: - لوحة النقاط
struct Scoreboard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let vertical: Bool
    var body: some View {
        if let g = m.game {
            let n = g.teams.count
            if vertical {
                VStack(spacing: 10 * k) {
                    ForEach(0..<n, id: \.self) { i in ScoreCard(i: i, row: true, big: n <= 6) }
                }
                .padding(.top, 6 * k).padding(.horizontal, 6 * k)
            } else {
                let cols = n <= 2 ? n : ((n == 3 || n == 5 || n == 6) ? 3 : 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8 * k), count: cols), spacing: 8 * k) {
                    ForEach(0..<n, id: \.self) { i in ScoreCard(i: i, row: n <= 2, big: false) }
                }
                .padding(.top, 4 * k)
            }
        }
    }
}

struct ScoreCard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let i: Int
    let row: Bool
    let big: Bool
    @State private var pop: String? = nil
    @State private var bump = false

    var body: some View {
        if let g = m.game, i < g.teams.count {
            let t = g.teams[i]
            let cur = m.curTeamIdx(g) == i
            Button { m.open(.team(i)) } label: {
                content(t, cur: cur, settings: g.settings)
                    .frame(maxWidth: .infinity, minHeight: (row ? 58 : 64) * k)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 16 * k, style: .continuous).fill(C.teamGrad(i))
                            if !cur { RoundedRectangle(cornerRadius: 16 * k, style: .continuous).fill(C.bg.opacity(0.42)) }
                        }
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16 * k, style: .continuous).strokeBorder(Color.white, lineWidth: cur ? 3 * k : 0))
                    .background(RoundedRectangle(cornerRadius: 19 * k, style: .continuous).fill(cur ? C.goldD : .clear).padding(-3 * k))
                    .shadow(color: .black.opacity(cur ? 0.25 : 0.12), radius: (cur ? 10 : 6) * k, x: 0, y: (cur ? 7 : 4) * k)
                    .overlay(alignment: .top) {
                        if let p = pop {
                            Text(p).tf(row ? 20 : 17, .bold).foregroundColor(.white)
                                .padding(.horizontal, 10 * k).padding(.vertical, 2 * k)
                                .background(Capsule().fill(C.ok).shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 3))
                                .offset(y: -16 * k)
                                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity.combined(with: .offset(y: -30 * k))))
                        }
                    }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("\(t.name): \(TL.fmtPts(t.score)). اضغط لتعديل الاسم أو النقاط")
            .onChange(of: m.fx) { f in
                guard let f, f.ok, f.team == i, let p = f.pts else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pop = plusPts(p); bump = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    withAnimation(.easeOut(duration: 0.3)) { bump = false }
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    withAnimation(.easeOut(duration: 0.4)) { pop = nil }
                }
            }
        }
    }

    @ViewBuilder
    func content(_ t: Team, cur: Bool, settings: Settings) -> some View {
        let life = HStack(spacing: 6 * k) {
            if settings.fifty { Image(systemName: "scissors").opacity(t.fifty ? 1 : 0.3) }
            Image(systemName: "arrow.left.arrow.right").opacity(t.swap ? 1 : 0.3)
        }
        .font(.system(size: (big ? 14 : 11) * k, weight: .semibold))
        .foregroundColor(.white)
        let score = Text(fmtPts(t.score)).tf(row ? (big ? 40 : 30) : 26, .bold).foregroundColor(.white)
            .scaleEffect(bump ? 1.25 : 1)
            .shadow(color: bump ? C.gold : .clear, radius: 8)
        if row {
            HStack(spacing: 8 * k) {
                VStack(alignment: .leading, spacing: 2 * k) {
                    if cur { Text("دوركم").tf(11, .semibold).foregroundColor(.white) }
                    Text(t.name).tf(big ? 18 : 14, .bold).foregroundColor(.white).lineLimit(2).minimumScaleFactor(0.7)
                    life
                }
                Spacer(minLength: 4 * k)
                score
            }
            .padding(.horizontal, 12 * k).padding(.vertical, 8 * k)
        } else {
            VStack(spacing: 1 * k) {
                if cur { Text("دوركم").tf(11, .semibold).foregroundColor(.white) }
                Text(t.name).tf(13, .bold).foregroundColor(.white).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                life
                score
            }
            .padding(.horizontal, 6 * k).padding(.vertical, 6 * k)
        }
    }
}

// MARK: - سطر الدور
struct TurnLine: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    var body: some View {
        if let g = m.game {
            let ti = m.curTeamIdx(g)
            HStack(spacing: 6 * k) {
                if g.phase == .steal, let s = g.stealer {
                    Text("محاولة سرقة:").tf(17, .semibold).foregroundColor(C.text)
                    TeamPill(i: s, name: g.teams[s].name, size: 17)
                } else {
                    Text("دور").tf(17, .semibold).foregroundColor(C.text)
                    TeamPill(i: ti, name: g.teams[ti].name, size: 17)
                    if g.mode == 1 && g.qid == nil { Text("— اختاروا سؤالاً").tf(17, .semibold).foregroundColor(C.text) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10 * k)
        }
    }
}

// MARK: - المسرح
struct Stage: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let g: GameState
    var body: some View {
        if g.mode == 1 && g.qid == nil {
            BoardView()
        } else if g.phase == .choose {
            ScrollView {
                VStack(spacing: 0) {
                    TurnLine()
                    ChooserView()
                }
                .padding(.horizontal, wide ? 0 : 14 * k)
                .padding(.bottom, 24 * k)
            }
        } else {
            QuestionStage()
        }
    }
}

struct QuestionStage: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    @State private var shakes: CGFloat = 0

    var body: some View {
        if let g = m.game, let q = m.curQuestion {
            let inQ = g.phase == .q
            ScrollView {
                VStack(spacing: 0) {
                    TurnLine()
                    QuestionCard(g: g, q: q, shakes: shakes)
                    if inQ { ToolsRow(g: g, q: q).padding(.top, 12 * k) }
                    if wide && !inQ { AfterPanel(g: g, q: q).padding(.top, 10 * k) }
                }
                .padding(.horizontal, wide ? 0 : 14 * k)
                .padding(.bottom, 20 * k)
            }
            .safeAreaInset(edge: .bottom) {
                if !wide && !inQ {
                    AfterPanel(g: g, q: q)
                        .padding(.horizontal, 14 * k).padding(.top, 12 * k).padding(.bottom, 4 * k)
                        .background(
                            RoundedRectangle(cornerRadius: 24 * k, style: .continuous).fill(Color.white)
                                .shadow(color: .black.opacity(0.14), radius: 14 * k, x: 0, y: -2 * k)
                                .ignoresSafeArea(edges: .bottom)
                        )
                        .padding(.horizontal, 8 * k)
                }
            }
            .onChange(of: m.fx) { f in
                if let f, !f.ok { withAnimation(.linear(duration: 0.45)) { shakes += 1 } }
            }
        } else {
            Color.clear.onAppear { m.validateCurrent() }
        }
    }
}

// MARK: - بطاقة السؤال
struct QuestionCard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let g: GameState
    let q: Question
    let shakes: CGFloat

    var body: some View {
        let cat = m.catByKey[q.cat]
        let ph = g.phase
        let open = ph == .judge || ph == .done
        let p = m.points(q, g)
        let canPause = ph == .q && g.timer != nil && !g.timedOut
        VStack(spacing: 0) {
            HStack(spacing: 8 * k) {
                CatThumb(cat: cat, size: 30)
                Text(cat?.name ?? q.cat).tf(15, .semibold).foregroundColor(C.text).lineLimit(1)
                DiffChip(d: q.d, pts: (q.clues != nil && ph == .q ? "الآن " : "") + ptsWordUI(p))
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10 * k)
            if ph == .q, let t = g.timer {
                HStack(spacing: 8 * k) {
                    TimerBar(timer: t, paused: g.paused || g.timedOut)
                    if canPause {
                        IconButton(system: g.paused ? "play.fill" : "pause.fill") { m.togglePause() }
                            .keyboardShortcut("p", modifiers: [])
                            .accessibilityLabel(g.paused ? "متابعة" : "إيقاف مؤقت")
                    }
                }
                .padding(.bottom, 14 * k)
            }
            ZStack {
                VStack(spacing: 0) {
                    QBox(g: g, q: q, open: open)
                        .modifier(Shake(animatableData: shakes))
                        .id(q.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    OptionsView(g: g, q: q, open: open, shakes: shakes).padding(.top, 16 * k)
                    if open {
                        HStack(spacing: 6 * k) {
                            Text("الإجابة:").tf(18).foregroundColor(C.muted)
                            Text(q.a).tf(wide ? 26 : 22, .bold).foregroundColor(C.ok)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, 10 * k)
                    }
                }
                if canPause && g.paused {
                    Button { m.resumeGame() } label: {
                        VStack(spacing: 8 * k) {
                            Image(systemName: "pause.circle.fill").font(.system(size: 48 * k))
                            Text("متوقف مؤقتاً").tf(26, .bold)
                            Text("اضغط للمتابعة").tf(15, .medium).foregroundColor(Color.white.opacity(0.75))
                        }
                        .foregroundColor(C.gold)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minHeight: 300 * k)
                        .background(RoundedRectangle(cornerRadius: 26 * k, style: .continuous).fill(Color(hex: "#1E1B4B")))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("متابعة")
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: q.id)
    }
}

struct TimerBar: View {
    @Environment(\.uiScale) var k
    @Environment(\.accessibilityReduceMotion) var rm
    let timer: TL.Timer
    let paused: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: timer.since == nil)) { tl in
            let now = tl.date.timeIntervalSince1970 * 1000
            let left = TL.tRemaining(timer, now)
            let frac = max(0, min(1, left / Double(max(1, timer.total) * 1000)))
            let sec = TL.tSeconds(timer, now)
            let urgent = sec <= 5 && timer.since != nil
            let pulse = urgent && !rm && Int(now / 300) % 2 == 0
            HStack(spacing: 8 * k) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: "#E5E7EB"))
                        Capsule().fill(urgent ? (pulse || rm ? Color(hex: "#EF4444") : C.accent) : C.accent)
                            .frame(width: geo.size.width * frac)
                    }
                }
                .frame(height: 10 * k)
                Text("\(sec)").tf(18, .bold)
                    .foregroundColor(urgent ? .white : C.text)
                    .frame(minWidth: 52 * k, minHeight: 36 * k)
                    .background(RoundedRectangle(cornerRadius: 12 * k).fill(urgent ? Color(hex: "#D7334C") : Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 4 * k, x: 0, y: 2 * k))
                    .scaleEffect(pulse ? 1.08 : 1)
                    .accessibilityLabel("بقي \(sec) ثانية")
            }
            .opacity(paused ? 0.6 : 1)
        }
    }
}

struct QBox: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let g: GameState
    let q: Question
    let open: Bool
    var body: some View {
        Group {
            if let clues = q.clues {
                ClueList(clues: clues, shown: g.shown, open: open, compact: open || g.phase == .steal, cat: m.catByKey[q.cat])
            } else {
                let poem = q.q.contains("\n")
                Text(q.q)
                    .tf(poem ? (wide ? 28 : 23) : (wide ? 26 : 21), .bold, amiri: poem)
                    .lineSpacing((poem ? 10 : 6) * k)
                    .foregroundColor(C.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18 * k).padding(.vertical, 20 * k)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 26 * k, style: .continuous).fill(Color.white)
            .shadow(color: Color.black.opacity(0.12), radius: 12 * k, x: 0, y: 10 * k))
    }
}

// MARK: - التلميحات (ومنها شعارات الأندية «@مفتاح»)
struct ClueList: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let clues: [String]
    let shown: Int
    let open: Bool
    let compact: Bool
    let cat: Category?

    var body: some View {
        let clubs = clues.allSatisfy { $0.hasPrefix("@") }
        if clubs {
            FlowLayout(spacing: 8 * k, rowSpacing: 8 * k) {
                ForEach(clues.indices, id: \.self) { i in
                    Group {
                        if i < shown || open { ClubTile(n: i + 1, key: String(clues[i].dropFirst()), late: i >= shown) }
                        else { LockedTile(n: i + 1) }
                    }
                    .frame(width: (wide ? 112 : (clues.count > 6 ? 82 : 98)) * k)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: (compact ? 5 : 8) * k) {
                ForEach(clues.indices, id: \.self) { i in
                    if i < shown || open {
                        HStack(alignment: .top, spacing: 10 * k) {
                            num(i + 1, locked: false)
                            if clues[i].hasPrefix("@") {
                                ClubInline(key: String(clues[i].dropFirst()))
                            } else {
                                Text(clues[i]).tf(compact ? 15 : (wide ? 20 : 18), .medium).foregroundColor(C.ink)
                                    .lineSpacing(4 * k).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12 * k).padding(.vertical, (compact ? 6 : 10) * k)
                        .background(RoundedRectangle(cornerRadius: 14 * k).fill(Color(hex: "#F1ECFF")))
                        .opacity(i >= shown ? 0.7 : 1)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    } else if !compact {
                        HStack(spacing: 10 * k) {
                            num(i + 1, locked: true)
                            Text("تلميح مخفي").tf(15).foregroundColor(Color(hex: "#5A3DB8"))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12 * k).padding(.vertical, 10 * k)
                        .overlay(RoundedRectangle(cornerRadius: 14 * k).strokeBorder(Color(hex: "#CFC3F2"), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    }
                }
            }
            .animation(.easeOut(duration: 0.3), value: shown)
        }
    }
    func num(_ n: Int, locked: Bool) -> some View {
        Text("\(n)").tf(15, .bold).foregroundColor(locked ? C.ink : .white)
            .frame(width: 28 * k, height: 28 * k)
            .background(RoundedRectangle(cornerRadius: 9 * k).fill(locked ? Color(hex: "#CFC3F2") : (cat.map { Color(hex: $0.c1) } ?? Color(hex: "#3D1FA3"))))
    }
}

struct ClubBadge: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let key: String
    var size: CGFloat = 52
    var body: some View {
        let club = m.clubs[key.lowercased()]
        let c1 = Color(hex: club?.c1 ?? "#334155")
        let c2 = Color(hex: club?.c2 ?? "#1E293B")
        ZStack {
            Circle().fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initialOf(club?.ar ?? key)).tf(size * 0.42, .bold).foregroundColor(.white)
            if let b = club?.badge, !b.isEmpty, let u = URL(string: b) {
                Circle().fill(Color.white)
                CachedImage(url: u, mode: .fit).padding(size * 0.08 * k)
            }
        }
        .frame(width: size * k, height: size * k)
        .clipShape(Circle())
        .overlay(Circle().stroke(c1.opacity(0.35), lineWidth: 1.5))
    }
}

struct ClubTile: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let n: Int
    let key: String
    let late: Bool
    var body: some View {
        let club = m.clubs[key.lowercased()]
        VStack(spacing: 6 * k) {
            ClubBadge(key: key, size: 54)
            Text(club?.ar ?? key).tf(13, .bold).foregroundColor(C.ink).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
        }
        .padding(.vertical, 10 * k).padding(.horizontal, 6 * k)
        .frame(maxWidth: .infinity, minHeight: 112 * k)
        .background(RoundedRectangle(cornerRadius: 16 * k).fill(Color(hex: "#F8FAFC")))
        .overlay(RoundedRectangle(cornerRadius: 16 * k).stroke(Color(hex: club?.c1 ?? "#CBD5E1").opacity(0.45), lineWidth: 1.5))
        .overlay(alignment: .topLeading) {
            Text("\(n)").tf(11, .bold).foregroundColor(.white).frame(width: 20 * k, height: 20 * k)
                .background(Circle().fill(Color(hex: "#3D1FA3"))).padding(5 * k)
        }
        .opacity(late ? 0.7 : 1)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

struct LockedTile: View {
    @Environment(\.uiScale) var k
    let n: Int
    var body: some View {
        VStack(spacing: 6 * k) {
            Text("؟").tf(28, .bold).foregroundColor(Color(hex: "#5A3DB8"))
            Text("نادٍ \(n)").tf(12).foregroundColor(Color(hex: "#5A3DB8"))
        }
        .frame(maxWidth: .infinity, minHeight: 112 * k)
        .overlay(RoundedRectangle(cornerRadius: 16 * k).strokeBorder(Color(hex: "#CFC3F2"), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}

struct ClubInline: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let key: String
    var body: some View {
        HStack(spacing: 8 * k) {
            ClubBadge(key: key, size: 30)
            Text(m.clubs[key.lowercased()]?.ar ?? key).tf(17, .bold).foregroundColor(C.ink)
        }
    }
}

// MARK: - الخيارات
struct OptionsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let g: GameState
    let q: Question
    let open: Bool
    let shakes: CGFloat

    func text(_ kk: Int) -> String { kk == 0 ? q.a : (kk - 1 < q.w.count ? q.w[kk - 1] : "") }

    var body: some View {
        let hidden = m.optsHidden
        let ph = g.phase
        if hidden {
            if ph == .q {
                Text(g.timedOut ? "انتهى الوقت. لغير الفريق أن يقول جوابه الآن قبل الكشف." : "الخيارات مخفية: يجيب الفريق شفهياً، ثم يكشف المقدِّم الإجابة.")
                    .tf(16).foregroundColor(Color(hex: "#374151")).multilineTextAlignment(.center).lineSpacing(4 * k)
                    .padding(.horizontal, 14 * k).padding(.vertical, 20 * k)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 20 * k).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 20 * k).strokeBorder(Color(hex: "#CBD5E1"), style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
            }
        } else {
            let list = g.order.contains { kk in let t = text(kk); return t.count > 22 || t.contains("\n") }
            let lockedAll = open || (ph == .steal && g.stealer == nil)
            if list {
                VStack(spacing: 10 * k) { ForEach(0..<g.order.count, id: \.self) { i in cell(i, list: true, lockedAll: lockedAll) } }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12 * k), GridItem(.flexible(), spacing: 12 * k)], spacing: 12 * k) {
                    ForEach(0..<g.order.count, id: \.self) { i in cell(i, list: false, lockedAll: lockedAll) }
                }
            }
        }
    }

    @ViewBuilder
    func cell(_ i: Int, list: Bool, lockedAll: Bool) -> some View {
        let kk = g.order[i]
        let ph = g.phase
        let isOk = open && kk == 0
        let isBad = (open && kk != 0 && (i == g.pick || i == g.stealPick)) || (ph == .steal && i == g.pick)
        let gone = g.gone.contains(i)
        let disabled = open || gone || (ph == .steal && (g.stealer == nil || i == g.pick)) || g.paused
        let dim = lockedAll && !isOk && !isBad
        let shakeThis = m.fx.map { !$0.ok && $0.opt == i } ?? false
        OptionButton(index: i, label: text(kk), letter: LETTERS[i], list: list, ok: isOk, bad: isBad) { m.answer(i) }
            .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [])
            .disabled(disabled)
            .opacity(gone ? 0.15 : (dim ? 0.45 : 1))
            .saturation(gone ? 0 : 1)
            .modifier(Shake(animatableData: shakeThis ? shakes : 0))
            .accessibilityLabel("\(LETTERS[i]): \(text(kk))")
    }
}

struct OptionButton: View {
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let index: Int
    let label: String
    let letter: String
    let list: Bool
    let ok: Bool
    let bad: Bool
    let action: () -> Void

    var body: some View {
        let pal = C.opts[index % 4]
        let fg = ok ? Color(hex: "#062A16") : bad ? Color.white : pal.3
        let badge = ZStack {
            RoundedRectangle(cornerRadius: 10 * k).fill(ok ? Color(hex: "#062A16") : (index == 2 && !bad ? Color(hex: "#2A1300").opacity(0.14) : Color.white.opacity(0.22)))
            if ok { Image(systemName: "checkmark").font(.system(size: 15 * k, weight: .heavy)).foregroundColor(Color(hex: "#5BE897")) }
            else { Text(letter).tf(15, .bold).foregroundColor(fg) }
        }
        .frame(width: 30 * k, height: 30 * k)
        Button(action: action) {
            Group {
                if list {
                    HStack(spacing: 12 * k) {
                        badge
                        Text(label).tf(wide ? 20 : 17, .semibold).foregroundColor(fg).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14 * k).padding(.vertical, 10 * k)
                    .frame(minHeight: 58 * k)
                } else {
                    VStack(spacing: 6 * k) {
                        badge
                        Text(label).tf(wide ? 22 : 19, .bold).foregroundColor(fg).multilineTextAlignment(.center)
                            .lineLimit(3).minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 10 * k).padding(.vertical, 12 * k)
                    .frame(maxWidth: .infinity, minHeight: (wide ? 110 : 96) * k)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(OptionStyle(k: k, index: index, list: list, ok: ok, bad: bad))
    }
}

struct OptionStyle: ButtonStyle {
    let k: CGFloat
    let index: Int
    let list: Bool
    let ok: Bool
    let bad: Bool
    func makeBody(configuration: Configuration) -> some View {
        let pal = C.opts[index % 4]
        let top = ok ? Color(hex: "#5BE897") : bad ? Color(hex: "#6B7280") : pal.0
        let bottom = ok ? Color(hex: "#2BBF6E") : bad ? Color(hex: "#6B7280") : pal.1
        let shadow = ok ? Color(hex: "#146B3C") : bad ? Color(hex: "#374151") : pal.2
        let depth = (list ? 5 : 7) * k
        let r = (list ? 18 : 22) * k
        let pressed = configuration.isPressed
        return configuration.label
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: shadow, radius: 0, x: 0, y: pressed ? depth / 3 : depth)
            )
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.white, lineWidth: ok ? 3 * k : 0))
            .background(RoundedRectangle(cornerRadius: r + 3 * k, style: .continuous).fill(ok ? C.ok : .clear).padding(-3 * k))
            .scaleEffect(ok ? (list ? 1.02 : 1.04) : 1)
            .offset(y: pressed ? depth * 0.6 : 0)
            .padding(.bottom, depth)
            .zIndex(ok ? 1 : 0)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: ok)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

// MARK: - الأدوات
struct ToolsRow: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let g: GameState
    let q: Question
    var body: some View {
        let team = g.teams[m.curTeamIdx(g)]
        let hidden = m.optsHidden
        FlowLayout(spacing: 8 * k, rowSpacing: 4 * k) {
            if g.settings.fifty && !hidden && !g.timedOut {
                Button { m.useFifty() } label: { Label("حذف إجابتين", systemImage: "scissors") }
                    .buttonStyle(GhostStyle(k: k, small: true))
                    .disabled(!team.fifty || !g.gone.isEmpty || g.paused).opacity(!team.fifty || !g.gone.isEmpty ? 0.4 : 1)
            }
            if let c = q.clues, g.shown < c.count, !g.timedOut {
                Button { m.moreClue() } label: { Label("تلميح آخر (تنقص نقطة)", systemImage: "lightbulb") }
                    .buttonStyle(GhostStyle(k: k, small: true)).disabled(g.paused)
            }
            if !g.timedOut {
                Button { m.swapQ() } label: { Label("تبديل السؤال", systemImage: "arrow.left.arrow.right") }
                    .buttonStyle(GhostStyle(k: k, small: true))
                    .disabled(!team.swap || g.paused).opacity(team.swap ? 1 : 0.4)
            }
            if hidden && !g.timedOut {
                Button { m.showOptions() } label: { Text("أظهر الخيارات (بنصف النقاط: \(fmtPts(TL.halve(TL.basePoints(q, shown: g.shown)))))") }
                    .buttonStyle(GhostStyle(k: k, small: true))
            }
            if g.settings.host {
                Button { m.hostReveal() } label: { Text("اكشف الإجابة") }
                    .buttonStyle(PrimaryStyle(k: k))
            }
        }
    }
}

// MARK: - ما بعد الإجابة
struct AfterPanel: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let g: GameState
    let q: Question

    var body: some View {
        let ti = m.curTeamIdx(g)
        let team = g.teams[ti]
        let p = m.points(q, g)
        VStack(spacing: 8 * k) {
            if g.phase == .steal {
                Text(g.pick == -1 ? "انتهى الوقت" : "الجواب غير صحيح من \(team.name)").tf(22, .bold).foregroundColor(C.bad)
                panel {
                    let sp = TL.stealPoints(p)
                    if g.stealer == nil {
                        Text("هل يحاول فريق آخر قبل كشف الإجابة؟ للسرقة \(plusPts(sp))").tf(15, .semibold).foregroundColor(C.text).multilineTextAlignment(.center)
                        FlowLayout(spacing: 8 * k, rowSpacing: 4 * k) {
                            ForEach(0..<g.teams.count, id: \.self) { kk in
                                if kk != ti {
                                    Button { m.chooseStealer(kk) } label: { Text(g.teams[kk].name).tf(15, .bold) }
                                        .buttonStyle(FillStyle(k: k, top: C.team(kk), bottom: C.team2(kk), shadow: .black.opacity(0.25), minH: 48))
                                }
                            }
                            Button { m.noSteal() } label: { Text("لا أحد — اكشف الإجابة") }.buttonStyle(GhostStyle(k: k, small: true))
                        }
                    } else if let s = g.stealer {
                        Text("\(g.teams[s].name): اختاروا جوابكم من الخيارات (\(plusPts(sp)))").tf(15, .semibold).foregroundColor(C.text).multilineTextAlignment(.center)
                        FlowLayout(spacing: 8 * k, rowSpacing: 4 * k) {
                            Button { m.chooseStealer(nil) } label: { Text("تغيير الفريق") }.buttonStyle(GhostStyle(k: k, small: true))
                            Button { m.noSteal() } label: { Text("لا أحد — اكشف الإجابة") }.buttonStyle(GhostStyle(k: k, small: true))
                        }
                    }
                }
            } else if g.phase == .judge {
                panel {
                    Text(m.canSteal ? "من أصاب؟ (السرقة لمن قال جوابه قبل الكشف)" : "هل أصاب الفريق؟").tf(15, .semibold).foregroundColor(C.text)
                    FlowLayout(spacing: 8 * k, rowSpacing: 4 * k) {
                        if !g.timedOut {
                            Button { m.judge("ok") } label: { Label("أصاب \(team.name) \(plusPts(p))", systemImage: "checkmark").font(.system(size: 15 * k, weight: .bold)) }
                                .buttonStyle(FillStyle(k: k, top: Color(hex: "#4BE08C"), bottom: Color(hex: "#22B566"), shadow: Color(hex: "#146B3C"), fg: Color(hex: "#062A16")))
                        }
                        if m.canSteal {
                            ForEach(0..<g.teams.count, id: \.self) { kk in
                                if kk != ti {
                                    Button { m.judge("steal", kk) } label: { Text("سرقة: \(g.teams[kk].name) \(plusPts(TL.stealPoints(p)))").tf(15, .bold) }
                                        .buttonStyle(FillStyle(k: k, top: C.team(kk), bottom: C.team2(kk), shadow: .black.opacity(0.25), minH: 48))
                                }
                            }
                        }
                        Button { m.judge("none") } label: { Label("لم يُصب أحد", systemImage: "xmark").font(.system(size: 15 * k, weight: .bold)) }
                            .buttonStyle(FillStyle(k: k, top: Color(hex: "#6B7280"), bottom: Color(hex: "#6B7280"), shadow: Color(hex: "#374151")))
                    }
                }
            } else if g.phase == .done {
                let r = g.res ?? TurnResult(type: "none")
                Group {
                    if r.type == "ok", let t = r.team, let pts = r.pts {
                        Text("أحسنتم! \(g.teams[t].name) \(plusPts(pts))").foregroundColor(C.ok)
                    } else if r.type == "steal", let t = r.team, let pts = r.pts {
                        Text("سرقة ناجحة: \(g.teams[t].name) \(plusPts(pts))").foregroundColor(C.ok)
                    } else {
                        Text(g.pick == -1 && !g.settings.host ? "انتهى الوقت" : (m.canSteal ? "لم يُصب أحد" : "الجواب غير صحيح")).foregroundColor(C.bad)
                    }
                }
                .tf(22, .bold).multilineTextAlignment(.center)
                .transition(.scale.combined(with: .opacity))
                HStack(spacing: 10 * k) {
                    Button { m.next() } label: { Text(m.isLastQuestion ? "النتيجة" : (g.mode == 1 ? "إلى اللوحة" : "التالي")) }
                        .buttonStyle(PrimaryStyle(k: k))
                        .keyboardShortcut(.return, modifiers: [])
                    Button { m.open(.report) } label: { Label("فيه خطأ", systemImage: "flag") }
                        .buttonStyle(GhostStyle(k: k, small: true))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: g.phase)
    }

    func panel<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        VStack(spacing: 10 * k) { content() }
            .frame(maxWidth: .infinity)
            .padding(12 * k)
            .background(RoundedRectangle(cornerRadius: 18 * k).fill(Color.white).shadow(color: .black.opacity(0.08), radius: 6 * k, x: 0, y: 2 * k))
    }
}

// MARK: - اختيار المستوى (يختاره الفريق)
struct ChooserView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    var body: some View {
        if let g = m.game, g.ti < g.turns.count {
            let t = g.turns[g.ti]
            let cat = m.catByKey[t.cat]
            let counts = m.levelCounts(t.cat)
            VStack(spacing: 14 * k) {
                HStack(spacing: 8 * k) {
                    CatThumb(cat: cat, size: 34)
                    Text(cat?.name ?? t.cat).tf(16, .semibold).foregroundColor(C.text)
                }
                Text("اختاروا مستوى سؤالكم").tf(22, .bold).foregroundColor(C.text)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12 * k), count: wide ? 4 : 2), spacing: 12 * k) {
                    ForEach(TL.LEVELS, id: \.self) { d in
                        let n = counts[d - 1]
                        Button { m.pickLevel(d) } label: {
                            VStack(spacing: 3 * k) {
                                Text(DIFF_NAME[d] ?? "").tf(21, .bold)
                                Text(ptsWordUI(Double(d)) + (cat?.clues == true ? " + التلميحات" : "")).tf(15, .semibold)
                                Text(n > 0 ? "بقي \(n)" : "نفدت").tf(13).opacity(0.9)
                            }
                            .frame(maxWidth: .infinity, minHeight: 100 * k)
                        }
                        .buttonStyle(FillStyle(k: k, top: C.level(d), bottom: C.levelDark(d), shadow: C.levelDeep(d), radius: 20))
                        .disabled(n == 0).opacity(n == 0 ? 0.3 : 1)
                    }
                }
                if !counts.contains(where: { $0 > 0 }) {
                    Text("انتهت الأسئلة المتاحة في كل الأقسام المختارة.").tf(13).foregroundColor(C.muted)
                    Button("عرض النتيجة") { m.endGame() }.buttonStyle(PrimaryStyle(k: k))
                }
            }
            .padding(16 * k)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 24 * k).fill(Color.white).shadow(color: .black.opacity(0.12), radius: 12 * k, x: 0, y: 10 * k))
        }
    }
}

// MARK: - شاشة «دور الفريق»
struct TurnSplash: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let i: Int
    let name: String
    let steal: Bool
    @State private var shown = false
    var body: some View {
        ZStack {
            C.teamGrad(i)
                .overlay(
                    ZStack {
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 520 * k, height: 520 * k).offset(x: 160 * k, y: -260 * k)
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 380 * k, height: 380 * k).offset(x: -170 * k, y: 300 * k)
                    }
                )
                .clipped()
                .ignoresSafeArea()
            VStack(spacing: 14 * k) {
                Text(initialOf(name)).tf(54, .bold).foregroundColor(C.team(i))
                    .frame(width: 110 * k, height: 110 * k)
                    .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.2), radius: 14 * k, x: 0, y: 8 * k))
                    .scaleEffect(shown ? 1 : 0.6)
                Text("دور").tf(26, .semibold).foregroundColor(.white.opacity(0.9))
                Text(name).tf(46, .bold).foregroundColor(.white).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6).padding(.horizontal, 24 * k)
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
            .offset(y: shown ? 0 : 20 * k)
            .opacity(shown ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { m.dismissSplash() }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { shown = true } }
        .accessibilityLabel("دور \(name)")
    }
}
