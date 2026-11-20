// مخزن التطبيق: تحميل الأسئلة من داخل التطبيق، والإعدادات، وسجل المستعمل (لا تكرار أبداً)، والبلاغات، والإحصاء،
// وحفظ المسابقة الجارية حتى تُستأنف ولو أُغلق التطبيق. كل شيء ملفات JSON في Application Support.
import Foundation
import SwiftUI
import UIKit

enum Screen { case home, game, result }

struct AlertButton: Identifiable {
    let id = UUID()
    let title: String
    var role: ButtonRole? = nil
    var action: @MainActor () -> Void = {}
}
struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var buttons: [AlertButton]
}

enum SheetKind: Identifiable, Equatable {
    case team(Int), menu, report, reports, history, diag
    var id: String {
        switch self {
        case .team(let i): return "team\(i)"
        case .menu: return "menu"
        case .report: return "report"
        case .reports: return "reports"
        case .history: return "history"
        case .diag: return "diag"
        }
    }
}

struct FXEvent: Equatable {
    let id = UUID()
    let ok: Bool
    var team: Int? = nil
    var pts: Double? = nil
    var opt: Int? = nil
    var burst: Bool = true
}

struct ResultSummary {
    struct Row { let i: Int; let team: Team }
    let teams: [Team]
    var ranked: [Row] { teams.enumerated().map { Row(i: $0.offset, team: $0.element) }.sorted { a, b in a.team.score == b.team.score ? a.i < b.i : a.team.score > b.team.score } }
}

@MainActor
final class AppModel: ObservableObject {
    static let version: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "2"

    // البيانات
    @Published var cats: [Category] = []
    var catByKey: [String: Category] = [:]
    var bank: [String: [Question]] = [:]
    var index = QIndex()
    var clubs: [String: Club] = [:]
    var problems: [Problem] = []
    var failed: [String] = []
    var registrySource = "cats.json"
    @Published var ready = false

    // الإعدادات والسجل
    @Published var settings = Settings() { didSet { if settings != oldValue { saveSettings() } } }
    @Published var used: Set<String> = []
    var usedKeys: Set<String> = []
    @Published var reports: [Report] = []
    var stats: [String: [Int]] = [:]
    var saveFailed = false
    var hadSettingsFile = false

    // الشاشات
    @Published var screen: Screen = .home
    @Published var game: GameState? = nil
    @Published var result: ResultSummary? = nil
    @Published var toast: String? = nil
    @Published var alert: AppAlert? = nil
    @Published var sheet: SheetKind? = nil
    @Published var splash: Int? = nil
    @Published var fx: FXEvent? = nil
    @Published var undoCount = 0
    var undoStack: [Data] = []

    // المؤقت
    var tickTask: Task<Void, Never>? = nil
    var lastSec: Int? = nil
    var autoPaused = false
    var splashTask: Task<Void, Never>? = nil
    var toastTask: Task<Void, Never>? = nil

    let dir: URL
    let shotMode: Bool

