// تحدّي — مسابقة ثقافية للفرق. تطبيق SwiftUI أصلي للآيفون والآيباد (بلا صفحة ويب).
import SwiftUI
import UIKit

@main
struct TahaddiApp: App {
    @StateObject private var model = AppModel(shotMode: Shot.name != nil)
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Fonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
                .preferredColorScheme(.light)
                .onAppear {
                    KeyboardDismisser.install()
                    #if DEBUG
                    Shot.afterLaunch(model)
                    #endif
                    if Shot.name == nil { WebMigration.runIfNeeded(model) }
                }
        }
        .onChange(of: scenePhase) { p in
            if p == .background || p == .inactive { model.appBackgrounded() }
        }
    }
}

/// يغلق لوحة المفاتيح عند لمس أي مكان خارج حقل الكتابة
@MainActor
enum KeyboardDismisser {
    final class Delegate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var v: UIView? = touch.view
            while let x = v { if x is UITextField || x is UITextView { return false }; v = x.superview }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc func tapped(_ g: UITapGestureRecognizer) { g.view?.window?.endEditing(true) }
    }
    static let delegate = Delegate()
    static var installed = false
    static func install() {
        if installed { return }
        Task { @MainActor in
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
            guard let w = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
            let t = UITapGestureRecognizer(target: delegate, action: #selector(Delegate.tapped(_:)))
            t.cancelsTouchesInView = false
            t.delegate = delegate
            w.addGestureRecognizer(t)
            installed = true
        }
    }
}

struct RootView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            let k = CGFloat(m.settings.scale) / 100 * (wide ? 1.3 : 1)
            ZStack {
                Background(tint: m.screen == .game ? m.turnColorTeam : nil)
                Group {
                    switch m.screen {
                    case .home: HomeView()
                    case .game: GameView()
                    case .result: ResultView()
                    }
                }
                .transition(.opacity)
                if let t = m.toast {
                    VStack {
                        Spacer()
                        Text(t).tf(16, .bold).foregroundColor(C.ink).multilineTextAlignment(.center)
                            .padding(.horizontal, 18 * k).padding(.vertical, 11 * k)
                            .background(RoundedRectangle(cornerRadius: 14 * k).fill(C.gold)
                                .shadow(color: C.goldD, radius: 0, x: 0, y: 5 * k)
                                .shadow(color: .black.opacity(0.25), radius: 12 * k, x: 0, y: 8 * k))
                            .padding(.horizontal, 16).padding(.bottom, 90 * k)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(30)
                }
            }
            .environment(\.uiScale, k)
            .environment(\.wide, wide)
            .animation(.easeInOut(duration: 0.25), value: m.screen)
            .alert(m.alert?.title ?? "", isPresented: Binding(get: { m.alert != nil }, set: { if !$0 { m.alert = nil } }), presenting: m.alert) { a in
                ForEach(a.buttons) { b in
                    Button(b.title, role: b.role) {
                        // يُنفَّذ بعد إغلاق النافذة حتى تستطيع فتح نافذة أخرى
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            b.action()
                        }
                    }
                }
            } message: { a in Text(a.message) }
            .sheet(item: $m.sheet, onDismiss: { m.autoResume() }) { kind in
                SheetHost(kind: kind)
                    .environmentObject(m)
                    .environment(\.uiScale, wide ? k / 1.15 : k)
                    .environment(\.wide, wide)
                    .environment(\.layoutDirection, .rightToLeft)
                    .environment(\.locale, Locale(identifier: "ar"))
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// الخلفية الفاتحة، وتُصبغ بلون الفريق صاحب الدور أثناء اللعب
struct Background: View {
    let tint: Int?
    var body: some View {
        ZStack {
            C.bg
            if let t = tint {
                C.team(t).opacity(0.16)
                LinearGradient(colors: [C.team(t).opacity(0.22), C.team(t).opacity(0.06)], startPoint: .top, endPoint: .bottom)
            } else {
                RadialGradient(colors: [Color(hex: "#DBEAFE"), Color(hex: "#DBEAFE").opacity(0)], center: .topLeading, startRadius: 0, endRadius: 420)
                RadialGradient(colors: [Color(hex: "#FCE7F3"), Color(hex: "#FCE7F3").opacity(0)], center: UnitPoint(x: 1, y: 0.08), startRadius: 0, endRadius: 380)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: tint)
    }
}

/// مضيف النوافذ
struct SheetHost: View {
    let kind: SheetKind
    var body: some View {
        switch kind {
        case .team(let i): TeamEditSheet(i: i)
        case .menu: MenuSheet()
        case .report: ReportSheet()
        case .reports: ReportsSheet()
        case .history: HistorySheet()
        case .diag: DiagSheet()
        }
    }
}

extension AppModel {
    func open(_ s: SheetKind) {
        if screen == .game { autoPause() }
        sheet = s
    }
}
