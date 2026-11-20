// فحوص ذاتية لمنطق اللعب (بلا XCTest): نقلٌ لاختبارات tools/tests/logic.test.js مع فحوص اللوحة الجديدة.
// تعمل في التطبيق بوسيط التشغيل -selfcheck (نسخة DEBUG)، وعلى Linux في .github/workflows/swift-logic.yml.
import Foundation

enum SelfCheck {
    final class Log {
        var lines: [String] = []
        var failed = 0
        var passed = 0
        func check(_ ok: Bool, _ name: String) {
            if ok { passed += 1 } else { failed += 1; lines.append("FAIL: " + name) }
        }
        func note(_ s: String) { lines.append(s) }
    }

    static func fakeBank(_ cats: [String], perLevel: Int = 10, keys: ((String, Int, Int) -> String?)? = nil) -> [String: [Question]] {
        var bank: [String: [Question]] = [:]
        for c in cats {
            var text = ""
            var n = 0
            for d in [1, 2, 3, 4] {
                for i in 0..<perLevel {
                    n += 1
                    let k = keys?(c, d, i).map { "|" + $0 } ?? ""
                    let sid = String(c.prefix(1)) + String(format: "%04d", n)
                    text += "\(d)|سؤال \(c) \(d) \(i)|جواب \(c) \(d) \(i)|خطأ أ \(i)|خطأ ب \(i)|خطأ ج \(i)|\(sid)\(k)\n"
                }
            }
            bank[c] = TL.parseBank(cat: c, text: text).items
        }
        return bank
    }
    static func ctx0(_ bank: [String: [Question]], _ used: Set<String> = []) -> PickContext {
        let ix = TL.buildIndex(bank)
        return PickContext(used: used, usedKeys: TL.usedKeySet(used, ix))
    }

