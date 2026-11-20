// الرئيسية: الفرق، والأقسام بصورها، والإعدادات، وزر البدء، وروابط السجل والبلاغات والتشخيص.
import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    @Environment(\.roomy) var roomy
    @FocusState private var focused: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Hero()
                    if m.game != nil { ResumeBox().padding(.top, 12 * k) }
                    if !m.failed.isEmpty { LoadErrorBox().padding(.top, 12 * k) }
                    if roomy {
                        HStack(alignment: .top, spacing: 22 * k) {
                            VStack(alignment: .leading, spacing: 0) {
                                teamsSection
                                catsSection(cols: 3)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 0) {
                                SettingsCard().id("settings").padding(.top, 20 * k)
                                FooterLinks()
                            }
                            .frame(width: 400 * k)
                        }
                    } else {
                        teamsSection
                        catsSection(cols: wide ? 4 : 2)
                        SettingsCard().id("settings").padding(.top, 14 * k)
                        FooterLinks()
                    }
                }
                .padding(.horizontal, (wide ? 28 : 14) * k)
                .padding(.top, 8 * k)
                .padding(.bottom, 20 * k)
                .frame(maxWidth: wide ? 1400 : 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { StartBar() }
            .onAppear {
                m.normalizeCats()
                if Shot.name == "settings" {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        proxy.scrollTo("settings", anchor: .top)
                    }
                }
                if Shot.name == "teams" {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        focused = 0
                    }
                }
            }
        }
    }

    // MARK: الفرق
    var teamsSection: some View {
        VStack(alignment: .leading, spacing: 10 * k) {
            HStack {
                Text("الفرق").tf(19, .bold).foregroundColor(C.text)
                Spacer()
                Button { m.addTeam() } label: { Label("فريق", systemImage: "plus") }
                    .buttonStyle(GhostStyle(k: k, small: true)).disabled(m.settings.teams.count >= 8)
                    .opacity(m.settings.teams.count >= 8 ? 0.4 : 1)
                Button { focused = nil; m.removeTeam() } label: { Label("فريق", systemImage: "minus") }
                    .buttonStyle(GhostStyle(k: k, small: true)).disabled(m.settings.teams.count <= 1)
                    .opacity(m.settings.teams.count <= 1 ? 0.4 : 1)
            }
            LazyVGrid(columns: wide ? [GridItem(.adaptive(minimum: 200 * k), spacing: 10 * k)] : Array(repeating: GridItem(.flexible(), spacing: 10 * k), count: 2), spacing: 10 * k) {
                ForEach(0..<m.settings.teams.count, id: \.self) { i in
                    TeamField(i: i, focus: $focused)
                }
            }
        }
        .padding(.top, 20 * k)
    }

    // MARK: الأقسام
    func catsSection(cols: Int) -> some View {
        let lvl = m.levelFilter
        return VStack(alignment: .leading, spacing: 10 * k) {
            HStack {
                Text("اختاروا الأقسام").tf(19, .bold).foregroundColor(C.text)
                Spacer()
                Text("\(m.settings.cats.count) مختارة").tf(14, .semibold).foregroundColor(C.amberText)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10 * k), count: cols), spacing: 10 * k) {
                ForEach(m.cats) { c in
                    let n = m.catCounts(c.key)
                    CatCard(c: c, on: m.settings.cats.contains(c.key), left: n.left, all: n.all, lvl: lvl) {
                        focused = nil
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { m.toggleCat(c.key) }
                    }
                }
            }
        }
        .padding(.top, 20 * k)
    }
}

