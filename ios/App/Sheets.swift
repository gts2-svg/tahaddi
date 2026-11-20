// النوافذ: تعديل الفريق، والقائمة، والإبلاغ عن سؤال، وقائمة البلاغات، ونقل السجل بين الأجهزة، والتشخيص.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SheetFrame<Content: View>: View {
    @Environment(\.uiScale) var k
    @Environment(\.dismiss) var dismiss
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12 * k) {
                HStack {
                    Text(title).tf(20, .bold).foregroundColor(C.accentD)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14 * k, weight: .bold)).foregroundColor(C.muted)
                            .frame(width: 32 * k, height: 32 * k).background(Circle().fill(Color(hex: "#F3F4F6")))
                    }
                    .accessibilityLabel("إغلاق")
                }
                content()
            }
            .padding(18 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

func copyToPasteboard(_ s: String) { UIPasteboard.general.string = s }

// MARK: - تعديل الفريق
struct TeamEditSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.dismiss) var dismiss
    let i: Int
    @State private var name = ""
    @State private var delta: Double = 0

    var body: some View {
        let t: Team? = m.game.flatMap { i < $0.teams.count ? $0.teams[i] : nil }
        SheetFrame(title: "تعديل الفريق") {
            if let t {
                Text("الاسم").tf(14).foregroundColor(C.muted)
                TextField("اسم الفريق", text: $name)
                    .tf(18).padding(.horizontal, 12 * k).frame(minHeight: 48 * k)
                    .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color(hex: "#F9FAFB")))
                    .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color(hex: "#D1D5DB"), lineWidth: 1))
                    .submitLabel(.done)
                Text("تعديل النقاط يدوياً").tf(14).foregroundColor(C.muted).padding(.top, 6 * k)
                HStack(spacing: 6 * k) {
                    adj(-1); adj(-0.5)
                    Text(fmtPts(t.score + delta)).tf(30, .bold).foregroundColor(C.amberText).frame(minWidth: 70 * k)
                    adj(0.5); adj(1)
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 10 * k) {
                    Button("حفظ") { m.editTeam(i, name: name, delta: delta); dismiss() }.buttonStyle(PrimaryStyle(k: k))
                    Button("إلغاء") { dismiss() }.buttonStyle(GhostStyle(k: k))
                }
                .frame(maxWidth: .infinity).padding(.top, 8 * k)
            }
        }
        .onAppear { name = t?.name ?? "" }
        .presentationDetents([.medium, .large])
    }
    func adj(_ d: Double) -> some View {
        Button(d > 0 ? plusPts(d) : fmtPts(d)) { delta += d }.buttonStyle(GhostStyle(k: k)).frame(minWidth: 54 * k)
    }
}

