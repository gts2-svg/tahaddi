// محرك المسابقة: البدء، والأدوار، والإجابة والسرقة ووضع المضيف، والوسائل، والمؤقت والإيقاف، والتراجع، والنهاية.
// نقلٌ لما في app.js مع طريقة اللوحة الجديدة («سين جيم») وشاشة «دور الفريق».
import Foundation
import SwiftUI
import UIKit

extension AppModel {
    // MARK: - استعلامات
    func curTeamIdx(_ s: GameState) -> Int {
        if s.mode == 1 { return s.turn }
        return s.ti < s.turns.count ? s.turns[s.ti].team : 0
    }
    var curTeamIndex: Int { game.map(curTeamIdx) ?? 0 }
    var curQuestion: Question? { q(game?.qid) }
    var isHost: Bool { game?.settings.host ?? false }
    var optsHidden: Bool { isHost && !(game?.optsShown ?? false) }
    var canSteal: Bool { (game?.settings.steal ?? false) && (game?.teams.count ?? 0) > 1 }
    func points(_ q: Question, _ s: GameState) -> Double {
        TL.turnPoints(q, shown: s.shown, optsShown: s.optsShown, host: s.settings.host)
    }
    /// الفريق الذي يُلوَّن به الدور الآن (صاحب الدور أو السارق)
    var turnColorTeam: Int {
        guard let s = game else { return 0 }
        if s.phase == .steal, let k = s.stealer { return k }
        return curTeamIdx(s)
    }

    // MARK: - الحفظ
    func frozen(_ s: GameState) -> GameState {
        var x = s
        if let t = x.timer { x.timer = TL.tPause(t, TL.nowMs()) }
        return x
    }
    func persist() {
        guard let s = game else { return }
        writeJSON("game.json", frozen(s))
    }
    func mutate(_ f: (inout GameState) -> Void) {
        guard var s = game else { return }
        f(&s)
        game = s
    }

    // MARK: - البدء
    func requestStart() {
        guard ready else { return }
        normalizeCats()
        if game != nil {
            alert = AppAlert(title: "مسابقة جديدة؟", message: "عندك مسابقة لم تكتمل، وستُحذف إذا بدأت واحدة جديدة.", buttons: [
                AlertButton(title: "ابدأ جديدة", role: .destructive) { [weak self] in self?.startGame() },
                AlertButton(title: "إلغاء", role: .cancel),
            ])
        } else { startGame() }
    }

    func startGame() {
        guard ready else { return }
        normalizeCats()
        let st = settings
        let n = st.teams.count
        let teams = (0..<n).map { Team(name: st.teamName($0), fifty: st.fifty) }
        var base = GameState(mode: st.mode, settings: st, teams: teams)
        if st.mode == 1 {
            let levels = st.effDiffMode == "fixed" ? [st.level] : TL.LEVELS
            let b = TL.buildBoard(bank: bank, cats: st.cats, nTeams: n, levels: levels, ctx: ctx())
            if b.total == 0 { return exhaustedAlert() }
            base.board = b.rows
            base.turn = 0
            base.seen = base.boardCells.map { $0.id }
            let go: @MainActor () -> Void = { [weak self] in self?.beginGame(base) }
            if b.total < b.wanted {
                alert = AppAlert(title: "الأسئلة المتاحة لا تكفي اللوحة كاملة",
                                 message: "اللوحة المطلوبة \(TL.qsWord(b.wanted))، والمتاح في الأقسام المختارة يكفي \(TL.qsWord(b.total)) فقط، فبعض المستويات ناقصة. ويبقى لكل فريق عدد الأدوار نفسه.\nتبدؤون بهذا العدد، أو تختارون أقساماً أخرى؟",
                                 buttons: [AlertButton(title: "ابدؤوا بـ\(TL.qsWord(b.total))", action: go),
                                           AlertButton(title: "تغيير الإعدادات", role: .cancel)])
                return
            }
            go()
        } else {
            let d = TL.dealRounds(bank: bank, cats: st.cats, nTeams: n, rounds: st.perTeam, diffMode: st.effDiffMode, level: st.level, ctx: ctx())
            if d.rounds == 0 { return exhaustedAlert() }
            base.turns = d.turns
            base.ti = 0
            base.rounds = d.rounds
            base.seen = d.turns.compactMap { $0.id }
            let go: @MainActor () -> Void = { [weak self] in
                guard let self else { return }
                var s = base
                self.beginTurn(&s)
                self.beginGame(s)
            }
            if d.rounds < st.perTeam {
                let lvl = st.effDiffMode == "fixed" ? " من مستوى «\(DIFF_NAME[st.level] ?? "")»" : ""
                alert = AppAlert(title: "الأسئلة المتاحة لا تكفي",
                                 message: "طلبتم \(TL.qsWord(st.perTeam)) لكل فريق، والمتاح\(lvl) في الأقسام المختارة يكفي \(TL.qsWord(d.rounds)) لكل فريق فقط، حتى يتساوى عدد الأدوار.\nتبدؤون بهذا العدد، أو تختارون أقساماً أو مستوى آخر؟",
                                 buttons: [AlertButton(title: "ابدؤوا بـ\(TL.qsWord(d.rounds)) لكل فريق", action: go),
                                           AlertButton(title: "تغيير الإعدادات", role: .cancel)])
                return
            }
            go()
        }
    }