struct Hero: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.accessibilityReduceMotion) var rm
    @State private var float = false
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8 * k) {
                Text("تحدّي").tf(40, .bold).foregroundColor(C.ink)
                    .padding(.horizontal, 22 * k).padding(.top, 2 * k).padding(.bottom, 8 * k)
                    .background(
                        RoundedRectangle(cornerRadius: 18 * k, style: .continuous)
                            .fill(LinearGradient(colors: [C.gold, C.goldL, C.gold], startPoint: .leading, endPoint: .trailing))
                            .shadow(color: C.goldD, radius: 0, x: 0, y: 5 * k)
                            .shadow(color: C.goldD.opacity(0.25), radius: 10 * k, x: 0, y: 10 * k)
                    )
                    .rotationEffect(.degrees(float ? -1 : -2.5))
                    .offset(y: float ? -4 * k : 0)
                    .onAppear { if !rm { withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) { float = true } } }
                Text("مسابقة ثقافية للفرق").tf(14).foregroundColor(C.muted)
            }
            Spacer()
            if m.ready {
                VStack(alignment: .trailing, spacing: 2 * k) {
                    Text(TL.catsWord(m.cats.count)).tf(14).foregroundColor(C.muted)
                    Text(TL.qsWord(m.totalQuestions)).tf(14, .semibold).foregroundColor(C.text)
                }
            }
        }
        .padding(.top, 14 * k).padding(.horizontal, 4 * k)
    }
}

struct TeamField: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    let i: Int
    var focus: FocusState<Int?>.Binding

    var body: some View {
        let name = i < m.settings.teams.count ? m.settings.teams[i] : ""
        let binding = Binding<String>(
            get: { i < m.settings.teams.count ? m.settings.teams[i] : "" },
            set: { v in if i < m.settings.teams.count { m.settings.teams[i] = String(v.prefix(24)) } })
        let isFocused = focus.wrappedValue == i
        return HStack(spacing: 8 * k) {
            Text(initialOf(name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultTeamName(i) : name))
                .tf(18, .bold).foregroundColor(.white)
                .frame(width: 38 * k, height: 38 * k)
                .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color.white.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color.white.opacity(0.4), lineWidth: 1)))
            ZStack(alignment: .leading) {
                if name.isEmpty {
                    Text(defaultTeamName(i)).tf(16, .bold).foregroundColor(.white.opacity(0.62)).lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: binding)
                    .tf(16, .bold)
                    .foregroundColor(.white)
                    .tint(.white)
                    .focused(focus, equals: i)
                    .submitLabel(.done)
                    .onSubmit { focus.wrappedValue = nil }
                    .autocorrectionDisabled()
                    .accessibilityLabel("اسم الفريق \(ORD[min(i, 7)])")
            }
            .padding(.horizontal, 6 * k).padding(.vertical, 8 * k)
            .background(RoundedRectangle(cornerRadius: 10 * k).fill(Color.black.opacity(isFocused ? 0.18 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10 * k).stroke(Color.white.opacity(isFocused ? 0.55 : 0), lineWidth: 1))
        }
        .padding(10 * k)
        .background(RoundedRectangle(cornerRadius: 18 * k, style: .continuous).fill(C.teamGrad(i))
            .shadow(color: Color.black.opacity(0.16), radius: 9 * k, x: 0, y: 8 * k))
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = i }
    }
}

struct CatCard: View {
    @Environment(\.uiScale) var k
    let c: Category
    let on: Bool
    let left: Int
    let all: Int
    let lvl: Int
    let action: () -> Void

