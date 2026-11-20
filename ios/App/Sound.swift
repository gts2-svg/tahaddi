// الأصوات: نغمات قصيرة تُولَّد في الذاكرة (كما في نسخة الويب بمولّد WebAudio)، بلا ملفات صوت.
// جلسة الصوت «ambient»: تحترم مفتاح الصامت ولا تقطع موسيقى الجهاز.
import AVFoundation
import UIKit

enum Tone { case ok, bad, tick, clue, win }

@MainActor
final class Sound {
    static let shared = Sound()
    private var players: [Tone: AVAudioPlayer] = [:]
    private var ready = false

    private func prepare() {
        if ready { return }
        ready = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let seqs: [Tone: ([(Double, Double)], Int, Double)] = [
            // (نغمات [تردد، مدة]، الشكل: 0 جيبي، 1 مربع، 2 منشاري، الشدة)
            .ok: ([(660, 0.09), (880, 0.16)], 0, 0.18),
            .bad: ([(220, 0.25)], 2, 0.16),
            .tick: ([(1000, 0.06)], 1, 0.10),
            .clue: ([(520, 0.08)], 0, 0.18),
            .win: ([(523, 0.12), (659, 0.12), (784, 0.12), (1046, 0.3)], 0, 0.18),
        ]
        for (k, v) in seqs {
            if let p = try? AVAudioPlayer(data: Sound.wav(v.0, shape: v.1, gain: v.2)) { p.prepareToPlay(); players[k] = p }
        }
    }

    func play(_ t: Tone, on: Bool) {
        if t == .ok || t == .win { haptic(.success) } else if t == .bad { haptic(.error) }
        guard on else { return }
        prepare()
        guard let p = players[t] else { return }
        p.currentTime = 0
        p.play()
    }

    private func haptic(_ k: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(k)
    }

    /// يبني ملف WAV (16 بت، أحادي) من سلسلة نغمات بخفوت أسّي كما في الويب
    static func wav(_ seq: [(Double, Double)], shape: Int, gain: Double) -> Data {
        let rate = 44100.0
        var samples: [Int16] = []
        for (f, d) in seq {
            let n = Int(rate * d)
            for i in 0..<n {
                let t = Double(i) / rate
                let ph = (t * f).truncatingRemainder(dividingBy: 1)
                let w: Double
                switch shape {
                case 1: w = ph < 0.5 ? 1 : -1
                case 2: w = 2 * ph - 1
                default: w = sin(2 * .pi * ph)
                }
                // من الشدة إلى 0.001 خلال المدة، مع بداية ناعمة قصيرة
                let env = gain * pow(0.001 / gain, t / d) * min(1, Double(i) / 60)
                samples.append(Int16(max(-1, min(1, w * env)) * 32767))
            }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        data.append("RIFF".data(using: .ascii)!); u32(36 + bytes)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(bytes)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }
}