    func exhaustedAlert() {
        let lvl = levelFilter
        alert = AppAlert(title: "انتهت الأسئلة",
                         message: "لعبتم كل الأسئلة المتاحة\(lvl > 0 ? " في مستوى «\(DIFF_NAME[lvl] ?? "")»" : "") في الأقسام المختارة، أو لم يبقَ منها ما يكفي جولة واحدة لكل الفرق. ولن يتكرر أي سؤال إلا إذا صفّرتم السجل.\nاختاروا أقساماً أو مستوى آخر، أو صفّروا سجل هذه الأقسام.",
                         buttons: [AlertButton(title: "تصفير هذه الأقسام", role: .destructive) { [weak self] in self?.resetUsedForSelected() },
                                   AlertButton(title: "إغلاق", role: .cancel)])
    }

    func beginGame(_ s: GameState) {
        undoStack.removeAll(); undoCount = 0
        result = nil
        game = s
        persist()
        screen = .game
        UIApplication.shared.isIdleTimerDisabled = true
        if s.phase == .choose { prepareChooser() }
        showSplash()
    }

    /// الطريقة المتتابعة: بداية الدور
    func beginTurn(_ s: inout GameState) {
        guard s.ti < s.turns.count else { return }
        let t = s.turns[s.ti]
        if let id = t.id { openQuestion(&s, id) }
        else { s.qid = nil; s.phase = .choose; s.timer = nil }
    }

    func openQuestion(_ s: inout GameState, _ id: String) {
        let qq = q(id)
        s.qid = id; s.phase = .q; s.order = TL.shuffle([0, 1, 2, 3]); s.gone = []; s.pick = nil
        s.stealer = nil; s.stealPick = nil; s.res = nil
        // «مسيرة اللاعب» تبدأ والنادي مقفل (0)، وأسئلة التلميحات النصية بأول تلميح (1)
        s.shown = qq?.clues != nil ? (qq?.isCareer == true ? 0 : 1) : 0
        s.optsShown = false; s.timedOut = false; s.statDone = false; s.paused = false
        s.timer = s.settings.timer > 0 ? TL.tNew(s.settings.timer) : nil
        if !s.seen.contains(id) { s.seen.append(id) }
        markUsed(id) // السؤال الذي ظهر يُعدّ مستعملاً ولو انتهت المسابقة قبل إجابته
        undoStack.removeAll(); undoCount = 0
        lastSec = nil
    }