    var body: some View {
        let cc = C.cat(c)
        let c1 = cc.0
        let c2 = cc.1
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2 * k) {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark").font(.system(size: 14 * k, weight: .heavy)).foregroundColor(c1)
                        .frame(width: 28 * k, height: 28 * k)
                        .background(Circle().fill(Color.white).shadow(color: .black.opacity(0.3), radius: 3 * k, x: 0, y: 2 * k))
                        .scaleEffect(on ? 1 : 0.01).opacity(on ? 1 : 0)
                }
                Spacer(minLength: 0)
                Text(c.name).tf(18, .bold).foregroundColor(.white).shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text("بقي \(left) من \(all)" + (lvl > 0 ? " · " + (DIFF_NAME[lvl] ?? "") : ""))
                    .tf(13).foregroundColor(.white.opacity(0.95)).shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            .padding(.horizontal, 12 * k).padding(.vertical, 10 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 132 * k)
            .background(
                // الصورة والتدرّج خلف المحتوى، فلا تؤثر في مقاس البطاقة
                ZStack {
                    C.catGrad(c)
                    if c.photo == nil {
                        Text(c.glyph).tf(80, .bold).foregroundColor(.white.opacity(0.13))
                    }
                    CachedImage(url: c.photoURL(600))
                        .saturation(on ? 1 : 0.55).brightness(on ? 0 : -0.05)
                        .scaleEffect(on ? 1.06 : 1)
                    LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: c2.opacity(0.78), location: 0.66), .init(color: c2, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    if !on { Color.white.opacity(0.18) }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22 * k, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22 * k, style: .continuous).strokeBorder(Color.white, lineWidth: on ? 3 * k : 0))
            .background(RoundedRectangle(cornerRadius: 25 * k, style: .continuous).fill(on ? c1 : .clear).padding(-3 * k))
            .shadow(color: Color.black.opacity(on ? 0.22 : 0.14), radius: (on ? 12 : 8) * k, x: 0, y: (on ? 8 : 5) * k)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(c.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// ضغطة خفيفة تصغّر العنصر قليلاً
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct Seg<V: Hashable>: View {
    @Environment(\.uiScale) var k
    let items: [(String, V)]
    let value: V
    let set: (V) -> Void
    var body: some View {
        HStack(spacing: 3 * k) {
            ForEach(items.indices, id: \.self) { i in
                let on = items[i].1 == value
                Button { set(items[i].1) } label: {
                    Text(items[i].0).tf(13, .semibold).foregroundColor(on ? C.ink : Color(hex: "#374151"))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44 * k)
                        .background(RoundedRectangle(cornerRadius: 11 * k, style: .continuous).fill(on ? C.gold : Color.clear)
                            .shadow(color: on ? C.goldD : .clear, radius: 0, x: 0, y: 3 * k))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3 * k)
        .background(RoundedRectangle(cornerRadius: 14 * k, style: .continuous).fill(C.seg))
    }
}

struct SettingsCard: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k

    func lbl(_ s: String) -> some View { Text(s).tf(14).foregroundColor(C.muted).padding(.bottom, 6 * k) }
    func hint(_ s: String) -> some View { Text(s).tf(13).foregroundColor(C.muted).fixedSize(horizontal: false, vertical: true).padding(.top, 6 * k) }
    func toggle(_ s: String, _ kp: WritableKeyPath<Settings, Bool>) -> some View {
        HStack(spacing: 10 * k) {
            Text(s).tf(14).foregroundColor(C.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8 * k)
            Toggle("", isOn: Binding(get: { m.settings[keyPath: kp] }, set: { m.settings[keyPath: kp] = $0 }))
                .labelsHidden().tint(Color(hex: "#E9B400"))
        }
        .frame(minHeight: 48 * k)
    }

    var body: some View {
        let s = m.settings
        let board = s.mode == 1
        VStack(alignment: .leading, spacing: 0) {
            Text("الإعدادات").tf(18, .bold).foregroundColor(C.accentD).padding(.bottom, 4 * k)
            Group {
                VStack(alignment: .leading, spacing: 0) {
                    lbl("حجم الخط")
                    Seg(items: [("صغير جداً", 70), ("صغير", 80), ("متوسط", 90), ("كبير", 100)], value: s.scale) { m.settings.scale = $0 }
                }.padding(.vertical, 8 * k)
                VStack(alignment: .leading, spacing: 0) {
                    lbl("طريقة اللعب")
                    Seg(items: [("بالتتابع", 0), ("لوحة الأسئلة", 1)], value: s.mode) { v in withAnimation { m.settings.mode = v } }
                    hint(board
                         ? "كل فريق في دوره يختار أي خانة من اللوحة: أي قسم وأي مستوى. لكل قسم صف فيه سهل ومتوسط وصعب وصعب جداً، ولكل فريق خانة في كل مستوى."
                         : "تأتي الأسئلة بالجولات: في كل جولة يأخذ كل فريق سؤالاً من القسم نفسه، والأقسام تتناوب.")
                }.padding(.vertical, 8 * k)
                VStack(alignment: .leading, spacing: 0) {
                    lbl("مستوى الأسئلة")
                    if board {
                        Seg(items: [("مختلط", "mixed"), ("مستوى ثابت", "fixed")], value: s.effDiffMode) { m.settings.diffMode = $0 }
                    } else {
                        Seg(items: [("مختلط", "mixed"), ("يختاره الفريق", "team"), ("مستوى ثابت", "fixed")], value: s.diffMode) { m.settings.diffMode = $0 }
                    }
                    if s.effDiffMode == "fixed" {
                        Seg(items: [("سهل", 1), ("متوسط", 2), ("صعب", 3), ("صعب جداً", 4)], value: s.level) { m.settings.level = $0 }
                            .padding(.top, 6 * k)
                    }
                    hint(diffHint(s))
                }.padding(.vertical, 8 * k)
                if board {
                    BoardSizeNote().padding(.vertical, 8 * k)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        lbl("عدد الأسئلة لكل فريق")
                        Seg(items: [("5", 5), ("10", 10), ("15", 15), ("20", 20), ("30", 30)], value: s.perTeam) { m.settings.perTeam = $0 }
                    }.padding(.vertical, 8 * k)
                }
                VStack(alignment: .leading, spacing: 0) {
                    lbl("وقت السؤال")
                    Seg(items: [("بلا", 0), ("15ث", 15), ("30ث", 30), ("45ث", 45), ("60ث", 60)], value: s.timer) { m.settings.timer = $0 }
                }.padding(.vertical, 8 * k)
            }
            toggle("السرقة: إذا أخطأ الفريق يحاول غيره بنصف النقاط قبل كشف الإجابة", \.steal)
            toggle("وسيلة «حذف إجابتين» مرة لكل فريق", \.fifty)
            toggle("وضع المضيف: الخيارات مخفية ويجيب الفريق شفهياً", \.host)
            if s.host {
                hint("يقرأ المقدِّم السؤال ويجيب الفريق بلا خيارات. إن طلب الفريق الخيارات أخذ نصف النقاط. ثم يكشف المقدِّم الإجابة ويحكم: صح، أو سرقة لمن قال جوابه قبل الكشف، أو لم يُصب أحد. وفي «من أنا؟» تبقى الخيارات مخفية، فتصير لمكافأة التلميحات قيمة.")
            }
            toggle("الأصوات", \.sound)
            PointsNote().padding(.top, 10 * k)
        }
        .card(k)
    }

    func diffHint(_ s: Settings) -> String {
        switch s.effDiffMode {
        case "fixed": return s.mode == 1 ? "كل خانات اللوحة من المستوى المختار." : "كل الأسئلة من المستوى المختار."
        case "team": return "في بداية كل دور يختار الفريق مستوى سؤاله ونقاطه قبل أن يظهر السؤال، والقسم واحد لكل الفرق في الجولة."
        default: return s.mode == 1 ? "في اللوحة كل المستويات، ويختار الفريق ما يشاء منها." : "في كل جولة مستوى واحد لكل الفرق، ويتغير من جولة إلى أخرى."
        }
    }
}

/// عدد أسئلة اللوحة، وتنبيه إذا طالت
struct BoardSizeNote: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    var body: some View {
        let s = m.settings
        let n = s.boardSize
        VStack(alignment: .leading, spacing: 6 * k) {
            HStack(spacing: 8 * k) {
                Image(systemName: "square.grid.3x3.fill").foregroundColor(C.accent).font(.system(size: 16 * k))
                Text("في اللوحة \(TL.qsWord(n))").tf(15, .bold).foregroundColor(C.text)
            }
            Text("\(TL.catsWord(s.cats.count)) × 4 مستويات × \(s.teams.count == 1 ? "فريق واحد" : s.teams.count == 2 ? "فريقان" : "\(s.teams.count) فرق") — لكل فريق \(TL.qsWord(n / max(1, s.teams.count))).")
                .tf(13).foregroundColor(C.muted).fixedSize(horizontal: false, vertical: true)
            if n > 48 {
                HStack(alignment: .top, spacing: 6 * k) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Color(hex: "#D97706"))
                    Text("مسابقة طويلة: أكثر من 48 سؤالاً. قلّلوا الأقسام أو الفرق إن أردتم مسابقة أقصر.")
                        .tf(13, .medium).foregroundColor(C.amberText).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10 * k)
                .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color(hex: "#FFFBEB")))
                .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color(hex: "#FCD34D"), lineWidth: 1))
            }
        }
        .padding(12 * k)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14 * k).fill(Color(hex: "#EFF6FF")))
    }
}

