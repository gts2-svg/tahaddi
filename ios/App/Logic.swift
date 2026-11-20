// تحدّي — منطق اللعب الخالص (بلا واجهة): نقلٌ أمين لملف logic.js في نسخة الويب.
// التحليل، والفهرس والسجل، والتوزيع بالجولات، ولوحة الأسئلة، والنقاط، والمؤقت، ودمج السجل.
// لا يستورد إلا Foundation حتى يُفحص على Linux أيضاً (انظر .github/workflows/swift-logic.yml).
import Foundation

typealias RNG = () -> Double
let systemRNG: RNG = { Double.random(in: 0..<1) }

/// مولّد ثابت (LCG) للفحوص، مطابق لما في tools/tests/logic.test.js
func seededRNG(_ seed: UInt32) -> RNG {
    var s = seed
    return {
        s = s &* 1664525 &+ 1013904223
        return Double(s) / 4294967296.0
    }
}

// MARK: - السؤال والمشكلات

struct Question: Hashable {
    let id: String
    let legacy: String
    let cat: String
    let d: Int
    let q: String
    let a: String
    let w: [String]
    let akey: String
    let keys: [String]
    /// التلميحات (أسئلة «من أنا؟» وكل سؤال فيه « ;; »). nil للسؤال العادي
    let clues: [String]?

    var sid: String { id.split(separator: ":", maxSplits: 1).count == 2 ? String(id.split(separator: ":", maxSplits: 1)[1]) : id }
    /// نص السؤال للعرض في البلاغات
    var display: String {
        if let c = clues { return c.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: "\n") }
        return q
    }
}

struct Problem: Hashable {
    let cat: String
    let line: Int
    let level: String // "error" | "warn"
    let msg: String
    let text: String
}

struct DealTurn: Codable, Equatable {
    var round: Int
    var team: Int
    var cat: String
    var d: Int?
    var id: String?
}

struct BoardCell: Codable, Equatable {
    var id: String
    var d: Int
    var used: Bool = false
    /// الفريق الذي اختار الخانة (لونها بعد الإغلاق)
    var by: Int? = nil
    /// الفريق الذي كسب نقاطها (صاحبها أو السارق)، أو nil إن لم يُصب أحد
    var win: Int? = nil
}

struct BoardGroup: Codable, Equatable {
    var d: Int
    var cells: [BoardCell]
}

struct BoardRow: Codable, Equatable {
    var cat: String
    var groups: [BoardGroup]
}

struct PickContext {
    var used: Set<String>
    var usedKeys: Set<String>
    var facts: Set<String> = []
    var exclude: Set<String> = []
}

struct QIndex {
    var byId: [String: Question] = [:]
    var byLegacy: [String: String] = [:]
}

enum TL {
    static let LEVELS = [1, 2, 3, 4]

    // MARK: أدوات عامة
    static func shuffle<T>(_ input: [T], _ rng: RNG = systemRNG) -> [T] {
        var a = input
        if a.count < 2 { return a }
        var i = a.count - 1
        while i > 0 {
            let j = min(i, max(0, Int((rng() * Double(i + 1)).rounded(.down))))
            a.swapAt(i, j)
            i -= 1
        }
        return a
    }

    /// djb2 على وحدات UTF-16 بعدد صحيح 32 بت، كما في JavaScript
    static func hash(_ s: String) -> String {
        var h: Int32 = 5381
        for u in s.utf16 { h = (h &<< 5) &+ h &+ Int32(u) }
        return String(UInt32(bitPattern: h), radix: 36)
    }

