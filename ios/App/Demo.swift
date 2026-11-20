// وضع التصوير (للبناء على المحاكي): وسيط التشغيل «-shot <اسم>» يفتح شاشة بعينها ببيانات تجريبية،
// و«-selfcheck» يشغّل فحوص المنطق ويكتب نتيجتها في Documents/selfcheck.txt. لا يمس سجل اللاعبين الحقيقي.
import SwiftUI
import UIKit

enum Shot {
    static let name: String? = {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-shot"), i + 1 < a.count { return a[i + 1] }
        return nil
    }()
    static var selfcheck: Bool { ProcessInfo.processInfo.arguments.contains("-selfcheck") }

    #if DEBUG
    @MainActor static var launched = false
    @MainActor static func afterLaunch(_ m: AppModel) {
        // يُستدعى مرة واحدة: تدوير الآيباد قد يعيد ظهور الواجهة فيُستدعى onAppear ثانية
        if launched { return }
        launched = true
        if selfcheck { runSelfCheck() }
        guard let n = name else { return }
        if UIDevice.current.userInterfaceIdiom == .pad { rotate(0) }
        setup(m, n)
        let wait: Double = ["splash": 1.2, "answered": 3.4, "steal": 3.4, "host": 3.4, "sheet": 3.4, "result": 1.5, "home": 2.5, "settings": 2.5, "teams": 2.5][n] ?? 2.2
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? "ready \(n)".write(to: docs.appendingPathComponent("shot-ready.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// الآيباد أفقياً للتصوير (يُعاد الطلب حتى يصير المشهد نشطاً)
    @MainActor static func rotate(_ attempt: Int) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if scene.interfaceOrientation.isLandscape { return }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { err in
            try? "attempt \(attempt): \(err.localizedDescription)".write(to: docs.appendingPathComponent("orient.txt"), atomically: true, encoding: .utf8)
        }
        if attempt < 4 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                rotate(attempt + 1)
            }
        }
    }