/// شرح النقاط بالكلمات وألوان المستويات
struct PointsNote: View {
    @Environment(\.uiScale) var k
    var body: some View {
        VStack(spacing: 8 * k) {
            HStack(spacing: 6 * k) {
                ForEach(1...4, id: \.self) { d in DiffChip(d: d, pts: TL.fmtPts(Double(d)), size: 12) }
            }
            Text("«من أنا؟» وأسئلة التلميحات: نقطة إضافية عن كل تلميح لم يُكشف\nالسرقة بنصف نقاط السؤال، و«½» معناها نصف نقطة\nلكل فريق مرة واحدة: حذف إجابتين، وتبديل السؤال")
                .tf(13).foregroundColor(C.muted).multilineTextAlignment(.center).lineSpacing(3 * k)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResumeBox: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    var body: some View {
        if let g = m.game {
            VStack(spacing: 8 * k) {
                Text("عندك مسابقة لم تكتمل").tf(16, .bold).foregroundColor(C.amberText)
                FlowChips(items: g.teams.enumerated().map { ($0.offset, "\($0.element.name)  \(fmtPts($0.element.score))") })
                Text(progressText(g)).tf(13).foregroundColor(C.muted)
                HStack(spacing: 10 * k) {
                    Button("متابعتها") { m.resumeSaved() }.buttonStyle(PrimaryStyle(k: k))
                    Button("حذفها") { m.discardSaved() }.buttonStyle(GhostStyle(k: k))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14 * k)
            .background(RoundedRectangle(cornerRadius: 20 * k).fill(Color(hex: "#FFFBEB")))
            .overlay(RoundedRectangle(cornerRadius: 20 * k).stroke(Color(hex: "#FCD34D"), lineWidth: 2))
        }
    }
    func progressText(_ g: GameState) -> String {
        if g.mode == 1 { return "اللوحة: تمّ \(g.boardCells.filter { $0.used }.count) من \(g.boardCells.count)" }
        let r = g.ti < g.turns.count ? g.turns[g.ti].round : 0
        return "الجولة \(r + 1) من \(g.rounds)"
    }
}

/// شرائح ملونة بألوان الفرق، تلتف على أكثر من سطر
struct FlowChips: View {
    @Environment(\.uiScale) var k
    let items: [(Int, String)]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 120 * k), spacing: 8 * k)]
        LazyVGrid(columns: cols, spacing: 6 * k) {
            ForEach(items.indices, id: \.self) { j in
                Text(items[j].1).tf(14, .bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 12 * k).padding(.vertical, 4 * k)
                    .background(Capsule().fill(C.teamGrad(items[j].0)))
            }
        }
    }
}

