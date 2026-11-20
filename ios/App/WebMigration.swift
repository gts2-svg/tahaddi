// ترحيل لمرة واحدة من النسخة السابقة (غلاف الويب): كان سجل الأسئلة المستعملة والبلاغات والإحصاء والإعدادات
// محفوظاً في localStorage لصفحة app://localhost داخل التطبيق نفسه. نقرؤه مرة واحدة بصفحة مخفية صغيرة،
// وندمجه في السجل الأصلي حتى لا تتكرر الأسئلة بعد التحديث. ليس في التطبيق صفحة ويب غير هذه القراءة.
import Foundation
import WebKit

@MainActor
final class WebMigration: NSObject, WKScriptMessageHandler {
    static let doneKey = "webMigrationDone"
    private static var current: WebMigration?
    private var web: WKWebView?
    private let page = MigrationPage()
    private weak var model: AppModel?
    private var finished = false

    static func runIfNeeded(_ m: AppModel) {
        if UserDefaults.standard.bool(forKey: doneKey) { return }
        // تثبيت جديد بلا بيانات ويب: لا شيء يُرحَّل
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("WebKit")
        if !FileManager.default.fileExists(atPath: lib.path) { UserDefaults.standard.set(true, forKey: doneKey); return }
        let w = WebMigration()
        w.model = m
        current = w
        w.start()
    }

    private func start() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.setURLSchemeHandler(page, forURLScheme: "app")
        cfg.userContentController.add(self, name: "mig")
        let v = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: cfg)
        web = v
        if let u = URL(string: "app://localhost/migrate.html") { v.load(URLRequest(url: u)) }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            self?.finish(nil)
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        finish(message.body as? String)
    }

    private func finish(_ body: String?) {
        if finished { return }
        finished = true
        defer {
            web?.configuration.userContentController.removeScriptMessageHandler(forName: "mig")
            web = nil
            WebMigration.current = nil
        }
        guard let body, let d = body.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let m = model else { return }
        func parse(_ k: String) -> Any? {
            guard let s = o[k] as? String, let dd = s.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: dd, options: [.fragmentsAllowed])
        }
        let used = (parse("tahaddi_used") as? [Any])?.compactMap { $0 as? String } ?? []
        let reports = (parse("tahaddi_reports") as? [Any]) ?? []
        let stats = (parse("tahaddi_stats") as? [String: Any]) ?? [:]
        if !used.isEmpty || !reports.isEmpty || !stats.isEmpty {
            _ = try? m.importHistory(["app": "tahaddi", "used": used, "reports": reports, "stats": stats])
        }
        // الإعدادات تُنقل إن لم يكن للتطبيق الأصلي إعدادات محفوظة بعد
        if !m.hadSettingsFile,
           let s = o["tahaddi_settings"] as? String, let sd = s.data(using: .utf8),
           var st = try? JSONDecoder().decode(Settings.self, from: sd) {
            st.sanitize()
            m.settings = st
            m.normalizeCats()
        }
        UserDefaults.standard.set(true, forKey: WebMigration.doneKey)
        if !used.isEmpty { m.showToast("نُقل سجل الأسئلة المستعملة من النسخة السابقة") }
    }
}

/// يقدّم صفحة القراءة الصغيرة على العنوان app://localhost نفسه الذي كانت النسخة السابقة تستعمله
final class MigrationPage: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let html = """
        <!DOCTYPE html><html><body><script>
        var o = {};
        ['tahaddi_used','tahaddi_reports','tahaddi_stats','tahaddi_settings'].forEach(function (k) { try { o[k] = localStorage.getItem(k); } catch (e) {} });
        window.webkit.messageHandlers.mig.postMessage(JSON.stringify(o));
        </script></body></html>
        """
        let data = Data(html.utf8)
        let resp = URLResponse(url: task.request.url ?? URL(fileURLWithPath: "/"), mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

}