    // MARK: - شاشة «دور الفريق»
    func showSplash() {
        guard let s = game else { return }
        splashTask?.cancel()
        timerHalt()
        let idx = curTeamIdx(s)
        withAnimation(.easeOut(duration: 0.2)) { splash = idx }
        if shotMode && ProcessInfo.processInfo.arguments.contains("splash") { return } // تبقى للتصوير
        splashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if Task.isCancelled { return }
            self?.endSplash()
        }
    }
    func endSplash() {
        splashTask?.cancel(); splashTask = nil
        guard splash != nil else { return }
        withAnimation(.easeIn(duration: 0.25)) { splash = nil }
        timerRun()
    }
    func dismissSplash() { endSplash() }

    // MARK: - المؤقت
    func timerRun() {
        guard var s = game, let t = s.timer, s.phase == .q, !s.timedOut, !s.paused, splash == nil, sheet == nil, screen == .game,
              UIApplication.shared.applicationState != .background else { return }
        s.timer = TL.tStart(t, TL.nowMs())
        game = s
        if tickTask == nil {
            tickTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled { return }
                    self?.tick()
                }
            }
        }
    }
    func timerHalt() {
        tickTask?.cancel(); tickTask = nil
        if var s = game, let t = s.timer, t.since != nil { s.timer = TL.tPause(t, TL.nowMs()); game = s }
    }
    func tick() {
        guard let s = game, let t = s.timer else { timerHalt(); return }
        let now = TL.nowMs()
        let sec = TL.tSeconds(t, now)
        if sec != lastSec {
            lastSec = sec
            if sec <= 5 && sec > 0 { Sound.shared.play(.tick, on: s.settings.sound) }
            persist()
        }
        if TL.tExpired(t, now) { timerHalt(); onTimeout() }
    }
    func onTimeout() {
        guard let s = game else { return }
        Sound.shared.play(.bad, on: s.settings.sound)
        if optsHidden { mutate { $0.timedOut = true }; persist(); return }
        answer(-1)
    }
    func pauseGame() {
        guard let s = game, s.timer != nil, s.phase == .q, !s.timedOut else { return }
        timerHalt(); mutate { $0.paused = true }; persist()
    }
    func resumeGame() {
        guard let s = game, s.phase == .q else { return }
        mutate { $0.paused = false }; persist(); timerRun()
    }
    func togglePause() { if game?.paused == true { resumeGame() } else { pauseGame() } }
    /// إيقاف تلقائي أثناء النوافذ، ويُستأنف عند إغلاقها
    func autoPause() { if tickTask != nil { timerHalt(); autoPaused = true; persist() } }
    func autoResume() {
        guard autoPaused else { return }
        autoPaused = false
        if let s = game, s.phase == .q, !s.paused, screen == .game { timerRun() }
    }
    /// خروج التطبيق إلى الخلفية: يتوقف السؤال بوقته المتبقي
    func appBackgrounded() {
        guard game != nil else { return }
        if tickTask != nil { timerHalt(); mutate { $0.paused = true } }
        persist()
    }

    // MARK: - التراجع
    func pushUndo() {
        guard let s = game, let d = try? JSONEncoder().encode(frozen(s)) else { return }
        undoStack.append(d)
        if undoStack.count > 15 { undoStack.removeFirst() }
        undoCount = undoStack.count
    }
    func undo() {
        guard let d = undoStack.popLast(), var s = try? JSONDecoder().decode(GameState.self, from: d) else { return }
        undoCount = undoStack.count
        timerHalt()
        if s.phase == .q && s.timer != nil { s.paused = true } // يعود السؤال متوقفاً حتى يستأنفه المقدِّم
        game = s
        persist()
        showToast("تم التراجع عن آخر إجراء")
    }

    // MARK: - الإجابة والسرقة
    func answer(_ i: Int) {
        guard var s = game, let qq = q(s.qid) else { return }
        let snd = s.settings.sound
        if s.phase == .q {
            if s.paused || (i >= 0 && s.gone.contains(i)) { return }
            pushUndo(); timerHalt()
            s = game ?? s
            let ti = curTeamIdx(s)
            s.pick = i
            let ok = i >= 0 && i < s.order.count && s.order[i] == 0
            if ok {
                let p = points(qq, s)
                s.teams[ti].score += p; s.teams[ti].ok += 1
                s.res = TurnResult(type: "ok", team: ti, pts: p); s.phase = .done
                Sound.shared.play(.ok, on: snd)
                fx = FXEvent(ok: true, team: ti, pts: p, opt: i)
            } else {
                s.teams[ti].bad += 1
                if i >= 0 { Sound.shared.play(.bad, on: snd) }
                fx = FXEvent(ok: false, opt: i >= 0 ? i : nil)
                if s.settings.steal && s.teams.count > 1 { s.phase = .steal; s.stealer = nil }
                else { s.res = TurnResult(type: "none"); s.phase = .done }
            }
        } else if s.phase == .steal, let k = s.stealer {
            if i < 0 || i == s.pick || s.gone.contains(i) { return }
            pushUndo()
            s.stealPick = i
            if i < s.order.count && s.order[i] == 0 {
                let p = TL.stealPoints(points(qq, s))
                s.teams[k].score += p; s.teams[k].steals += 1
                s.res = TurnResult(type: "steal", team: k, pts: p)
                Sound.shared.play(.ok, on: snd)
                fx = FXEvent(ok: true, team: k, pts: p, opt: i)
                showToast("سرقة ناجحة: \(s.teams[k].name) \(plusPts(p))")
            } else {
                s.res = TurnResult(type: "none", failed: k)
                Sound.shared.play(.bad, on: snd)
                fx = FXEvent(ok: false, opt: i)
            }
            s.phase = .done
        } else { return }
        game = s
        persist()
    }
    func chooseStealer(_ k: Int?) {
        guard game?.phase == .steal else { return }
        mutate { $0.stealer = k }; persist()
    }
    func noSteal() {
        guard game?.phase == .steal else { return }
        pushUndo()
        mutate { $0.res = TurnResult(type: "none"); $0.phase = .done }
        persist()
    }
    // وضع المضيف
    func showOptions() {
        guard let s = game, s.phase == .q, s.settings.host, !s.optsShown else { return }
        mutate { $0.optsShown = true }; persist()
    }
    func hostReveal() {
        guard game?.phase == .q else { return }
        timerHalt(); mutate { $0.phase = .judge }; persist()
    }
    func judge(_ kind: String, _ k: Int? = nil) {
        guard var s = game, s.phase == .judge, let qq = q(s.qid) else { return }
        pushUndo()
        s = game ?? s
        let ti = curTeamIdx(s)
        let p = points(qq, s)
        let snd = s.settings.sound
        if kind == "ok" {
            s.teams[ti].score += p; s.teams[ti].ok += 1
            s.res = TurnResult(type: "ok", team: ti, pts: p)
            Sound.shared.play(.ok, on: snd); fx = FXEvent(ok: true, team: ti, pts: p)
        } else if kind == "steal", let k = k {
            s.teams[ti].bad += 1
            let sp = TL.stealPoints(p)
            s.teams[k].score += sp; s.teams[k].steals += 1
            s.res = TurnResult(type: "steal", team: k, pts: sp)
            Sound.shared.play(.ok, on: snd); fx = FXEvent(ok: true, team: k, pts: sp)
        } else {
            s.teams[ti].bad += 1
            s.res = TurnResult(type: "none")
            Sound.shared.play(.bad, on: snd); fx = FXEvent(ok: false)
        }
        s.phase = .done
        game = s
        persist()
    }

    func commitStats(_ s: inout GameState) {
        guard let id = s.qid, !s.statDone, s.phase == .done, let r = s.res else { return }
        var st = stats[id] ?? [0, 0, 0]
        while st.count < 3 { st.append(0) }
        if r.type == "ok" { st[0] += 1 } else { st[1] += 1 }
        if r.type == "steal" { st[2] += 1 }
        stats[id] = st; s.statDone = true; saveStats()
    }

    func next() {
        guard var s = game, s.phase == .done else { return }
        commitStats(&s)
        undoStack.removeAll(); undoCount = 0
        if s.mode == 1 {
            let picker = curTeamIdx(s)
            let winner: Int? = (s.res?.type ?? "none") != "none" ? s.res?.team : nil
            if let c = s.cell, c.count == 3, c[0] < s.board.count, c[1] < s.board[c[0]].groups.count, c[2] < s.board[c[0]].groups[c[1]].cells.count {
                s.board[c[0]].groups[c[1]].cells[c[2]].used = true
                s.board[c[0]].groups[c[1]].cells[c[2]].by = picker
                s.board[c[0]].groups[c[1]].cells[c[2]].win = winner
            }
            s.turn = (s.turn + 1) % max(1, s.teams.count)
            s.qid = nil; s.phase = nil; s.cell = nil; s.timer = nil
            game = s
            persist()
            if s.boardLeft == 0 { endGame(); return }
            showSplash()
            return
        }
        if s.ti + 1 >= s.turns.count { game = s; endGame(); return }
        s.ti += 1
        beginTurn(&s)
        game = s
        persist()
        if s.phase == .choose { prepareChooser() }
        showSplash()
    }
    var isLastQuestion: Bool {
        guard let s = game else { return false }
        return s.mode == 1 ? s.boardLeft <= 1 : s.ti + 1 >= s.turns.count
    }

    // MARK: - الوسائل
    func useFifty() {
        guard let s = game, s.phase == .q, !s.paused, !optsHidden, s.teams[curTeamIdx(s)].fifty else { return }
        let wrong = s.order.enumerated().filter { $0.element != 0 }.map { $0.offset }
        let ti = curTeamIdx(s)
        mutate { $0.gone = Array(TL.shuffle(wrong).prefix(2)); $0.teams[ti].fifty = false }
        persist()
    }
    func moreClue() {
        guard let s = game, s.phase == .q, !s.paused, let qq = q(s.qid), let c = qq.clues, s.shown < (qq.isCareer ? 1 : c.count) else { return }
        mutate { $0.shown += 1 }; persist()
        Sound.shared.play(.clue, on: s.settings.sound)
    }
    func swapQ() {
        guard var s = game, s.phase == .q, !s.paused, let qq = q(s.qid) else { return }
        let ti = curTeamIdx(s)
        if !s.teams[ti].swap { showToast("استعمل هذا الفريق تبديل السؤال من قبل"); return }
        let c = ctx(s.seen)
        guard let rep = TL.takeN(TL.freshPool(bank, qq.cat, qq.d, c), 1, c.facts).first else {
            showToast("لا يوجد سؤال بديل من القسم والمستوى نفسيهما"); return
        }
        timerHalt()
        s = game ?? s
        s.teams[ti].swap = false
        if s.mode == 1, let cl = s.cell, cl.count == 3 { s.board[cl[0]].groups[cl[1]].cells[cl[2]].id = rep.id }
        else if s.ti < s.turns.count { s.turns[s.ti].id = rep.id }
        openQuestion(&s, rep.id)
        game = s
        persist()
        timerRun()
        showToast("تم تبديل السؤال")
    }

    // MARK: - اختيار المستوى (يختاره الفريق)
    func levelCounts(_ cat: String) -> [Int] {
        let c = ctx(game?.seen ?? [])
        return TL.LEVELS.map { TL.countFresh(bank, cat, $0, c) }
    }
    /// إذا نفد قسم الدور أُخذ قسم آخر فيه أسئلة
    func prepareChooser() {
        guard var s = game, s.phase == .choose, s.ti < s.turns.count else { return }
        let cat = s.turns[s.ti].cat
        if !levelCounts(cat).contains(where: { $0 > 0 }),
           let alt = s.settings.cats.first(where: { levelCounts($0).contains(where: { $0 > 0 }) }) {
            s.turns[s.ti].cat = alt
            game = s
            persist()
        }
    }
    func pickLevel(_ d: Int) {
        guard var s = game, s.phase == .choose, s.ti < s.turns.count else { return }
        let c = ctx(s.seen)
        guard let qq = TL.takeN(TL.freshPool(bank, s.turns[s.ti].cat, d, c), 1, c.facts).first else {
            showToast("نفدت أسئلة هذا المستوى"); prepareChooser(); return
        }
        s.turns[s.ti].d = d; s.turns[s.ti].id = qq.id
        openQuestion(&s, qq.id)
        game = s
        persist()
        timerRun()
    }

    // MARK: - اللوحة
    func openCell(_ r: Int, _ gi: Int, _ k: Int) {
        guard var s = game, s.mode == 1, s.qid == nil, r < s.board.count, gi < s.board[r].groups.count, k < s.board[r].groups[gi].cells.count else { return }
        let cell = s.board[r].groups[gi].cells[k]
        if cell.used { return }
        if q(cell.id) == nil {
            s.board[r].groups[gi].cells[k].used = true
            game = s; persist()
            if s.boardLeft == 0 { endGame() }
            return
        }
        s.cell = [r, gi, k]
        openQuestion(&s, cell.id)
        game = s
        persist()
        timerRun()
    }

    /// سؤال حُذف من الملفات بعد بدء المسابقة
    func skipMissing() {
        guard var s = game else { return }
        if s.mode == 1 {
            if let c = s.cell, c.count == 3, c[0] < s.board.count, c[1] < s.board[c[0]].groups.count, c[2] < s.board[c[0]].groups[c[1]].cells.count {
                s.board[c[0]].groups[c[1]].cells[c[2]].used = true
            }
            s.qid = nil; s.cell = nil; s.phase = nil; s.timer = nil
            game = s; persist()
            if s.boardLeft == 0 { endGame() }
            return
        }
        guard s.ti < s.turns.count else { endGame(); return }
        let t = s.turns[s.ti]
        let c = ctx(s.seen)
        if let d = t.d, let rep = TL.takeN(TL.freshPool(bank, t.cat, d, c), 1, c.facts).first {
            s.turns[s.ti].id = rep.id
            openQuestion(&s, rep.id)
            game = s; persist(); return
        }
        if t.d == nil || s.settings.effDiffMode == "team" {
            s.turns[s.ti].id = nil; s.turns[s.ti].d = nil; s.phase = .choose; s.qid = nil
            game = s; persist(); prepareChooser(); return
        }
        s.turns.remove(at: s.ti)
        if s.ti >= s.turns.count { game = s; endGame(); return }
        beginTurn(&s)
        game = s; persist()
    }
    /// يتأكد أن سؤال الحالة موجود (بعد الاستئناف أو تحديث ملفات الأسئلة)
    func validateCurrent() {
        guard let s = game else { return }
        if s.qid != nil && q(s.qid) == nil { skipMissing() }
        if s.mode == 1 && s.qid == nil && s.boardLeft == 0 { endGame() }
    }

    // MARK: - الفرق أثناء اللعب
    func editTeam(_ i: Int, name: String, delta: Double) {
        guard let s = game, i < s.teams.count else { return }
        let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = nm.isEmpty ? s.teams[i].name : String(nm.prefix(24))
        if delta == 0 && newName == s.teams[i].name { return }
        pushUndo()
        mutate { $0.teams[i].name = newName; $0.teams[i].score += delta }
        if i < settings.teams.count { settings.teams[i] = newName == defaultTeamName(i) ? "" : newName }
        persist()
        if delta != 0 {
            fx = FXEvent(ok: delta > 0, team: i, pts: delta > 0 ? delta : nil, burst: false)
            showToast("\(newName): \(delta > 0 ? plusPts(delta) : fmtPts(delta))")
        }
    }

    // MARK: - التنقل
    func leaveToHome() {
        autoPaused = false
        timerHalt()
        splashTask?.cancel(); splash = nil
        if let s = game, s.phase == .q, s.timer != nil { mutate { $0.paused = true } }
        persist()
        screen = .home
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func resumeSaved() {
        guard ready else { showToast("انتظر حتى تُحمَّل الأسئلة"); return }
        guard var s = game else { return }
        undoStack.removeAll(); undoCount = 0
        if s.phase == .q && s.timer != nil { s.paused = true } // يعود متوقفاً بالوقت المتبقي نفسه
        game = s
        persist()
        screen = .game
        UIApplication.shared.isIdleTimerDisabled = true
        validateCurrent()
        if screen == .game {
            if game?.phase == .choose { prepareChooser() }
            showSplash()
        }
    }
    func discardSaved() {
        alert = AppAlert(title: "حذف المسابقة المحفوظة؟", message: "تُحذف نهائياً ولا يمكن متابعتها.", buttons: [
            AlertButton(title: "نعم، احذفها", role: .destructive) { [weak self] in self?.game = nil; self?.removeFile("game.json") },
            AlertButton(title: "إلغاء", role: .cancel),
        ])
    }
    func confirmEnd() {
        alert = AppAlert(title: "إنهاء المسابقة؟", message: "تنتهي المسابقة الآن وتظهر النتيجة، ولا يمكن متابعتها بعد ذلك.", buttons: [
            AlertButton(title: "نعم، أنهِها", role: .destructive) { [weak self] in self?.endGame() },
            AlertButton(title: "إلغاء", role: .cancel) { [weak self] in self?.autoResume() },
        ])
    }

    func endGame() {
        guard var s = game else { return }
        commitStats(&s)
        tickTask?.cancel(); tickTask = nil
        splashTask?.cancel(); splash = nil
        undoStack.removeAll(); undoCount = 0
        result = ResultSummary(teams: s.teams)
        game = nil
        removeFile("game.json")
        screen = .result
        UIApplication.shared.isIdleTimerDisabled = false
        Sound.shared.play(.win, on: settings.sound)
    }
    func playAgain() { result = nil; requestStart() }
    func goHome() { screen = .home; result = nil }
}

// MARK: - عرض النقاط
/// الأرقام ذات النصف (1½) تُعزل باتجاه اليسار-لليمين، وإلا ظهرت في السطر العربي «½1»
func iso(_ s: String) -> String { "\u{2066}" + s + "\u{2069}" }
func fmtPts(_ x: Double) -> String { iso(TL.fmtPts(x)) }
func plusPts(_ x: Double) -> String { iso("+" + TL.fmtPts(x)) }
func ptsWordUI(_ x: Double) -> String {
    ((x == x.rounded(.down) || x == 0.5) && x >= 0) ? TL.ptsWord(x) : "\(fmtPts(x)) نقطة"
}