struct LoadErrorBox: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    var body: some View {
        VStack(spacing: 8 * k) {
            Text("تعذّر تحميل: \(m.failed.joined(separator: "، ")).").tf(14).foregroundColor(Color(hex: "#B91C1C")).multilineTextAlignment(.center)
            Button("أعد المحاولة") { m.loadBank(); m.loadLedger() }.buttonStyle(GhostStyle(k: k, small: true))
        }
        .frame(maxWidth: .infinity).card(k)
        .overlay(RoundedRectangle(cornerRadius: 20 * k).stroke(Color(hex: "#FCA5A5"), lineWidth: 2))
    }
}

struct FooterLinks: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    func link(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).tf(14).underline().foregroundColor(C.muted).padding(.horizontal, 8 * k).frame(minHeight: 44 * k) }
            .buttonStyle(.plain)
    }
    var body: some View {
        VStack(spacing: 6 * k) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * k), spacing: 4 * k)], spacing: 0) {
                link("نقل السجل بين الأجهزة") { m.open(.history) }
                link("الأسئلة المُبلَّغ عنها" + (m.reports.isEmpty ? "" : " (\(m.reports.count))")) { m.open(.reports) }
                link("التشخيص" + (m.rejectedCount > 0 ? " (\(m.rejectedCount))" : "")) { m.open(.diag) }
                link("تصفير الأسئلة المستعملة") {
                    m.alert = AppAlert(title: "تصفير السجل؟", message: "تعود كل الأسئلة المستعملة متاحة، وقد تتكرر عليكم. ننصح بتصدير السجل قبل ذلك.", buttons: [
                        AlertButton(title: "نعم، صفّر", role: .destructive) { m.setUsed([String]()); m.showToast("تم التصفير") },
                        AlertButton(title: "إلغاء", role: .cancel),
                    ])
                }
            }
            if m.ready {
                Text("مجموع الأسئلة: \(m.totalQuestions) · المستعمل منها: \(m.usedInBank)").tf(12).foregroundColor(C.muted)
            }
            Text("الإصدار \(AppModel.version)").tf(12).foregroundColor(C.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14 * k)
    }
}

