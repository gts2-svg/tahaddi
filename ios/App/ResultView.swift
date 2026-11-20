// شاشة النتيجة: الفائز بكأسه ونقاطه (أو المتعادلون معاً)، ثم بقية الفرق بترتيبها، وإحصاء المسابقة، وقصاصات ومطر وأشعة.
import SwiftUI

struct ResultView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) var rm

    var body: some View {
        if let res = m.result, !res.teams.isEmpty {
            let ranked = res.ranked
            let top = ranked[0].team.score
            let winners = ranked.filter { $0.team.score == top }
            let solo = res.teams.count == 1
            let tie = !solo && winners.count > 1
            ZStack {
                ScrollView {
                    VStack(spacing: 0) {
                        Text("انتهت المسابقة").tf(15, .semibold).foregroundColor(C.muted).padding(.top, 24 * k)
                        Text(solo ? "نتيجتك" : tie ? "تعادل!" : "الفائز!").tf(44, .bold).foregroundColor(C.amberText)
                            .shadow(color: Color(hex: "#FDE68A"), radius: 0, x: 0, y: 3 * k)
                            .padding(.top, 4 * k)
                        ZStack {
                            Rays().frame(width: 640 * k, height: 640 * k).offset(y: -10 * k)
                            VStack(spacing: 0) {
                                FlowLayout(spacing: 16 * k, rowSpacing: 16 * k) {
                                    ForEach(winners, id: \.i) { w in champ(w, small: tie) }
                                }
                                .padding(.top, 26 * k)
                                winPoints(top)
                                    .padding(.top, 18 * k)
                                Text(tie ? "بين " + joinNames(winners.map { "«\($0.team.name)»" }) : detail(winners[0].team))
                                    .tf(14).foregroundColor(C.muted).multilineTextAlignment(.center).padding(.top, 8 * k)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 10 * k) {
                            ForEach(rankRows(ranked, top: top, tie: tie, winners: winners)) { rr in
                                let place = rr.place
                                let row = rr.row
                                HStack(spacing: 12 * k) {
                                    Text("\(place)").tf(16, .bold).foregroundColor(.white)
                                        .frame(width: 34 * k, height: 34 * k)
                                        .background(RoundedRectangle(cornerRadius: 10 * k).fill(C.teamGrad(row.i)))
                                    VStack(alignment: .leading, spacing: 2 * k) {
                                        Text(row.team.name).tf(17, .bold).foregroundColor(C.text)
                                        Text(detail(row.team)).tf(13).foregroundColor(C.muted)
                                    }
                                    Spacer()
                                    Text(fmtPts(row.team.score)).tf(22, .bold).foregroundColor(C.text)
                                }
                                .padding(.horizontal, 14 * k).padding(.vertical, 12 * k)
                                .background(RoundedRectangle(cornerRadius: 18 * k).fill(Color.white).shadow(color: .black.opacity(0.08), radius: 6 * k, x: 0, y: 2 * k))
                            }
                        }
                        .padding(.top, 22 * k)
                        let sum: (KeyPath<Team, Int>) -> Int = { kp in res.teams.reduce(0) { $0 + $1[keyPath: kp] } }
                        HStack(spacing: 8 * k) {
                            stat("الأسئلة", sum(\.ok) + sum(\.bad))
                            stat("إجابات صحيحة", sum(\.ok))
                            stat("سرقات", sum(\.steals))
                        }
                        .padding(.top, 10 * k)
                        HStack(alignment: .top, spacing: 10 * k) {
                            Button("مباراة جديدة بنفس الفرق") { m.playAgain() }
                                .buttonStyle(PrimaryStyle(k: k, big: true))
                                .layoutPriority(1)
                            Button("الرئيسية") { m.goHome() }
                                .buttonStyle(GhostStyle(k: k))
                                .frame(minHeight: 64 * k)
                        }
                        .padding(.top, 22 * k)
                    }
                    .padding(.horizontal, 14 * k)
                    .padding(.bottom, 24 * k)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                ConfettiLayer(bursts: 1, rain: true)
            }
            .onAppear { if !rm { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { bounce = true } } }
        }
    }

    func champ(_ w: ResultSummary.Row, small: Bool) -> some View {
        let s: CGFloat = small ? 130 : 160
        return VStack(spacing: 4 * k) {
            Image(systemName: "trophy.fill").font(.system(size: (small ? 40 : 52) * k)).foregroundColor(.white)
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            Text(w.team.name).tf(small ? 18 : 22, .bold).foregroundColor(.white).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(12 * k)
        .frame(width: s * k, height: s * k)
        .background(RoundedRectangle(cornerRadius: (small ? 32 : 40) * k, style: .continuous).fill(C.teamGrad(w.i)))
        .overlay(RoundedRectangle(cornerRadius: (small ? 32 : 40) * k, style: .continuous).strokeBorder(Color.white, lineWidth: 6 * k))
        .background(RoundedRectangle(cornerRadius: ((small ? 32 : 40) + 4) * k, style: .continuous).fill(C.gold).padding(-4 * k))
        .shadow(color: .black.opacity(0.25), radius: 20 * k, x: 0, y: 14 * k)
        .offset(y: bounce ? -8 * k : 0)
    }

    @ViewBuilder
    func winPoints(_ top: Double) -> some View {
        let word = TL.ptsWord(top) == "نقطة" ? "نقطة واحدة" : ptsWordUI(top)
        let parts = word.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, parts[0].contains(where: { $0.isNumber }) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * k) {
                Text(parts[0]).tf(54, .bold).foregroundColor(C.text)
                Text(parts[1]).tf(20, .semibold).foregroundColor(C.muted)
            }
        } else {
            Text(word).tf(34, .bold).foregroundColor(C.text)
        }
    }

    func stat(_ l: String, _ v: Int) -> some View {
        VStack(spacing: 2 * k) {
            Text(l).tf(12).foregroundColor(C.muted)
            Text("\(v)").tf(21, .bold).foregroundColor(C.text)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10 * k)
        .background(RoundedRectangle(cornerRadius: 16 * k).fill(Color.white).shadow(color: .black.opacity(0.08), radius: 6 * k, x: 0, y: 2 * k))
    }

    func detail(_ t: Team) -> String { "صح \(t.ok) · سرقة \(t.steals) · خطأ \(t.bad)" }
    func joinNames(_ ns: [String]) -> String {
        ns.count <= 1 ? ns.joined() : ns.dropLast().joined(separator: "، ") + " و" + (ns.last ?? "")
    }
    /// الترتيب: الفائزون في الأعلى (يُكرَّرون في القائمة عند التعادل)، ثم البقية بمراتبهم
    struct RankRow: Identifiable {
        let place: Int
        let row: ResultSummary.Row
        var id: Int { row.i }
    }
    func rankRows(_ ranked: [ResultSummary.Row], top: Double, tie: Bool, winners: [ResultSummary.Row]) -> [RankRow] {
        var out: [RankRow] = []
        if tie { out += winners.map { RankRow(place: 1, row: $0) } }
        var place = 0
        var prev: Double? = nil
        for (idx, r) in ranked.enumerated() {
            if r.team.score != prev { place = idx }
            prev = r.team.score
            if r.team.score == top { continue }
            out.append(RankRow(place: place + 1, row: r))
        }
        return out
    }
}
