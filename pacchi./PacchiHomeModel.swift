import Foundation
import Observation
import CoreHaptics

@Observable @MainActor
final class PacchiHomeModel {
    var menuOpen = false
    var selectedKey = ""
    var destination: PacchiDestination?
    private var engine: CHHapticEngine?
    func press(_ key: String, sound: Bool) {
        selectedKey = key
        if sound { RetroSoundManager.shared.play(.number) }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.35),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch { /* Haptics are optional on unsupported or interrupted devices. */ }
    }
}