struct StartBar: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    @Environment(\.accessibilityReduceMotion) var rm
    @State private var glow = false

    var chips: [String] {
        let s = m.settings
        let diff: String = ["mixed": "مستوى مختلط", "team": "المستوى يختاره الفريق", "fixed": "مستوى \(DIFF_NAME[s.level] ?? "")"][s.effDiffMode] ?? ""
        return [s.mode == 1 ? "لوحة: \(TL.qsWord(s.boardSize))" : "بالتتابع · \(s.perTeam) لكل فريق", diff, s.timer > 0 ? "\(s.timer) ث" : "بلا وقت", s.host ? "وضع المضيف" : ""].filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 6 * k) {
            Button {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                m.requestStart()
            } label: {
                Text(m.ready ? "ابدأ المسابقة" : (m.failed.isEmpty ? "جارٍ تحميل الأسئلة…" : "تعذّر تحميل الأسئلة"))
            }
            .buttonStyle(PrimaryStyle(k: k, big: true, enabled: m.ready))
            .disabled(!m.ready)
            .background(
                RoundedRectangle(cornerRadius: 26 * k).stroke(C.gold.opacity(glow ? 0 : 0.55), lineWidth: glow ? 14 * k : 2)
                    .padding(.bottom, 7 * k)
            )
            .onAppear { if !rm { withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { glow = true } } }
            HStack(spacing: 6 * k) {
                ForEach(chips, id: \.self) { c in
                    Text(c).tf(12).foregroundColor(Color(hex: "#374151")).lineLimit(1)
                        .padding(.horizontal, 10 * k).padding(.vertical, 4 * k)
                        .background(Capsule().fill(Color.white).overlay(Capsule().stroke(C.line, lineWidth: 1)))
                }
            }
        }
        .frame(maxWidth: wide ? 560 : .infinity)
        .padding(.horizontal, 14 * k)
        .padding(.top, 10 * k)
        .padding(.bottom, 4 * k)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [C.bg.opacity(0), C.bg.opacity(0.96), C.bg], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)).ignoresSafeArea())
    }
}
