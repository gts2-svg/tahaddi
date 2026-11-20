// النماذج: الأقسام، والإعدادات، وحالة المسابقة المحفوظة.
import Foundation

struct Category: Identifiable, Hashable {
    let key: String
    let name: String
    let glyph: String
    let file: String
    let color: String
    let c1: String
    let c2: String
    let prefix: String
    let clues: Bool
    let photo: String?
    var id: String { key }

    init?(_ j: [String: Any]) {
        guard let key = j["key"] as? String, !key.isEmpty, let file = j["file"] as? String, !file.isEmpty else { return nil }
        self.key = key
        self.file = file
        name = (j["name"] as? String) ?? key
        glyph = (j["glyph"] as? String) ?? ""
        color = (j["color"] as? String) ?? "#5B4A8A"
        c1 = (j["c1"] as? String) ?? color
        c2 = (j["c2"] as? String) ?? color
        prefix = (j["prefix"] as? String) ?? ""
        clues = (j["clues"] as? Bool) ?? false
        let p = (j["photo"] as? String) ?? ""
        photo = p.isEmpty ? nil : p
    }

    func photoURL(_ w: Int) -> URL? {
        guard let p = photo else { return nil }
        return URL(string: "https://images.unsplash.com/photo-\(p)?auto=format&fit=crop&w=\(w)&q=60")
    }
}

/// نادٍ لتلميحات «@مفتاح» (data/clubs.json)
struct Club: Hashable {
    let key: String
    let ar: String
    let en: String
    let badge: String
    let c1: String
    let c2: String
}

let DIFF_NAME = [1: "سهل", 2: "متوسط", 3: "صعب", 4: "صعب جداً"]
let ORD = ["الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن"]
func defaultTeamName(_ i: Int) -> String { "الفريق " + (i < ORD.count ? ORD[i] : String(i + 1)) }

struct Settings: Codable, Equatable {
    /// أسماء الفرق كما كُتبت؛ الفارغ يلعب بالاسم الافتراضي («الفريق الأول»…)
    var teams: [String] = ["", ""]
    var cats: [String] = ["religion", "history", "geography", "poetry"]
    var diffMode: String = "mixed"
    var level: Int = 2
    var perTeam: Int = 10
    var timer: Int = 30
    var mode: Int = 0
    var steal: Bool = true
    var fifty: Bool = true
    var sound: Bool = true
    var host: Bool = false
    var scale: Int = 80

    enum CodingKeys: String, CodingKey {
        case teams, cats, diffMode, level, perTeam, timer, mode, steal, fifty, sound, host, scale
    }

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        teams = (try? c.decodeIfPresent([String].self, forKey: .teams)) ?? d.teams
        cats = (try? c.decodeIfPresent([String].self, forKey: .cats)) ?? d.cats
        diffMode = (try? c.decodeIfPresent(String.self, forKey: .diffMode)) ?? d.diffMode
        level = Settings.int(c, .level) ?? d.level
        perTeam = Settings.int(c, .perTeam) ?? d.perTeam
        timer = Settings.int(c, .timer) ?? d.timer
        mode = Settings.int(c, .mode) ?? d.mode
        steal = (try? c.decodeIfPresent(Bool.self, forKey: .steal)) ?? d.steal
        fifty = (try? c.decodeIfPresent(Bool.self, forKey: .fifty)) ?? d.fifty
        sound = (try? c.decodeIfPresent(Bool.self, forKey: .sound)) ?? d.sound
        host = (try? c.decodeIfPresent(Bool.self, forKey: .host)) ?? d.host
        scale = Settings.int(c, .scale) ?? d.scale
        sanitize()
    }
    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: k) { return v }
        if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return Int(v) }
        return nil
    }
    mutating func sanitize() {
        if !["fixed", "mixed", "team"].contains(diffMode) { diffMode = "mixed" }
        if !(1...4).contains(level) { level = 2 }
        if ![5, 10, 15, 20, 30].contains(perTeam) { perTeam = 10 }
        if ![0, 15, 30, 45, 60].contains(timer) { timer = 30 }
        if ![0, 1].contains(mode) { mode = 0 }
        if ![70, 80, 90, 100].contains(scale) { scale = 80 }
        if teams.isEmpty { teams = ["", ""] }
        teams = Array(teams.prefix(8)).enumerated().map { i, n in
            let t = String(n.prefix(24))
            return t.trimmingCharacters(in: .whitespaces) == defaultTeamName(i) ? "" : t
        }
    }
    /// المستوى الفعلي: «يختاره الفريق» لا ينطبق على اللوحة
    var effDiffMode: String { mode == 1 && diffMode == "team" ? "mixed" : diffMode }
    func teamName(_ i: Int) -> String {
        let n = i < teams.count ? teams[i].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return n.isEmpty ? defaultTeamName(i) : n
    }
    /// عدد خانات اللوحة = الأقسام × 4 × الفرق
    var boardSize: Int { cats.count * 4 * teams.count }
}

struct Team: Codable, Equatable {
    var name: String
    var score: Double = 0
    var ok: Int = 0
    var steals: Int = 0
    var bad: Int = 0
    var fifty: Bool
    var swap: Bool = true
}

enum Phase: String, Codable {
    case q, steal, judge, done, choose
}

struct TurnResult: Codable, Equatable {
    var type: String // ok | steal | none
    var team: Int?
    var pts: Double?
    var failed: Int?
}

struct GameState: Codable, Equatable {
    var v: Int = 3
    var mode: Int
    var settings: Settings
    var teams: [Team]
    var seen: [String] = []
    var qid: String? = nil
    var phase: Phase? = nil
    var paused: Bool = false
    // بالتتابع
    var turns: [DealTurn] = []
    var ti: Int = 0
    var rounds: Int = 0
    // اللوحة
    var board: [BoardRow] = []
    var turn: Int = 0
    var cell: [Int]? = nil // [صف، مجموعة، خانة]
    // السؤال الحالي
    var order: [Int] = [0, 1, 2, 3]
    var gone: [Int] = []
    var pick: Int? = nil // -1: انتهى الوقت
    var stealer: Int? = nil
    var stealPick: Int? = nil
    var res: TurnResult? = nil
    var shown: Int = 0
    var optsShown: Bool = false
    var timedOut: Bool = false
    var statDone: Bool = false
    var timer: TL.Timer? = nil

    var boardCells: [BoardCell] { board.flatMap { $0.groups.flatMap { $0.cells } } }
    var boardLeft: Int { boardCells.filter { !$0.used }.count }
}

/// بلاغ عن سؤال (يُحفظ بصيغة الويب نفسها)
struct Report: Codable, Equatable {
    var id: String?
    var cat: String?
    var q: String?
    var a: String?
    var note: String?
    var at: String?
    var key: String { id ?? ((cat ?? "") + "|" + (q ?? "")) }
}