// MARK: - القائمة
struct MenuSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.dismiss) var dismiss
    var body: some View {
        SheetFrame(title: "القائمة") {
            Text("للتعديل على اسم فريق أو نقاطه اضغط بطاقته في لوحة النقاط. الإصدار \(AppModel.version)").tf(13).foregroundColor(C.muted)
            VStack(spacing: 10 * k) {
                Button { dismiss() } label: { Text("متابعة").frame(maxWidth: .infinity) }.buttonStyle(PrimaryStyle(k: k))
                Button {
                    m.autoPaused = false
                    dismiss()
                    m.leaveToHome()
                } label: { Text("الخروج للرئيسية (تُحفظ المسابقة)").frame(maxWidth: .infinity) }.buttonStyle(GhostStyle(k: k))
                Button {
                    m.autoPaused = false
                    m.pauseGame()
                    dismiss()
                    m.confirmEnd()
                } label: { Text("إنهاء المسابقة…").frame(maxWidth: .infinity) }.buttonStyle(GhostStyle(k: k, danger: true))
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - الإبلاغ عن سؤال
struct ReportSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @Environment(\.dismiss) var dismiss
    @State private var note = ""
    var body: some View {
        SheetFrame(title: "الإبلاغ عن السؤال") {
            if let q = m.curQuestion {
                let prev = m.reports.first { $0.id == q.id }
                Text(q.display).tf(15).foregroundColor(C.text).fixedSize(horizontal: false, vertical: true)
                Text("الإجابة المعتمدة: \(q.a) · المعرّف: \(q.sid)").tf(13).foregroundColor(C.muted)
                if prev != nil { Text("أُبلغ عن هذا السؤال من قبل، وستُحدَّث ملاحظته.").tf(13).foregroundColor(C.amberText) }
                ZStack(alignment: .topLeading) {
                    if note.isEmpty { Text("ملاحظتك (اختياري): ما الخطأ؟").tf(15).foregroundColor(C.soft).padding(12 * k).allowsHitTesting(false) }
                    TextEditor(text: $note).tf(15).frame(minHeight: 120 * k).padding(6 * k).scrollContentBackground(.hidden)
                }
                .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color(hex: "#F9FAFB")))
                .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color(hex: "#D1D5DB"), lineWidth: 1))
                .onAppear { note = prev?.note ?? "" }
                HStack(spacing: 10 * k) {
                    Button("حفظ") { m.saveReport(for: q, note: note); dismiss() }.buttonStyle(PrimaryStyle(k: k))
                    Button("إلغاء") { dismiss() }.buttonStyle(GhostStyle(k: k))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - البلاغات
struct ReportsSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @State private var confirmClear = false
    var body: some View {
        SheetFrame(title: m.reports.isEmpty ? "الأسئلة المُبلَّغ عنها" : "الأسئلة المُبلَّغ عنها (\(m.reports.count))") {
            if m.reports.isEmpty {
                Text("لا يوجد بلاغات. أثناء اللعب اضغط «فيه خطأ» على أي سؤال تشك فيه.").tf(15).foregroundColor(C.text)
            } else {
                ForEach(m.reports.indices, id: \.self) { i in
                    let r = m.reports[i]
                    VStack(alignment: .leading, spacing: 3 * k) {
                        Text("[\(r.cat ?? "")]" + (r.id.map { id in " (" + (id.split(separator: ":").last.map(String.init) ?? id) + ")" } ?? ""))
                            .tf(13, .semibold).foregroundColor(C.accentD)
                        Text(r.q ?? "").tf(14).foregroundColor(C.text).fixedSize(horizontal: false, vertical: true)
                        Text("المعتمد: \(r.a ?? "")" + ((r.note ?? "").isEmpty ? "" : " — " + (r.note ?? ""))).tf(12).foregroundColor(C.muted)
                    }
                    .padding(.vertical, 8 * k)
                    Divider()
                }
                Text("انسخ القائمة وأرسلها لتصحيحها:").tf(13).foregroundColor(C.muted)
                HStack(spacing: 10 * k) {
                    Button { copyToPasteboard(m.reportsText); m.showToast("تم النسخ") } label: { Label("نسخ", systemImage: "doc.on.doc") }
                        .buttonStyle(PrimaryStyle(k: k))
                    ShareLink(item: m.reportsText) { Label("مشاركة", systemImage: "square.and.arrow.up") }
                        .buttonStyle(GhostStyle(k: k))
                    Button("مسح الكل") { confirmClear = true }.buttonStyle(GhostStyle(k: k, danger: true))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .alert("مسح كل البلاغات نهائياً؟", isPresented: $confirmClear) {
            Button("نعم، امسحها", role: .destructive) { m.reports = []; m.saveReports() }
            Button("إلغاء", role: .cancel) {}
        }
    }
}

// MARK: - نقل السجل
struct HistorySheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    enum Mode { case main, code, paste }
    @State private var mode: Mode = .main
    @State private var code = ""
    @State private var pasted = ""
    @State private var fileURL: URL? = nil
    @State private var importing = false
    @State private var message: (String, String)? = nil

    var body: some View {
        SheetFrame(title: mode == .code ? "رمز السجل" : mode == .paste ? "لصق رمز السجل" : "نقل السجل بين الأجهزة") {
            switch mode {
            case .main: mainView
            case .code: codeView
            case .paste: pasteView
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text, .data]) { r in
            switch r {
            case .success(let url):
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url), let t = String(data: d, encoding: .utf8) { doImport(t) }
                else { message = ("تعذّر الاستيراد", "تعذّر قراءة الملف.") }
            case .failure(let e):
                message = ("تعذّر الاستيراد", e.localizedDescription)
            }
        }
        .alert(message?.0 ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("حسناً", role: .cancel) {}
        } message: { Text(message?.1 ?? "") }
        .onAppear { makeFile() }
    }

    var mainView: some View {
        VStack(alignment: .leading, spacing: 12 * k) {
            Text("في السجل \(TL.qsWord(m.used.count)) مستعملاً، و\(m.reports.count) بلاغاً، وإحصاء الصواب والخطأ لـ\(TL.qsWord(m.stats.count)).")
                .tf(15).foregroundColor(C.text).fixedSize(horizontal: false, vertical: true)
            Text("انقلوه إلى الجوال الآخر أو الآيباد حتى لا تتكرر عليكم الأسئلة. الاستيراد يدمج السجلين ولا يحذف شيئاً. والرمز متوافق مع نسخة الموقع.")
                .tf(13).foregroundColor(C.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10 * k) {
                if let u = fileURL {
                    ShareLink(item: u) { Label("مشاركة ملف السجل", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryStyle(k: k))
                }
                Button { code = HistoryCode.encode(m.historyJSON()); mode = .code } label: { Label("نسخ رمز", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostStyle(k: k))
                Button { importing = true } label: { Label("استيراد ملف", systemImage: "folder").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostStyle(k: k))
                Button { mode = .paste } label: { Label("لصق رمز", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }
                    .buttonStyle(GhostStyle(k: k))
            }
        }
    }

    var codeView: some View {
        VStack(alignment: .leading, spacing: 12 * k) {
            Text("انسخ الرمز كله وأرسله إلى الجهاز الآخر، ثم الصقه هناك في «لصق رمز».").tf(13).foregroundColor(C.muted)
            ScrollView {
                Text(code).font(.system(size: 12, design: .monospaced)).foregroundColor(C.text)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 160 * k)
            .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color(hex: "#F9FAFB")))
            .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color(hex: "#D1D5DB"), lineWidth: 1))
            HStack(spacing: 10 * k) {
                Button { copyToPasteboard(code); m.showToast("تم النسخ") } label: { Label("نسخ", systemImage: "doc.on.doc") }.buttonStyle(PrimaryStyle(k: k))
                ShareLink(item: code) { Label("مشاركة", systemImage: "square.and.arrow.up") }.buttonStyle(GhostStyle(k: k))
                Button("رجوع") { mode = .main }.buttonStyle(GhostStyle(k: k))
            }
            .frame(maxWidth: .infinity)
        }
    }

    var pasteView: some View {
        VStack(alignment: .leading, spacing: 12 * k) {
            ZStack(alignment: .topLeading) {
                if pasted.isEmpty { Text("الصق الرمز أو محتوى الملف هنا").tf(14).foregroundColor(C.soft).padding(12 * k).allowsHitTesting(false) }
                TextEditor(text: $pasted).font(.system(size: 12, design: .monospaced)).frame(minHeight: 160 * k).padding(6 * k)
                    .scrollContentBackground(.hidden)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .background(RoundedRectangle(cornerRadius: 12 * k).fill(Color(hex: "#F9FAFB")))
            .overlay(RoundedRectangle(cornerRadius: 12 * k).stroke(Color(hex: "#D1D5DB"), lineWidth: 1))
            HStack(spacing: 10 * k) {
                Button("استيراد") { doImport(pasted) }.buttonStyle(PrimaryStyle(k: k))
                Button { pasted = UIPasteboard.general.string ?? "" } label: { Label("لصق", systemImage: "doc.on.clipboard") }.buttonStyle(GhostStyle(k: k))
                Button("رجوع") { mode = .main }.buttonStyle(GhostStyle(k: k))
            }
            .frame(maxWidth: .infinity)
        }
    }

    func doImport(_ text: String) {
        do {
            let obj = try HistoryCode.decode(text)
            let msg = try m.importHistory(obj)
            message = ("تم الاستيراد", msg)
            mode = .main
            pasted = ""
            makeFile()
        } catch {
            message = ("تعذّر الاستيراد", (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func makeFile() {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("tahaddi-history-\(AppModel.today()).json")
        if (try? m.historyJSON(pretty: true).write(to: u, options: .atomic)) != nil { fileURL = u }
    }
}

// MARK: - التشخيص
struct DiagSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.uiScale) var k
    @State private var check: String? = nil
    var body: some View {
        SheetFrame(title: "التشخيص") {
            Text("الإصدار \(AppModel.version) · الأقسام من: \(m.registrySource)").tf(14).foregroundColor(C.text)
            if !m.failed.isEmpty { Text("تعذّر تحميل: \(m.failed.joined(separator: "، "))").tf(14).foregroundColor(Color(hex: "#B91C1C")) }
            Grid(alignment: .center, horizontalSpacing: 8 * k, verticalSpacing: 6 * k) {
                GridRow {
                    Text("القسم").gridColumnAlignment(.leading)
                    Text("الأسئلة"); Text("مرفوض"); Text("تنبيهات")
                }
                .tf(13, .bold).foregroundColor(C.muted)
                Divider()
                ForEach(m.cats) { c in
                    let pr = m.problems.filter { $0.cat == c.key }
                    GridRow {
                        Text(c.name).gridColumnAlignment(.leading)
                        Text("\(m.bank[c.key]?.count ?? 0)")
                        Text("\(pr.filter { $0.level == "error" }.count)")
                        Text("\(pr.filter { $0.level == "warn" }.count)")
                    }
                    .tf(13).foregroundColor(C.text)
                }
            }
            Text("«مرفوض»: سطر لا يدخل اللعب لخطأ في صيغته. «تنبيه»: يدخل اللعب لكن فيه ما يستحق التصحيح.").tf(12).foregroundColor(C.muted)
            let list = m.problems.sorted { a, b in a.level == b.level ? false : a.level == "error" }.prefix(60)
            ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 2 * k) {
                    (Text(p.level == "error" ? "مرفوض " : "تنبيه ").foregroundColor(p.level == "error" ? Color(hex: "#B91C1C") : C.amberText)
                     + Text("\(m.catByKey[p.cat]?.name ?? p.cat): السطر \(p.line) — \(p.msg)").foregroundColor(C.text))
                        .tf(13)
                    Text(p.text).tf(11).foregroundColor(C.muted)
                }
                .padding(.vertical, 4 * k)
            }
            Text("التخزين: \(m.used.count) مستعملاً، و\(m.reports.count) بلاغاً، وإحصاء \(m.stats.count) سؤالاً · في ذاكرة التطبيق" + (m.saveFailed ? " · حدث فشل في الحفظ" : ""))
                .tf(13).foregroundColor(C.text)
            Text("أندية التلميحات: \(m.clubs.count)").tf(12).foregroundColor(C.muted)
            Button("فحص منطق اللعب") {
                let r = SelfCheck.run(dataDir: AppModel.dataDir)
                check = (r.ok ? "سليم ✓\n" : "فيه أخطاء ✗\n") + r.text
            }
            .buttonStyle(GhostStyle(k: k, small: true))
            if let check {
                Text(check).font(.system(size: 11, design: .monospaced)).foregroundColor(C.text)
                    .environment(\.layoutDirection, .leftToRight).frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}
