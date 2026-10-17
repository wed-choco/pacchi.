import AVFoundation

@MainActor
final class RetroSoundManager {
    static let shared = RetroSoundManager()
    enum Tone: Hashable { case number, navigation, select, back, notification, error, shutter, photoSave, albumSelect }
    private var player: AVAudioPlayer?
    private var cachedPlayers: [Tone: AVAudioPlayer] = [:]
    private var configuredSession = false
    func play(_ tone: Tone) {
        #if os(iOS)
        if !configuredSession {
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                configuredSession = true
            } catch { return }
        }
        #endif
        player?.stop()
        if let cached = cachedPlayers[tone] {
            player = cached
            cached.currentTime = 0
            cached.play()
            return
        }
        let notes: [(Double, Double)]
        switch tone {
        case .shutter: notes = [(1800, 0.018), (650, 0.035), (1200, 0.018)]
        case .photoSave: notes = [(880, 0.05), (1175, 0.06), (1568, 0.09)]
        case .albumSelect: notes = [(1200, 0.025)]
        case .number: notes = [(880, 0.045)]
        case .navigation: notes = [(1400, 0.018)]
        case .select: notes = [(1047, 0.055), (1397, 0.075)]
        case .back: notes = [(440, 0.06)]
        case .notification: notes = [(784, 0.16), (1047, 0.20), (0, 0.08), (784, 0.16), (1047, 0.25)]
        case .error: notes = [(330, 0.07), (0, 0.04), (330, 0.07)]
        }
        let rate = 22050.0
        var samples = [Int16]()
        for (frequency, duration) in notes {
            let count = Int(rate * duration)
            for i in 0..<count {
                let envelope = min(1, Double(i) / 100) * min(1, Double(count - i) / 180)
                samples.append(Int16(sin(2 * .pi * frequency * Double(i) / rate) * envelope * 2400))
            }
        }
        var data = Data()
        func string(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        string("RIFF"); integer(UInt32(36 + samples.count * 2)); string("WAVEfmt "); integer(UInt32(16))
        integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(rate)); integer(UInt32(rate * 2))
        integer(UInt16(2)); integer(UInt16(16)); string("data"); integer(UInt32(samples.count * 2))
        for sample in samples { integer(sample) }
        do {
            let created = try AVAudioPlayer(data: data)
            cachedPlayers[tone] = created
            player = created
            created.play()
        } catch { player = nil }
    }
}