    /// الأرقام العربية المشرقية (٠-٩) والفارسية (۰-۹) إلى أرقام غربية
    static func toWestern(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if (0x660...0x669).contains(u.value), let d = Unicode.Scalar(u.value - 0x660 + 0x30) { out.append(d) }
            else if (0x6F0...0x6F9).contains(u.value), let d = Unicode.Scalar(u.value - 0x6F0 + 0x30) { out.append(d) }
            else { out.append(u) }
        }
        return String(out)
    }

    static func isDiac(_ u: Unicode.Scalar) -> Bool {
        (0x64B...0x652).contains(u.value) || u.value == 0x670 || u.value == 0x640
    }
    static func stripDiac(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars where !isDiac(u) { out.append(u) }
        return String(out)
    }
    /// يجمع المسافات المتتالية في مسافة واحدة ويقص الأطراف
    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// تطبيع الإجابة لمنع اجتماع إجابتين متماثلتين في المسابقة الواحدة
    static func normAns(_ s: String) -> String {
        var t = stripDiac(s)
        t.removeAll { "«»\"()".contains($0) }
        var u = String.UnicodeScalarView()
        for c in t.unicodeScalars {
            switch c.value {
            case 0x623, 0x625, 0x622, 0x671: u.append("\u{0627}") // أإآٱ → ا
            case 0x649: u.append("\u{064A}")                      // ى → ي
            case 0x629: u.append("\u{0647}")                      // ة → ه
            default: u.append(c)
            }
        }
        t = collapse(String(u))
        if t.hasPrefix("سوره ") { t.removeFirst(5) }
        if t.hasPrefix("ال") { t.removeFirst(2) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normKey(_ s: String) -> String {
        stripDiac(s).trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: "-")
    }

    // MARK: تحليل ملف الأسئلة
    // الصيغة: الصعوبة|السؤال|الصحيح|خطأ|خطأ|خطأ|المعرّف|المفاتيح
    // السطر الذي فيه خطأ يُستبعد، والتنبيه لا يستبعده.
    // التلميحات: كل سؤال فيه «;;» في أي قسم (لا «من أنا؟» وحده). القسم الموسوم clues يُنبَّه فيه إن لم تكن ثلاثة.
    static func parseBank(cat: String, text: String, clues: Bool = false) -> (items: [Question], problems: [Problem]) {
        var items: [Question] = []
        var problems: [Problem] = []
        var ids = Set<String>()
        let lines = text.components(separatedBy: "\n")
        for (i, rawLine) in lines.enumerated() {
            var raw = rawLine
            if raw.hasSuffix("\r") { raw.removeLast() }
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = i + 1
            if line.isEmpty || line.hasPrefix("#") { continue }
            func bad(_ msg: String, _ level: String = "error") {
                problems.append(Problem(cat: cat, line: ln, level: level, msg: msg, text: String(line.prefix(140))))
            }
            let p = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if p.count < 6 { bad("حقول ناقصة (\(p.count) من 6 على الأقل)"); continue }
            if p.count > 8 { bad("علامة | زائدة داخل النص (\(p.count) حقلاً، والحد 8)"); continue }
            let dRaw = toWestern(p[0])
            guard dRaw.count == 1, let d = Int(dRaw), (1...4).contains(d) else { bad("الصعوبة «\(p[0])» ليست من 1 إلى 4"); continue }
            if dRaw != p[0] { bad("الصعوبة مكتوبة بأرقام عربية مشرقية (قُبلت)", "warn") }
            if p[1].isEmpty || p[2].isEmpty || p[3].isEmpty || p[4].isEmpty || p[5].isEmpty { bad("حقل فارغ في السؤال أو الخيارات"); continue }
            // المقارنة بالنص الحرفي: أسئلة الإملاء والضبط تختلف خياراتها بالتشكيل أو الهمزة وحدها
            let ex: (String) -> String = { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            let na = normAns(p[2])
            let xw = p[3...5].map(ex)
            if xw.contains(ex(p[2])) { bad("خيار خاطئ مطابق للإجابة الصحيحة"); continue }
            if Set(xw).count < 3 { bad("خياران خاطئان متطابقان", "warn") }
            let sid = p.count > 6 ? p[6] : ""
            if !sid.isEmpty && ids.contains(sid) { bad("معرّف مكرر «\(sid)»"); continue }
            if !sid.isEmpty { ids.insert(sid) } else { bad("سؤال بلا معرّف (شغّل tools/assign_ids.py)", "warn") }
            var keys: [String] = []
            if p.count > 7, !p[7].isEmpty {
                for part in p[7].components(separatedBy: CharacterSet(charactersIn: ",،")) {
                    let k = normKey(part)
                    if !k.isEmpty && !keys.contains(k) { keys.append(k) }
                }
            }
            let q = p[1].replacingOccurrences(of: "\\n", with: "\n")
            let legacy = cat + ":" + hash(q + "|" + p[2])
            var cl: [String]? = nil
            if clues || q.contains(";;") {
                let parts = q.components(separatedBy: ";;").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if clues && parts.count != 3 { bad("عدد التلميحات \(parts.count) والمطلوب 3", "warn") }
                if !clues && parts.count < 2 { bad("سؤال تلميحات فيه \(parts.count) تلميح فقط", "warn") }
                if !parts.isEmpty { cl = parts }
            }
            items.append(Question(id: sid.isEmpty ? legacy : cat + ":" + sid, legacy: legacy, cat: cat, d: d, q: q,
                                  a: p[2], w: Array(p[3...5]), akey: na, keys: keys, clues: cl))
        }
        return (items, problems)
    }

    // MARK: الفهرس والسجل
    static func buildIndex(_ bank: [String: [Question]]) -> QIndex {
        var ix = QIndex()
        for list in bank.values { for q in list { ix.byId[q.id] = q; ix.byLegacy[q.legacy] = q.id } }
        return ix
    }
    /// ترحيل المعرّفات القديمة (المأخوذة من النص) إلى المعرّفات الثابتة
    static func migrateIds<S: Sequence>(_ ids: S, _ ix: QIndex) -> Set<String> where S.Element == String {
        var out = Set<String>()
        for id in ids { out.insert(ix.byLegacy[id] ?? id) }
        return out
    }
    /// مفاتيح المعلومات المستعملة: سؤال مستعمل يجعل كل سؤال يشاركه مفتاحاً مستعملاً
    static func usedKeySet(_ used: Set<String>, _ ix: QIndex) -> Set<String> {
        var ks = Set<String>()
        for id in used { if let q = ix.byId[id] { ks.formUnion(q.keys) } }
        return ks
    }
    static func isFresh(_ q: Question, _ used: Set<String>, _ usedKeys: Set<String>) -> Bool {
        !used.contains(q.id) && !q.keys.contains(where: { usedKeys.contains($0) })
    }
    /// «بصمات» السؤال داخل المسابقة: إجابته المطبَّعة ومفاتيحه
    static func facts(_ q: Question) -> [String] { ["a:" + q.akey] + q.keys.map { "k:" + $0 } }
    static func clashes(_ q: Question, _ f: Set<String>) -> Bool { facts(q).contains(where: { f.contains($0) }) }
    static func addFacts(_ q: Question, _ f: inout Set<String>) { for x in facts(q) { f.insert(x) } }
    static func factsOf<S: Sequence>(_ ids: S, _ ix: QIndex) -> Set<String> where S.Element == String {
        var s = Set<String>()
        for id in ids { if let q = ix.byId[id] { addFacts(q, &s) } }
        return s
    }
    /// الأسئلة المتاحة من قسم ومستوى (d=0: كل المستويات)، غير مستعملة ولا تصطدم بما في المسابقة
    static func freshPool(_ bank: [String: [Question]], _ cat: String, _ d: Int, _ ctx: PickContext) -> [Question] {
        (bank[cat] ?? []).filter { q in
            (d == 0 || q.d == d) && isFresh(q, ctx.used, ctx.usedKeys) && !ctx.exclude.contains(q.id) && !clashes(q, ctx.facts)
        }
    }
    /// يأخذ n أسئلة لا يصطدم بعضها ببعض ولا بما في المسابقة؛ لا يعدّل factSet
    static func takeN(_ pool: [Question], _ n: Int, _ factSet: Set<String>, _ rng: RNG = systemRNG) -> [Question] {
        var tmp = factSet
        var out: [Question] = []
        for q in shuffle(pool, rng) {
            if out.count >= n { break }
            if clashes(q, tmp) { continue }
            addFacts(q, &tmp); out.append(q)
        }
        return out
    }
    /// عدد ما يمكن أخذه فعلاً (بعد إسقاط الإجابات المتماثلة فيما بينها)
    static func countFresh(_ bank: [String: [Question]], _ cat: String, _ d: Int, _ ctx: PickContext) -> Int {
        let pool = freshPool(bank, cat, d, ctx)
        var tmp = ctx.facts
        var n = 0
        for q in pool where !clashes(q, tmp) { addFacts(q, &tmp); n += 1 }
        return n
    }

    // MARK: التوزيع بالجولات (الطريقة المتتابعة)
    // كل جولة: قسم واحد ومستوى واحد، ولكل فريق سؤال منهما. فلا يلازم فريقٌ قسماً، ولا يظلم الحظُّ في الصعوبة.
    // diffMode: "fixed" (level) | "mixed" | "team" (المستوى يختاره الفريق في دوره، فيبقى السؤال فارغاً حتى يختار)
    static func dealRounds(bank: [String: [Question]], cats: [String], nTeams: Int, rounds: Int,
                           diffMode: String = "mixed", level: Int = 2, ctx: PickContext,
                           rng: RNG = systemRNG) -> (turns: [DealTurn], rounds: Int) {
        let order = shuffle(cats, rng)
        var factSet = ctx.facts
        var turns: [DealTurn] = []
        var r = 0
        var cycle: [Int] = []
        if order.isEmpty || nTeams < 1 { return ([], 0) }
        if diffMode == "team" {
            var cap: [String: Int] = [:]
            var c2 = ctx; c2.facts = factSet
            for c in order { cap[c] = countFresh(bank, c, 0, c2) }
            while r < rounds {
                var cat: String? = nil
                for k in 0..<order.count {
                    let c = order[(r + k) % order.count]
                    if (cap[c] ?? 0) >= nTeams { cat = c; break }
                }
                guard let chosen = cat else { break }
                cap[chosen, default: 0] -= nTeams
                for t in 0..<nTeams { turns.append(DealTurn(round: r, team: t, cat: chosen, d: nil, id: nil)) }
                r += 1
            }
            return (turns, r)
        }
        while r < rounds {
            var levels: [Int]
            if diffMode == "fixed" { levels = [level] }
            else {
                if cycle.isEmpty { cycle = shuffle(LEVELS, rng) }
                let want = cycle.removeFirst()
                levels = [want] + shuffle(LEVELS.filter { $0 != want }, rng)
            }
            var got: (c: String, d: Int, picks: [Question])? = nil
            outer: for k in 0..<order.count {
                let c = order[(r + k) % order.count]
                for d in levels {
                    var c2 = ctx; c2.facts = factSet
                    let picks = takeN(freshPool(bank, c, d, c2), nTeams, factSet, rng)
                    if picks.count == nTeams { got = (c, d, picks); break outer }
                }
            }
            guard let g = got else { break }
            for (t, q) in g.picks.enumerated() {
                addFacts(q, &factSet)
                turns.append(DealTurn(round: r, team: t, cat: g.c, d: g.d, id: q.id))
            }
            r += 1
        }
        return (turns, r)
    }

    // MARK: لوحة الأسئلة («سين جيم»)
    // صف لكل قسم، وفي الصف مجموعة لكل مستوى، وفي المجموعة خانة لكل فريق.
    // طول المسابقة = الأقسام × 4 × الفرق. في المستوى الثابت: مجموعة واحدة فيها 4 × الفرق خانة.
    // المجموعة التي لا تكفيها الأسئلة تُقصّ إلى مضاعف لعدد الفرق، فتبقى الأدوار متساوية.
    static func buildBoard(bank: [String: [Question]], cats: [String], nTeams: Int, levels: [Int] = LEVELS,
                           ctx: PickContext, rng: RNG = systemRNG) -> (rows: [BoardRow], total: Int, wanted: Int) {
        let n = max(1, nTeams)
        let perGroup = n * max(1, 4 / max(1, levels.count))
        let wanted = cats.count * perGroup * levels.count
        var factSet = ctx.facts
        struct Slot { let c: String; let d: Int; var pool: [Question]; var got: [Question] }
        var slots: [Slot] = []
        for c in cats { for d in levels { slots.append(Slot(c: c, d: d, pool: shuffle(freshPool(bank, c, d, ctx), rng), got: [])) } }
        // تعبئة بالتناوب حتى لا تستأثر مجموعة بالأسئلة المشتركة الإجابة
        var progress = true
        while progress {
            progress = false
            for i in slots.indices where slots[i].got.count < perGroup {
                while let q = slots[i].pool.popLast() {
                    if clashes(q, factSet) { continue }
                    addFacts(q, &factSet); slots[i].got.append(q); progress = true; break
                }
            }
        }
        var rows: [BoardRow] = []
        var total = 0
        for c in cats {
            var groups: [BoardGroup] = []
            for s in slots where s.c == c {
                let keep = (s.got.count / n) * n
                let cells = s.got.prefix(keep).map { BoardCell(id: $0.id, d: s.d) }
                total += cells.count
                groups.append(BoardGroup(d: s.d, cells: Array(cells)))
            }
            if groups.contains(where: { !$0.cells.isEmpty }) { rows.append(BoardRow(cat: c, groups: groups)) }
        }
        return (rows, total, wanted)
    }

    // MARK: النقاط
    // النقاط بأنصاف: ½ نصف نقطة. كل قسمة تُقرَّب إلى أدنى نصف، ولا تقل عن ½.
    static func halfFloor(_ x: Double) -> Double { (x * 2 + 1e-9).rounded(.down) / 2 }
    static func halve(_ p: Double) -> Double { max(0.5, halfFloor(p / 2)) }
    /// نقاط السؤال: الصعوبة، وأسئلة التلميحات تزيد نقطة عن كل تلميح لم يُكشف
    static func basePoints(_ q: Question, shown: Int = 1) -> Double {
        if let c = q.clues { return Double(q.d + max(0, c.count - shown)) }
        return Double(q.d)
    }
    /// في وضع المضيف: إظهار الخيارات ينصّف النقاط
    static func turnPoints(_ q: Question, shown: Int, optsShown: Bool, host: Bool) -> Double {
        let p = basePoints(q, shown: shown)
        return optsShown && host ? halve(p) : p
    }
    /// السرقة: نصف نقاط السؤال الحالية (فالسهل يُسرق بنصف نقطة)
    static func stealPoints(_ p: Double) -> Double { halve(p) }
    static func fmtPts(_ x: Double) -> String {
        let neg = x < 0
        let a = abs(x)
        let i = Int((a + 1e-9).rounded(.down))
        let h = a - Double(i) >= 0.25
        let s = h ? (i != 0 ? "\(i)½" : "½") : String(i)
        return (neg ? "−" : "") + s
    }
    struct Forms { let one, two, few, many, hund: String }
    /// تمييز العدد بالعربية: 1 مفرد، 2 مثنى، 3–10 جمع، 11–99 مفرد منصوب، والمئات مفرد مجرور
    static func countWord(_ n: Int, _ f: Forms) -> String {
        if n == 1 { return f.one }
        if n == 2 { return f.two }
        let m = n % 100
        if m >= 3 && m <= 10 { return "\(n) \(f.few)" }
        if m >= 11 { return "\(n) \(f.many)" }
        return "\(n) \(f.hund)"
    }
    static let PTS = Forms(one: "نقطة", two: "نقطتان", few: "نقاط", many: "نقطة", hund: "نقطة")
    static let QS = Forms(one: "سؤال واحد", two: "سؤالان", few: "أسئلة", many: "سؤالاً", hund: "سؤال")
    static let ROUNDS = Forms(one: "جولة واحدة", two: "جولتان", few: "جولات", many: "جولةً", hund: "جولة")
    static let CATS = Forms(one: "قسم واحد", two: "قسمان", few: "أقسام", many: "قسماً", hund: "قسم")
    static func ptsWord(_ x: Double) -> String {
        if x == 0.5 { return "نصف نقطة" }
        if x != x.rounded(.down) || x < 0 { return "\(fmtPts(x)) نقطة" }
        return countWord(Int(x), PTS)
    }
    static func qsWord(_ n: Int) -> String { countWord(n, QS) }
    static func roundsWord(_ n: Int) -> String { countWord(n, ROUNDS) }
    static func catsWord(_ n: Int) -> String { countWord(n, CATS) }
    /// «بقيت 5 أسئلة» / «بقي 12 سؤالاً» / «بقي سؤالان»
    static func leftMsg(_ n: Int) -> String {
        let m = n % 100
        return (m >= 3 && m <= 10 ? "بقيت " : "بقي ") + qsWord(n)
    }

    // MARK: المؤقت
    // الإيقاف والخروج والعودة لا تعيد الوقت أبداً: يُحفظ المتبقي ويُكمل منه. الأزمنة بالمللي ثانية.
    struct Timer: Codable, Equatable {
        var total: Int
        var leftMs: Double
        var since: Double?
    }
    static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
    static func tNew(_ total: Int) -> Timer { Timer(total: total, leftMs: Double(total) * 1000, since: nil) }
    static func tRemaining(_ t: Timer, _ now: Double) -> Double {
        guard let s = t.since else { return t.leftMs }
        return max(0, t.leftMs - (now - s))
    }
    static func tStart(_ t: Timer, _ now: Double) -> Timer {
        if t.since != nil { return t }
        var x = t; x.since = now; return x
    }
    static func tPause(_ t: Timer, _ now: Double) -> Timer { Timer(total: t.total, leftMs: tRemaining(t, now), since: nil) }
    static func tSeconds(_ t: Timer, _ now: Double) -> Int { Int((tRemaining(t, now) / 1000 - 1e-9).rounded(.up)) }
    static func tExpired(_ t: Timer, _ now: Double) -> Bool { tRemaining(t, now) <= 0 }

    // MARK: الاستيراد والتصدير
    // دمج سجلين: اتحاد المستعمل، وبلاغات بلا تكرار (بالمعرّف)، والإحصاء بالأكبر لكل سؤال
    struct History {
        var used: [String]
        var reports: [[String: Any]]
        var stats: [String: [Int]]
    }
    static func mergeHistory(_ local: History, _ inc: History) -> (merged: History, addedUsed: Int, addedReports: Int) {
        var usedSet = Set(local.used)
        var used = local.used
        var addedUsed = 0
        for id in inc.used where !usedSet.contains(id) { usedSet.insert(id); used.append(id); addedUsed += 1 }
        var reports = local.reports
        var addedReports = 0
        func repKey(_ r: [String: Any]) -> String {
            if let id = r["id"] as? String, !id.isEmpty { return id }
            return "\(r["cat"] ?? "")|\(r["q"] ?? "")"
        }
        var seen = Set(reports.map(repKey))
        for r in inc.reports where !seen.contains(repKey(r)) { seen.insert(repKey(r)); reports.append(r); addedReports += 1 }
        var stats = local.stats
        for (id, v) in inc.stats {
            let cur = stats[id] ?? [0, 0, 0]
            stats[id] = (0..<3).map { i in max(i < cur.count ? cur[i] : 0, i < v.count ? v[i] : 0) }
        }
        return (History(used: used, reports: reports, stats: stats), addedUsed, addedReports)
    }
}