    init(shotMode: Bool = false) {
        self.shotMode = shotMode
        let fm = FileManager.default
        if shotMode {
            dir = fm.temporaryDirectory.appendingPathComponent("tahaddi-shot-\(UUID().uuidString)", isDirectory: true)
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
            dir = base.appendingPathComponent("Tahaddi", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        loadBank()
        if let s: Settings = readJSON("settings.json") { settings = s; hadSettingsFile = true } else { settings = Settings() }
        loadLedger()
        if let g: GameState = readJSON("game.json"), g.v == 3, !g.teams.isEmpty { game = g }
    }

    // MARK: - الملفات
    func fileURL(_ name: String) -> URL { dir.appendingPathComponent(name) }
    func readJSON<T: Decodable>(_ name: String) -> T? {
        guard let d = try? Data(contentsOf: fileURL(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    @discardableResult
    func writeJSON<T: Encodable>(_ name: String, _ v: T) -> Bool {
        do {
            let d = try JSONEncoder().encode(v)
            try d.write(to: fileURL(name), options: .atomic)
            return true
        } catch {
            if !saveFailed { showToast("تعذّر الحفظ في ذاكرة الجهاز. صدّروا السجل احتياطاً.") }
            saveFailed = true
            return false
        }
    }
    func removeFile(_ name: String) { try? FileManager.default.removeItem(at: fileURL(name)) }
    func saveSettings() { writeJSON("settings.json", settings) }

    // MARK: - تحميل الأسئلة
    static var dataDir: URL? { Bundle.main.url(forResource: "Data", withExtension: nil) }

    func loadBank() {
        var list: [Category] = []
        registrySource = "cats.json"
        if let dir = AppModel.dataDir,
           let d = try? Data(contentsOf: dir.appendingPathComponent("cats.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let arr = j["categories"] as? [[String: Any]] {
            list = arr.compactMap(Category.init)
        }
        if list.isEmpty {
            registrySource = "النسخة الاحتياطية داخل التطبيق"
            list = AppModel.fallbackCats.compactMap(Category.init)
        }
        var seen = Set<String>()
        list = list.filter { seen.insert($0.key).inserted }
        cats = list
        catByKey = Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
        bank = [:]; problems = []; failed = []
        for c in list {
            let name = (c.file as NSString).lastPathComponent
            guard let dir = AppModel.dataDir,
                  let text = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else {
                bank[c.key] = []; failed.append(c.name); continue
            }
            let r = TL.parseBank(cat: c.key, text: text, clues: c.clues)
            bank[c.key] = r.items
            problems.append(contentsOf: r.problems)
        }
        index = TL.buildIndex(bank)
        clubs = AppModel.loadClubs()
        ready = bank.values.contains { !$0.isEmpty }
    }

    static func loadClubs() -> [String: Club] {
        guard let dir = dataDir, let d = try? Data(contentsOf: dir.appendingPathComponent("clubs.json")) else { return [:] }
        return parseClubs(d)
    }
    static func parseClubs(_ d: Data) -> [String: Club] {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        var out: [String: Club] = [:]
        for (k, v) in j {
            guard let o = v as? [String: Any] else { continue }
            let key = k.lowercased()
            out[key] = Club(key: key, ar: (o["ar"] as? String) ?? k, en: (o["en"] as? String) ?? "",
                            badge: (o["badge"] as? String) ?? "", c1: (o["c1"] as? String) ?? "#334155", c2: (o["c2"] as? String) ?? "#1E293B")
        }
        return out
    }

    static let fallbackCats: [[String: Any]] = [
        ["key": "religion", "name": "الدين", "glyph": "د", "file": "data/religion.txt", "c1": "#059669", "c2": "#047857", "prefix": "r"],
        ["key": "seerah", "name": "السيرة النبوية", "glyph": "س", "file": "data/seerah.txt", "c1": "#0369A1", "c2": "#075985", "prefix": "s"],
        ["key": "history", "name": "التاريخ الإسلامي", "glyph": "ت", "file": "data/history.txt", "c1": "#B45309", "c2": "#92400E", "prefix": "h"],
        ["key": "geography", "name": "الجغرافيا", "glyph": "ج", "file": "data/geography.txt", "c1": "#2563EB", "c2": "#1D4ED8", "prefix": "g"],
        ["key": "poetry", "name": "الشعر", "glyph": "ش", "file": "data/poetry.txt", "c1": "#7C3AED", "c2": "#6D28D9", "prefix": "p"],
        ["key": "arabic", "name": "اللغة العربية", "glyph": "ض", "file": "data/arabic.txt", "c1": "#DC2626", "c2": "#B91C1C", "prefix": "a"],
        ["key": "saudi", "name": "السعودية", "glyph": "ع", "file": "data/saudi.txt", "c1": "#15803D", "c2": "#166534", "prefix": "k"],
        ["key": "whoami", "name": "من أنا؟", "glyph": "أ", "file": "data/whoami.txt", "c1": "#DB2777", "c2": "#BE185D", "prefix": "w", "clues": true],
    ]

    // MARK: - سجل المستعمل والبلاغات والإحصاء
    func loadLedger() {
        let raw: [String] = readJSON("used.json") ?? []
        used = TL.migrateIds(raw, index)
        if used.count != raw.count || raw.contains(where: { !used.contains($0) }) { writeJSON("used.json", Array(used)) }
        usedKeys = TL.usedKeySet(used, index)
        reports = readJSON("reports.json") ?? []
        stats = readJSON("stats.json") ?? [:]
    }
    func q(_ id: String?) -> Question? { id.flatMap { index.byId[$0] } }
    func markUsed(_ id: String) {
        if used.contains(id) { return }
        used.insert(id)
        if let q = q(id) { usedKeys.formUnion(q.keys) }
        writeJSON("used.json", Array(used))
    }
    func setUsed<S: Sequence>(_ ids: S) where S.Element == String {
        used = Set(ids)
        usedKeys = TL.usedKeySet(used, index)
        writeJSON("used.json", Array(used))
    }
    /// سياق الاختيار: المستعمل، ومفاتيحه، وما في المسابقة الحالية
    func ctx(_ matchIds: [String] = []) -> PickContext {
        PickContext(used: used, usedKeys: usedKeys, facts: TL.factsOf(matchIds, index), exclude: Set(matchIds))
    }
    func saveReports() { writeJSON("reports.json", reports) }
    func saveStats() { writeJSON("stats.json", stats) }

    var levelFilter: Int { settings.effDiffMode == "fixed" ? settings.level : 0 }
    var totalQuestions: Int { bank.values.reduce(0) { $0 + $1.count } }
    var usedInBank: Int { used.filter { index.byId[$0] != nil }.count }
    func catCounts(_ k: String) -> (left: Int, all: Int) {
        let lvl = levelFilter
        let all = (bank[k] ?? []).filter { lvl == 0 || $0.d == lvl }
        return (all.filter { TL.isFresh($0, used, usedKeys) }.count, all.count)
    }
    var rejectedCount: Int { problems.filter { $0.level == "error" }.count + failed.count }

    // MARK: - الإعدادات من الرئيسية
    func toggleCat(_ k: String) {
        if settings.cats.contains(k) {
            if settings.cats.count > 1 { settings.cats.removeAll { $0 == k } } else { showToast("اختر قسماً واحداً على الأقل") }
        } else {
            settings.cats = cats.map { $0.key }.filter { $0 == k || settings.cats.contains($0) }
        }
    }
    func normalizeCats() {
        guard !cats.isEmpty else { return }
        let valid = settings.cats.filter { catByKey[$0] != nil }
        if valid != settings.cats || valid.isEmpty { settings.cats = valid.isEmpty ? Array(cats.prefix(4).map { $0.key }) : valid }
    }
    func addTeam() { if settings.teams.count < 8 { settings.teams.append("") } }
    func removeTeam() { if settings.teams.count > 1 { settings.teams.removeLast() } }

    // MARK: - تنبيه عابر
    func showToast(_ s: String, _ secs: Double = 2.2) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { toast = s }
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: - البلاغات
    func saveReport(for q: Question, note: String) {
        let r = Report(id: q.id, cat: catByKey[q.cat]?.name ?? q.cat, q: q.display, a: q.a, note: note, at: AppModel.today())
        if let i = reports.firstIndex(where: { $0.id == q.id }) { reports[i] = r; saveReports(); showToast("حُدِّث البلاغ") }
        else { reports.append(r); saveReports(); showToast("حُفظ البلاغ") }
    }
    var reportsText: String {
        reports.enumerated().map { i, r in
            let sid = r.id.map { id -> String in let p = id.split(separator: ":", maxSplits: 1); return " (\(p.count == 2 ? String(p[1]) : id))" } ?? ""
            var s = "\(i + 1)) [\(r.cat ?? "")]\(sid) \(r.q ?? "")\nالإجابة المعتمدة: \(r.a ?? "")"
            if let n = r.note, !n.isEmpty { s += "\nالملاحظة: " + n }
            return s
        }.joined(separator: "\n\n")
    }
    static func today() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - نقل السجل
    func historyObject() -> [String: Any] {
        let reps: [[String: Any]] = reports.map { r in
            var o: [String: Any] = [:]
            if let v = r.id { o["id"] = v }; if let v = r.cat { o["cat"] = v }; if let v = r.q { o["q"] = v }
            if let v = r.a { o["a"] = v }; if let v = r.note { o["note"] = v }; if let v = r.at { o["at"] = v }
            return o
        }
        let iso = ISO8601DateFormatter().string(from: Date())
        return ["app": "tahaddi", "format": 1, "version": AppModel.version, "at": iso, "used": Array(used), "reports": reps, "stats": stats]
    }
    func historyJSON(pretty: Bool = false) -> Data {
        (try? JSONSerialization.data(withJSONObject: historyObject(), options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])) ?? Data()
    }
    /// يدمج سجلاً مستورداً ويعيد رسالة النتيجة
    func importHistory(_ obj: [String: Any]) throws -> String {
        guard (obj["app"] as? String) == "tahaddi", let usedArr = obj["used"] as? [Any] else {
            throw HistoryError.msg("الملف ليس سجلاً من «تحدّي»")
        }
        let incUsed = Array(TL.migrateIds(usedArr.compactMap { $0 as? String }, index))
        let incReports = (obj["reports"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        var incStats: [String: [Int]] = [:]
        if let s = obj["stats"] as? [String: Any] {
            for (k, v) in s { if let a = v as? [Any] { incStats[k] = a.map { ($0 as? NSNumber)?.intValue ?? Int("\($0)") ?? 0 } } }
        }
        let localReports: [[String: Any]] = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(reports))) as? [[String: Any]] ?? []
        let m = TL.mergeHistory(TL.History(used: Array(used), reports: localReports, stats: stats),
                                TL.History(used: incUsed, reports: incReports, stats: incStats))
        setUsed(m.merged.used)
        reports = m.merged.reports.compactMap { o in
            guard let d = try? JSONSerialization.data(withJSONObject: o) else { return nil }
            return try? JSONDecoder().decode(Report.self, from: d)
        }
        saveReports()
        stats = m.merged.stats; saveStats()
        return "أُضيف \(TL.qsWord(m.addedUsed)) إلى المستعمل، و\(m.addedReports) بلاغاً جديداً، ودُمج إحصاء الأسئلة. لم يُحذف شيء من سجل هذا الجهاز."
    }

    // MARK: - التصفير
    func resetUsedForSelected() {
        let lvl = levelFilter
        let ids = Set(settings.cats.flatMap { (bank[$0] ?? []).filter { lvl == 0 || $0.d == lvl }.map { $0.id } })
        setUsed(used.filter { !ids.contains($0) })
        showToast("تم التصفير")
    }
}

enum HistoryError: Error, LocalizedError {
    case msg(String)
    var errorDescription: String? { if case .msg(let s) = self { return s }; return nil }
}