    /// يشغّل كل الفحوص. dataDir: مجلد فيه cats.json وملفات الأسئلة (اختياري)
    static func run(dataDir: URL?) -> (ok: Bool, text: String) {
        let L = Log()
        // ---------- أدوات ----------
        L.check(TL.hash("abc") == "3772q3", "hash abc")
        L.check(TL.hash("من القائل:\nالخيل|المتنبي") == "xkrf6v", "hash arabic")
        L.check(TL.hash("") == "45h", "hash empty")
        L.check(TL.normAns("سُورَة الفاتحة") == "فاتحه", "normAns sura")
        L.check(TL.normAns("«أبو بكر»") == "ابو بكر", "normAns quotes")
        L.check(TL.normAns("سورة الفاتحة") == TL.normAns("الفاتحة"), "normAns equal")
        L.check(TL.normKey(" بغداد  المنصور ") == "بغداد-المنصور", "normKey")
        L.check(TL.toWestern("٢۳") == "23", "toWestern")

        // ---------- التحليل ----------
        do {
            let r = TL.parseBank(cat: "religion", text: "٢|سؤال|صح|خ1|خ2|خ3|r0001\n۳|سؤال2|صح2|خ1|خ2|خ3|r0002")
            L.check(r.items.count == 2 && r.items[0].d == 2 && r.items[1].d == 3, "eastern digits")
            L.check(r.problems.filter { $0.level == "warn" }.count == 2, "eastern digits warn")
        }
        do {
            let text = ["# تعليق", "## عنوان", "",
                        "5|سؤال|صح|خ1|خ2|خ3|r0001",
                        "1|سؤال|صح|خ1|خ2",
                        "1|سؤال|صح|خ1|خ2|خ3|r0003|مفتاح|زائد",
                        "1|سؤال|صح|صح|خ2|خ3|r0004",
                        "1|سؤال|صح|خ1||خ3|r0005",
                        "1|سؤال سليم|صح|خ1|خ2|خ3|r0006",
                        "1|مكرر|صح9|خ1|خ2|خ3|r0006"].joined(separator: "\n")
            let r = TL.parseBank(cat: "religion", text: text)
            let errs = r.problems.filter { $0.level == "error" }
            L.check(r.items.count == 1, "bad lines items")
            L.check(errs.map { $0.line } == [4, 5, 6, 7, 8, 10], "bad lines numbers \(errs.map { $0.line })")
        }
        do {
            let r = TL.parseBank(cat: "whoami", text: "2|ت1 ;; ت2 ;; ت3|المتنبي|البحتري|أبو تمام|المعري||متنبي,شعراء-العباسيين", clues: true)
            let q = r.items.first
            L.check(q?.clues ?? [] == ["ت1", "ت2", "ت3"], "clues parse")
            L.check(q?.keys ?? [] == ["متنبي", "شعراء-العباسيين"], "keys parse")
            L.check(q?.id.hasPrefix("whoami:") == true, "legacy id")
            L.check(r.problems.contains { $0.msg.contains("بلا معرّف") }, "no id warn")
            let r2 = TL.parseBank(cat: "football", text: "1|@sporting ;; @manutd ;; @realmadrid ;; @juventus ;; @alnassr|كريستيانو رونالدو|ليونيل ميسي|نيمار|كريم بنزيما|f0001")
            L.check(r2.items.first?.clues?.count == 5, "clue detection in any category")
            L.check(r2.items.first.map { TL.basePoints($0, shown: 1) } == 5, "career points")
        }

        // ---------- التوزيع بالجولات ----------
        do {
            let cats = ["religion", "history", "geography", "poetry"]
            let bank = fakeBank(cats, perLevel: 20)
            var ok = true
            for seed in 1...50 {
                let d = TL.dealRounds(bank: bank, cats: cats, nTeams: 2, rounds: 10, diffMode: "mixed", ctx: ctx0(bank), rng: seededRNG(UInt32(seed)))
                if d.rounds != 10 || d.turns.count != 20 { ok = false }
                for r in 0..<10 {
                    let rt = d.turns.filter { $0.round == r }
                    if Set(rt.map { $0.cat }).count != 1 || Set(rt.map { $0.d ?? 0 }).count != 1 || rt.map({ $0.team }) != [0, 1] { ok = false }
                }
                for team in [0, 1] where Set(d.turns.filter { $0.team == team }.map { $0.cat }).count != 4 { ok = false }
                let sum: (Int) -> Int = { t in d.turns.filter { $0.team == t }.reduce(0) { $0 + ($1.d ?? 0) } }
                if sum(0) != sum(1) { ok = false }
            }
            L.check(ok, "rounds: one cat+level per round, all cats, equal points")
        }
        do {
            let cats = ["religion", "history"]
            let bank = fakeBank(cats, perLevel: 3)
            let d = TL.dealRounds(bank: bank, cats: cats, nTeams: 4, rounds: 10, diffMode: "fixed", level: 4, ctx: ctx0(bank), rng: seededRNG(3))
            L.check(d.turns.allSatisfy { $0.d == 4 } && d.turns.count % 4 == 0 && d.turns.count == d.rounds * 4 && d.rounds < 10, "fixed level + whole rounds")
        }
        do {
            let cats = ["religion", "history", "poetry"]
            let bank = fakeBank(cats, perLevel: 5)
            let d = TL.dealRounds(bank: bank, cats: cats, nTeams: 3, rounds: 6, diffMode: "team", ctx: ctx0(bank), rng: seededRNG(7))
            var ok = d.turns.count == 18 && d.turns.allSatisfy { $0.d == nil && $0.id == nil }
            for r in 0..<6 where Set(d.turns.filter { $0.round == r }.map { $0.cat }).count != 1 { ok = false }
            for t in 0..<3 where Set(d.turns.filter { $0.team == t }.map { $0.cat }).count != 3 { ok = false }
            L.check(ok, "team-chooses mode")
        }
        do {
            var text = ""
            for i in 1...8 { text += "1|س\(i)|\(i <= 4 ? "المتنبي" : "جواب\(i)")|خ1|خ2|خ3|r\(String(format: "%04d", i))\n" }
            let bank = ["religion": TL.parseBank(cat: "religion", text: text).items]
            let d = TL.dealRounds(bank: bank, cats: ["religion"], nTeams: 1, rounds: 8, diffMode: "fixed", level: 1,
                                  ctx: ctx0(bank, ["religion:r0005"]), rng: seededRNG(1))
            let ids = d.turns.compactMap { $0.id }
            let ans = ids.compactMap { id in bank["religion"]!.first { $0.id == id }?.akey }
            L.check(!ids.contains("religion:r0005") && Set(ans).count == ans.count && d.turns.count == 4, "used + unique answers")
        }
        do {
            let text = ["1|بنى بغداد؟|المنصور|خ1|خ2|خ3|h0001|بغداد-المنصور",
                        "1|ما المدينة التي بناها المنصور؟|بغداد|خ1|خ2|خ3|h0002|بغداد-المنصور",
                        "1|سؤال آخر|جواب3|خ1|خ2|خ3|h0003",
                        "1|سؤال رابع|جواب4|خ1|خ2|خ3|h0004|البردة,بغداد-المنصور"].joined(separator: "\n")
            let bank = ["history": TL.parseBank(cat: "history", text: text).items]
            let ix = TL.buildIndex(bank)
            let used: Set<String> = ["history:h0001"]
            let uk = TL.usedKeySet(used, ix)
            L.check(bank["history"]!.filter { TL.isFresh($0, used, uk) }.map { $0.id } == ["history:h0003"], "keys used")
            var ok = true
            for s in 1...30 {
                let d = TL.dealRounds(bank: bank, cats: ["history"], nTeams: 1, rounds: 4, diffMode: "fixed", level: 1, ctx: ctx0(bank), rng: seededRNG(UInt32(s)))
                let keyed = d.turns.filter { ["history:h0001", "history:h0002", "history:h0004"].contains($0.id ?? "") }
                if keyed.count != 1 || d.turns.count != 2 { ok = false }
            }
            L.check(ok, "keys within a match")
        }

        // ---------- اللوحة ----------
        do {
            let cats = ["religion", "history", "geography", "poetry"]
            let bank = fakeBank(cats, perLevel: 10)
            var ok = true
            for n in [1, 2, 3, 4, 8] {
                let ix = TL.buildIndex(bank)
                let b = TL.buildBoard(bank: bank, cats: cats, nTeams: n, ctx: ctx0(bank), rng: seededRNG(UInt32(n * 7)))
                let cells = b.rows.flatMap { $0.groups.flatMap { $0.cells } }
                if b.wanted != cats.count * 4 * n || b.total != b.wanted || cells.count != b.total { ok = false; L.note("board n=\(n) total=\(b.total) wanted=\(b.wanted)") }
                if Set(cells.map { $0.id }).count != cells.count { ok = false }
                for r in b.rows { if r.groups.map({ $0.d }) != [1, 2, 3, 4] { ok = false }; for g in r.groups where g.cells.count != n || g.cells.contains(where: { $0.d != g.d }) { ok = false } }
                var f = Set<String>()
                for c in cells { if let q = ix.byId[c.id] { if TL.clashes(q, f) { ok = false }; TL.addFacts(q, &f) } }
            }
            L.check(ok, "board: cats×4×teams, one cell per team per level")
            let fx = TL.buildBoard(bank: bank, cats: ["religion", "history"], nTeams: 2, levels: [3], ctx: ctx0(bank), rng: seededRNG(9))
            L.check(fx.rows.allSatisfy { $0.groups.count == 1 && $0.groups[0].cells.count == 8 && $0.groups[0].cells.allSatisfy { $0.d == 3 } } && fx.total == 16, "board fixed level")
            let short = fakeBank(["saudi"], perLevel: 3)
            let sb = TL.buildBoard(bank: short, cats: ["saudi"], nTeams: 2, ctx: ctx0(short), rng: seededRNG(2))
            L.check(sb.total == 8 && sb.wanted == 8, "board short ok n=2")
            let sb4 = TL.buildBoard(bank: short, cats: ["saudi"], nTeams: 4, ctx: ctx0(short), rng: seededRNG(2))
            L.check(sb4.total == 0 && sb4.wanted == 16 && sb4.rows.isEmpty, "board short trims to whole turns")
        }

        // ---------- النقاط ----------
        L.check([1, 2, 3, 4, 7, 0.5, 1.5].map { TL.stealPoints($0) } == [0.5, 1, 1.5, 2, 3.5, 0.5, 0.5], "steal points")
        do {
            let q = Question(id: "w:1", legacy: "", cat: "w", d: 2, q: "", a: "", w: [], akey: "", keys: [], clues: ["a", "b", "c"])
            let q1 = Question(id: "x:1", legacy: "", cat: "x", d: 1, q: "", a: "", w: [], akey: "", keys: [], clues: nil)
            let q3 = Question(id: "x:3", legacy: "", cat: "x", d: 3, q: "", a: "", w: [], akey: "", keys: [], clues: nil)
            L.check(TL.basePoints(q, shown: 1) == 4 && TL.basePoints(q, shown: 3) == 2, "clue points")
            L.check(TL.turnPoints(q, shown: 1, optsShown: true, host: true) == 2 && TL.turnPoints(q, shown: 1, optsShown: false, host: true) == 4, "host points")
            L.check(TL.turnPoints(q1, shown: 0, optsShown: true, host: true) == 0.5 && TL.turnPoints(q3, shown: 0, optsShown: true, host: true) == 1.5
                    && TL.turnPoints(q3, shown: 0, optsShown: true, host: false) == 3, "host halves")
        }
        L.check([0.5, 2.5, 3, -1.5].map(TL.fmtPts) == ["½", "2½", "3", "−1½"], "fmtPts")
        L.check([10, 3, 12, 2, 1, 100].map(TL.leftMsg) == ["بقيت 10 أسئلة", "بقيت 3 أسئلة", "بقي 12 سؤالاً", "بقي سؤالان", "بقي سؤال واحد", "بقي 100 سؤال"], "leftMsg")
        L.check([1, 2, 4, 12, 0.5].map(TL.ptsWord) == ["نقطة", "نقطتان", "4 نقاط", "12 نقطة", "نصف نقطة"], "ptsWord")

        // ---------- المؤقت ----------
        do {
            var t = TL.tStart(TL.tNew(30), 1000)
            var ok = TL.tSeconds(t, 1000) == 30 && TL.tSeconds(t, 7500) == 24
            t = TL.tPause(t, 7500)
            ok = ok && TL.tSeconds(t, 99999) == 24
            if let data = try? JSONEncoder().encode(t), let back = try? JSONDecoder().decode(TL.Timer.self, from: data) { t = back } else { ok = false }
            t = TL.tStart(t, 200000)
            ok = ok && TL.tSeconds(t, 200000) == 24 && TL.tSeconds(t, 210000) == 14
            t = TL.tStart(t, 205000)
            ok = ok && TL.tSeconds(t, 210000) == 14 && TL.tExpired(t, 224000) && !TL.tExpired(t, 223000)
            L.check(ok, "timer pause/resume")
        }

        // ---------- السجل ----------
        do {
            let local = TL.History(used: ["a:1", "a:2"], reports: [["id": "a:1", "note": "x"]], stats: ["a:1": [1, 0, 0]])
            let inc = TL.History(used: ["a:2", "a:3"], reports: [["id": "a:1", "note": "x"], ["id": "a:9"]], stats: ["a:1": [1, 0, 0], "a:3": [0, 1, 1]])
            let m = TL.mergeHistory(local, inc)
            L.check(Set(m.merged.used) == ["a:1", "a:2", "a:3"] && m.addedUsed == 1 && m.addedReports == 1, "merge 1")
            let m2 = TL.mergeHistory(m.merged, inc)
            L.check(m2.addedUsed == 0 && m2.merged.stats["a:1"] == [1, 0, 0] && m2.merged.stats["a:3"] == [0, 1, 1], "merge idempotent")
            let bank = ["religion": TL.parseBank(cat: "religion", text: "1|س|ج|خ1|خ2|خ3|r0001").items]
            let ix = TL.buildIndex(bank)
            L.check(TL.migrateIds([bank["religion"]![0].legacy, "x:1"], ix) == ["religion:r0001", "x:1"], "migrate ids")
        }

        // ---------- البيانات الحقيقية ----------
        if let dir = dataDir {
            let reg = dir.appendingPathComponent("cats.json")
            if let data = try? Data(contentsOf: reg),
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cats = j["categories"] as? [[String: Any]] {
                var all = Set<String>()
                var n = 0
                for c in cats {
                    guard let key = c["key"] as? String, let file = c["file"] as? String else { continue }
                    let url = dir.appendingPathComponent((file as NSString).lastPathComponent)
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { L.check(false, "read \(file)"); continue }
                    let r = TL.parseBank(cat: key, text: text, clues: (c["clues"] as? Bool) ?? false)
                    L.check(r.items.count > 50, "items in \(key)")
                    for q in r.items { if all.contains(q.id) { L.check(false, "dup id \(q.id)") }; all.insert(q.id); n += 1 }
                    let e = r.problems.filter { $0.level == "error" }.count
                    L.note("data \(key): \(r.items.count) questions, \(e) rejected, \(r.problems.count - e) warnings")
                }
                L.check(n > 1000, "bank size \(n)")
                // صفقة حقيقية: لوحة 4 أقسام وفريقين
                var bank: [String: [Question]] = [:]
                for c in cats { if let key = c["key"] as? String, let file = c["file"] as? String,
                                   let text = try? String(contentsOf: dir.appendingPathComponent((file as NSString).lastPathComponent), encoding: .utf8) {
                    bank[key] = TL.parseBank(cat: key, text: text, clues: (c["clues"] as? Bool) ?? false).items } }
                let keys = Array(bank.keys.sorted().prefix(4))
                let b = TL.buildBoard(bank: bank, cats: keys, nTeams: 2, ctx: ctx0(bank))
                L.check(b.total == b.wanted, "real board \(b.total)/\(b.wanted)")
                let d = TL.dealRounds(bank: bank, cats: keys, nTeams: 3, rounds: 20, ctx: ctx0(bank))
                L.check(d.rounds == 20, "real rounds \(d.rounds)")
            } else {
                L.check(false, "cats.json not readable at \(reg.path)")
            }
        }
        L.note("passed \(L.passed), failed \(L.failed)")
        return (L.failed == 0, L.lines.joined(separator: "\n"))
    }

    /// تفريغ قانوني لكل سؤال، للمقارنة مع logic.js (انظر swift-logic.yml)
    static func dump(dataDir: URL) -> String {
        guard let data = try? Data(contentsOf: dataDir.appendingPathComponent("cats.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = j["categories"] as? [[String: Any]] else { return "no cats.json" }
        var out: [String] = []
        for c in cats {
            guard let key = c["key"] as? String, let file = c["file"] as? String,
                  let text = try? String(contentsOf: dataDir.appendingPathComponent((file as NSString).lastPathComponent), encoding: .utf8) else { continue }
            let r = TL.parseBank(cat: key, text: text, clues: (c["clues"] as? Bool) ?? false)
            for q in r.items { out.append([q.id, q.legacy, String(q.d), q.akey, q.keys.joined(separator: ","), String(q.clues?.count ?? 0)].joined(separator: "\t")) }
            for p in r.problems { out.append(["P", p.cat, String(p.line), p.level].joined(separator: "\t")) }
        }
        return out.joined(separator: "\n")
    }
}
