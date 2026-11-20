// رمز نقل السجل بين الأجهزة، متوافق مع نسخة الويب:
// «TAHADDI1Z:» + base64(zlib(JSON)) ، أو «TAHADDI1:» + base64(JSON) ، أو JSON مباشرة.
// الويب يضغط بـ CompressionStream('deflate') أي صيغة zlib (رأس 78 9C + deflate + Adler-32).
import Foundation

enum HistoryCode {
    static func encode(_ json: Data) -> String {
        if let raw = try? (json as NSData).compressed(using: .zlib) as Data {
            var z = Data([0x78, 0x9C])
            z.append(raw)
            var a = adler32(json).bigEndian
            z.append(Data(bytes: &a, count: 4))
            return "TAHADDI1Z:" + z.base64EncodedString()
        }
        return "TAHADDI1:" + json.base64EncodedString()
    }

    static func decode(_ text: String) throws -> [String: Any] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{") { return try object(Data(t.utf8)) }
        let compact = t.components(separatedBy: .whitespacesAndNewlines).joined()
        let zipped: Bool
        let body: Substring
        if compact.hasPrefix("TAHADDI1Z:") { zipped = true; body = compact.dropFirst(10) }
        else if compact.hasPrefix("TAHADDI1:") { zipped = false; body = compact.dropFirst(9) }
        else { throw HistoryError.msg("ليس رمز سجل من «تحدّي»") }
        guard var bytes = Data(base64Encoded: String(body), options: .ignoreUnknownCharacters) else {
            throw HistoryError.msg("الرمز ناقص أو تالف: انسخوه كاملاً")
        }
        if zipped {
            guard bytes.count > 6 else { throw HistoryError.msg("الرمز ناقص أو تالف: انسخوه كاملاً") }
            var raw = bytes.dropFirst(2)
            raw = raw.dropLast(4)
            guard let out = try? (Data(raw) as NSData).decompressed(using: .zlib) as Data else {
                throw HistoryError.msg("تعذّر فك الرمز المضغوط")
            }
            bytes = out
        }
        return try object(bytes)
    }

    private static func object(_ d: Data) throws -> [String: Any] {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw HistoryError.msg("المحتوى ليس سجلاً صالحاً")
        }
        return o
    }

    static func adler32(_ d: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for x in d { a = (a + UInt32(x)) % 65521; b = (b + a) % 65521 }
        return (b << 16) | a
    }
}
