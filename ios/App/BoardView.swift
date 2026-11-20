// لوحة الأسئلة على طريقة «سين جيم»: صف لكل قسم (صورته ولونه)، وفي الصف أربع مجموعات: سهل، متوسط، صعب، صعب جداً،
// وفي كل مجموعة خانة لكل فريق. يختار الفريق في دوره أي خانة فارغة، وبعد السؤال تأخذ الخانة لون الفريق الذي اختارها وتُغلق.
import SwiftUI

struct BoardView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide

    var body: some View {
        if let g = m.game {
            ScrollView {
                VStack(spacing: (wide ? 12 : 10) * k) {
                    TurnLine()
                    ForEach(g.board.indices, id: \.self) { r in
                        BoardRowView(r: r, row: g.board[r], teams: g.teams.count)
                    }
                    BoardLegend(teams: g.teams.count)
                }
                .padding(.horizontal, wide ? 0 : 14 * k)
                .padding(.bottom, 24 * k)
            }
        }
    }
}

struct BoardRowView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let r: Int
    let row: BoardRow
    let teams: Int

    var body: some View {
        let cat = m.catByKey[row.cat]
        let left = row.groups.reduce(0) { $0 + $1.cells.filter { !$0.used }.count }
        if wide {
            // الترويسة خلف مساحة محجوزة في جانب الصف، فيتحدد ارتفاع الصف بالخانات وحدها
            HStack(spacing: 0) {
                Color.clear.frame(width: 170 * k)
                groups.padding(10 * k)
            }
            .background(alignment: .leading) { header(cat, left: left).frame(width: 170 * k) }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20 * k, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8 * k, x: 0, y: 3 * k)
            .opacity(left == 0 ? 0.75 : 1)
        } else {
            VStack(spacing: 0) {
                header(cat, left: left).frame(height: 50 * k)
                groups.padding(8 * k)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20 * k, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 8 * k, x: 0, y: 3 * k)
            .opacity(left == 0 ? 0.75 : 1)
        }
    }

    func header(_ cat: Category?, left: Int) -> some View {
        let cc = C.cat(cat)
        return C.catGrad(cat)
            .overlay(CachedImage(url: cat?.photoURL(wide ? 500 : 800)))
            .overlay(LinearGradient(colors: wide ? [cc.1.opacity(0.0), cc.1.opacity(0.92)] : [cc.1.opacity(0.95), cc.1.opacity(0.35)],
                                    startPoint: wide ? .top : .leading, endPoint: wide ? .bottom : .trailing))
            .overlay(alignment: wide ? .bottomLeading : .leading) {
                VStack(alignment: .leading, spacing: 1 * k) {
                    Text(cat?.name ?? row.cat).tf(wide ? 19 : 17, .bold).foregroundColor(.white)
                        .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1).lineLimit(2).minimumScaleFactor(0.75)
                    Text(left == 0 ? "اكتمل" : TL.leftMsg(left)).tf(12, .medium).foregroundColor(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                }
                .padding(.horizontal, 14 * k).padding(.vertical, 10 * k)
            }
            .clipped()
    }

    var groups: some View {
        HStack(alignment: .top, spacing: (wide ? 10 : 6) * k) {
            ForEach(row.groups.indices, id: \.self) { gi in
                LevelGroupView(r: r, gi: gi, group: row.groups[gi], teams: teams, single: row.groups.count == 1)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct LevelGroupView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let r: Int
    let gi: Int
    let group: BoardGroup
    let teams: Int
    let single: Bool

    var body: some View {
        let d = group.d
        let cols = single ? min(group.cells.count, wide ? 8 : 4) : (wide ? min(teams, 4) : min(teams, 2))
        VStack(spacing: 6 * k) {
            HStack(spacing: 3 * k) {
                Text(DIFF_NAME[d] ?? "").tf(wide ? 13 : 12, .bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6 * k).padding(.vertical, 3 * k)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(C.levelDark(d)))
            if group.cells.isEmpty {
                Text("نفدت").tf(12).foregroundColor(C.soft).frame(maxWidth: .infinity, minHeight: 44 * k)
            } else {
                let c = max(1, cols)
                let rows = stride(from: 0, to: group.cells.count, by: c).map { Array($0..<min($0 + c, group.cells.count)) }
                VStack(spacing: 5 * k) {
                    ForEach(rows.indices, id: \.self) { ri in
                        HStack(spacing: 5 * k) {
                            ForEach(rows[ri], id: \.self) { ci in
                                BoardCellView(r: r, gi: gi, ci: ci, cell: group.cells[ci])
                            }
                            ForEach(0..<(c - rows[ri].count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }
            }
        }
        .padding(5 * k)
        .background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(C.level(d).opacity(0.07)))
    }
}

struct BoardCellView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.wide) var wide
    let r: Int
    let gi: Int
    let ci: Int
    let cell: BoardCell

    var body: some View {
        let d = cell.d
        let h = (wide ? 56 : 48) * k
        Button { m.openCell(r, gi, ci) } label: {
            ZStack {
                if cell.used, let by = cell.by {
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous).fill(C.teamGrad(by))
                    if let w = cell.win, w != by {
                        // سرقها فريق آخر: دائرة صغيرة بلون السارق وحرفه
                        Text(initialOf(m.game.map { w < $0.teams.count ? $0.teams[w].name : "" } ?? ""))
                            .tf(12, .bold).foregroundColor(.white)
                            .frame(width: 22 * k, height: 22 * k)
                            .background(Circle().fill(C.team(w)).overlay(Circle().stroke(Color.white, lineWidth: 2)))
                    } else {
                        Image(systemName: cell.win == nil ? "xmark" : "checkmark")
                            .font(.system(size: 17 * k, weight: .heavy)).foregroundColor(.white.opacity(cell.win == nil ? 0.7 : 1))
                    }
                } else if cell.used {
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous)
                        .strokeBorder(Color(hex: "#CBD5E1"), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                } else {
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous).fill(Color.white)
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous).fill(C.level(d).opacity(0.14))
                    RoundedRectangle(cornerRadius: 11 * k, style: .continuous).strokeBorder(C.level(d).opacity(0.75), lineWidth: 2 * k)
                    Text("؟").tf(wide ? 22 : 19, .bold).foregroundColor(C.levelDark(d))
                }
            }
            .frame(height: h)
            .frame(maxWidth: .infinity)
            .shadow(color: cell.used ? .clear : C.levelDeep(d).opacity(0.18), radius: 0, x: 0, y: 3 * k)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(cell.used)
        .accessibilityLabel(label)
    }

    var label: String {
        let cat = m.catByKey[m.game?.board[r].cat ?? ""]?.name ?? ""
        var s = "\(cat)، \(DIFF_NAME[cell.d] ?? "")"
        if cell.used, let g = m.game {
            if let by = cell.by, by < g.teams.count { s += "، اختارها \(g.teams[by].name)" }
            if let w = cell.win, w < g.teams.count { s += "، كسبها \(g.teams[w].name)" } else { s += "، لم يُصب أحد" }
        }
        return s
    }
}

struct BoardLegend: View {
    @Environment(\.uiScale) var k
    let teams: Int
    var body: some View {
        VStack(spacing: 8 * k) {
            FlowLayout(spacing: 6 * k, rowSpacing: 6 * k) {
                ForEach(1...4, id: \.self) { d in DiffChip(d: d, pts: ptsWordUI(Double(d)), size: 12) }
            }
            Text("الخانة المختارة تأخذ لون الفريق الذي اختارها: ✓ أصاب، ✗ لم يُصب أحد، ودائرة بلون فريق آخر إن سرقها.")
                .tf(12).foregroundColor(C.muted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4 * k)
    }
}
