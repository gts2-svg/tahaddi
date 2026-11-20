// صور الأقسام وشعارات الأندية: تُجلب من الشبكة مرة ثم تُحفظ على القرص، فتظهر بلا إنترنت بعد ذلك.
// وإن لم تصل الصورة بقي ما تحتها (تدرّج لون القسم، أو شارة النادي بلونيه).
import SwiftUI
import UIKit
import CryptoKit

@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let mem = NSCache<NSString, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]
    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let d = base.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()

    private func file(_ url: URL) -> URL {
        let h = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(String(h.prefix(32)))
    }

    func cached(_ url: URL) -> UIImage? {
        if let m = mem.object(forKey: url.absoluteString as NSString) { return m }
        if let d = try? Data(contentsOf: file(url)), let img = UIImage(data: d) {
            mem.setObject(img, forKey: url.absoluteString as NSString)
            return img
        }
        return nil
    }

    func load(_ url: URL) async -> UIImage? {
        if let c = cached(url) { return c }
        if let t = inflight[url] { return await t.value }
        let path = file(url)
        let s = session
        let t = Task<UIImage?, Never> {
            guard let (d, resp) = try? await s.data(from: url),
                  (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let img = UIImage(data: d) else { return nil }
            try? d.write(to: path, options: .atomic)
            return img
        }
        inflight[url] = t
        let img = await t.value
        inflight[url] = nil
        if let img { mem.setObject(img, forKey: url.absoluteString as NSString) }
        return img
    }
}

/// صورة من الشبكة مع تخزين؛ تظهر بتلاشٍ فوق الخلفية الاحتياطية
struct CachedImage: View {
    let url: URL?
    var mode: ContentMode = .fill
    /// خلفية بيضاء مستديرة تظهر مع الصورة فقط (لشعارات الأندية)
    var plate: Bool = false
    @State private var image: UIImage?

    @MainActor
    init(url: URL?, mode: ContentMode = .fill, plate: Bool = false) {
        self.url = url
        self.mode = mode
        self.plate = plate
        _image = State(initialValue: url.flatMap { ImageStore.shared.cached($0) })
    }

    var body: some View {
        ZStack {
            if let image {
                if plate { Circle().fill(Color.white).padding(-6).transition(.opacity) }
                Image(uiImage: image).resizable().aspectRatio(contentMode: mode)
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let c = ImageStore.shared.cached(url) { image = c; return }
            let img = await ImageStore.shared.load(url)
            withAnimation(.easeOut(duration: 0.3)) { image = img }
        }
    }
}