    @MainActor static func runSelfCheck() {
        var r = SelfCheck.run(dataDir: AppModel.dataDir)
        // رمز السجل: ذهاب وإياب
        let obj: [String: Any] = ["app": "tahaddi", "format": 1, "used": ["religion:r0001", "history:h0002"], "reports": [], "stats": ["religion:r0001": [1, 0, 0]]]
        if let d = try? JSONSerialization.data(withJSONObject: obj),
           let back = try? HistoryCode.decode(HistoryCode.encode(d)),
           (back["used"] as? [String]) == ["religion:r0001", "history:h0002"] {
            r.text += "\nhistory code roundtrip ok"
        } else { r.ok = false; r.text += "\nFAIL: history code roundtrip" }
        // رمز مضغوط من نسخة الويب (CompressionStream deflate) لـ {"app":"tahaddi","used":["a:1"]}
        let web = "TAHADDI1Z:eJyrVkosKFCyUipJzEhMSclU0lEqLU5NUbKKVkq0MlSKrQUAqQQJ7g=="
        if let w = try? HistoryCode.decode(web), (w["used"] as? [String]) == ["a:1"] { r.text += "\nweb code ok" }
        else { r.text += "\nweb code: could not decode (check sample)" }
        let out = (r.ok ? "SELFCHECK OK\n" : "SELFCHECK FAILED\n") + r.text
        NSLog("%@", out)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? out.write(to: docs.appendingPathComponent("selfcheck.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor static func firstQ(_ m: AppModel, _ cat: String, _ d: Int, _ ok: (Question) -> Bool = { _ in true }) -> Question? {
        (m.bank[cat] ?? []).first { $0.d == d && ok($0) } ?? (m.bank[cat] ?? []).first
    }
    static func short(_ q: Question) -> Bool {
        !q.q.contains("\n") && ([q.a] + q.w).allSatisfy { $0.count <= 22 } && q.q.count < 90
    }

    @MainActor static func seqGame(_ m: AppModel, _ q: Question, teams: [Team]) -> GameState {
        var g = GameState(mode: 0, settings: m.settings, teams: teams)
        let cats = m.settings.cats
        g.turns = (0..<20).map { DealTurn(round: $0 / 2, team: $0 % 2, cat: cats[($0 / 2) % cats.count], d: 1 + ($0 / 2) % 4, id: nil) }
        g.rounds = 10
        g.ti = 6
        g.turns[6].cat = q.cat
        g.turns[6].d = q.d
        g.turns[6].id = q.id
        m.openQuestion(&g, q.id)
        return g
    }

    @MainActor static func setup(_ m: AppModel, _ n: String) {
        var s = Settings()
        s.teams = ["الصقور", "النجوم"]
        s.cats = ["religion", "history", "geography", "poetry"]
        s.timer = 30
        m.settings = s
        let two = [Team(name: "الصقور", score: 7, ok: 3, steals: 1, bad: 1, fifty: false, swap: true),
                   Team(name: "النجوم", score: 5.5, ok: 2, steals: 1, bad: 2, fifty: true, swap: false)]
        switch n {
        case "home":
            m.settings.teams = ["", ""]
        case "settings":
            m.settings.teams = ["", ""]
            m.settings.mode = 1
        case "teams":
            m.settings.teams = ["الصقور", "", "النجوم"]
        case "splash", "question":
            if let q = firstQ(m, "geography", 2, short) { m.beginGame(seqGame(m, q, teams: two)) }
        case "answered":
            if let q = firstQ(m, "geography", 2, short) {
                m.beginGame(seqGame(m, q, teams: two))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    if let i = m.game?.order.firstIndex(of: 0) { m.answer(i) }
                }
            }
        case "steal":
            if let q = firstQ(m, "history", 3, short) {
                m.beginGame(seqGame(m, q, teams: two))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    if let i = m.game?.order.firstIndex(where: { $0 != 0 }) { m.answer(i) }
                }
            }
        case "host":
            m.settings.host = true
            if let q = firstQ(m, "geography", 3, short) {
                m.beginGame(seqGame(m, q, teams: two))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    m.hostReveal()
                }
            }
        case "sheet":
            if let q = firstQ(m, "geography", 1, short) {
                m.beginGame(seqGame(m, q, teams: two))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    m.open(.team(0))
                }
            }
        case "poem":
            if let q = firstQ(m, "poetry", 1, { $0.q.contains("\n") }) { m.beginGame(seqGame(m, q, teams: two)) }
        case "whoami":
            m.settings.cats = ["whoami", "history", "geography", "poetry"]
            if let q = firstQ(m, "whoami", 2) {
                var g = seqGame(m, q, teams: two)
                g.shown = 2
                m.beginGame(g)
            }
        case "clubs":
            // سؤال «مسيرة اللاعب» حقيقي من قسم كرة القدم، بشعارات الأندية من data/clubs.json
            m.settings.cats = ["football", "history", "geography", "poetry"].filter { m.catByKey[$0] != nil }
            let career = (m.bank["football"] ?? []).filter { q in (q.clues?.count ?? 0) >= 5 && (q.clues ?? []).allSatisfy { $0.hasPrefix("@") } }
            if let q = career.first(where: { $0.d == 1 }) ?? career.first {
                var g = seqGame(m, q, teams: two)
                g.shown = min(4, q.clues?.count ?? 1)
                m.beginGame(g)
            }
        case "board":
            m.settings.mode = 1
            let b = TL.buildBoard(bank: m.bank, cats: m.settings.cats, nTeams: 2, ctx: m.ctx(), rng: seededRNG(5))
            var g = GameState(mode: 1, settings: m.settings, teams: two)
            g.board = b.rows
            let marks: [(Int, Int, Int, Int, Int?)] = [(0, 0, 0, 0, 0), (0, 1, 1, 1, 1), (1, 2, 0, 0, nil), (2, 0, 1, 1, 0), (3, 3, 0, 0, 0), (1, 0, 1, 1, 1)]
            for (r, gi, ci, by, win) in marks where r < g.board.count && gi < g.board[r].groups.count && ci < g.board[r].groups[gi].cells.count {
                g.board[r].groups[gi].cells[ci].used = true
                g.board[r].groups[gi].cells[ci].by = by
                g.board[r].groups[gi].cells[ci].win = win
            }
            g.seen = g.boardCells.map { $0.id }
            g.turn = 0
            m.beginGame(g)
        case "result":
            m.result = ResultSummary(teams: [
                Team(name: "الصقور", score: 14.5, ok: 6, steals: 2, bad: 2, fifty: false, swap: false),
                Team(name: "النجوم", score: 11, ok: 5, steals: 1, bad: 4, fifty: false, swap: true),
                Team(name: "الفرسان", score: 9, ok: 4, steals: 0, bad: 6, fifty: true, swap: false),
            ])
            m.screen = .result
        default:
            break
        }
    }
    #endif
}
