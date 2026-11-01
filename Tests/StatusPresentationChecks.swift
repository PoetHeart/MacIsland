import AppKit

func checkStatusPresentation() {
    let normal = SystemStatusSnapshot(
        battery: BatteryStatus(level: 0.78, isCharging: true, isPluggedIn: true, isPresent: true),
        wifi: .connected(strength: 3), audio: AudioStatus(level: 0.5, isMuted: false))
    let english = StatusPresentation.lines(for: normal, language: "en")
    precondition(english == ["Battery: 78% · Charging", "Wi-Fi: Connected · Strong signal", "Volume: 50%"])
    let unavailable = SystemStatusSnapshot(
        battery: BatteryStatus(level: nil, isCharging: false, isPluggedIn: false, isPresent: true),
        wifi: .unavailable, audio: AudioStatus(level: nil, isMuted: false))
    let missing = StatusPresentation.lines(for: unavailable, language: "zh-Hans")
    precondition(missing.allSatisfy { $0.contains("暂不可用") && !$0.contains("0%") })
    let desktop = SystemStatusSnapshot(
        battery: BatteryStatus(level: nil, isCharging: false, isPluggedIn: true, isPresent: false),
        wifi: .off, audio: AudioStatus(level: nil, isMuted: true))
    precondition(StatusPresentation.lines(for: desktop, language: "en") == [
        "Battery: No built-in battery · Plugged in", "Wi-Fi: Off", "Volume: Muted"])
    let zero = SystemStatusSnapshot(
        battery: BatteryStatus(level: 0, isCharging: false, isPluggedIn: false, isPresent: true),
        wifi: .disconnected, audio: AudioStatus(level: 0, isMuted: false))
    precondition(StatusPresentation.lines(for: zero, language: "en") == ["Battery: 0%", "Wi-Fi: Disconnected", "Volume: 0%"])
    // A template adapts to both appearances; unavailable input must not look like a measured zero.
    precondition(StatusIconRenderer.volumeSteps(for: AudioStatus(level: nil, isMuted: false)) == nil)
    precondition(StatusIconRenderer.volumeSteps(for: AudioStatus(level: 0, isMuted: false)) == 0)
    precondition(StatusIconRenderer.volumeSteps(for: AudioStatus(level: 0.51, isMuted: false)) == 3)
    precondition(StatusIconRenderer.volumeSteps(for: AudioStatus(level: 1, isMuted: true)) == 0)
    precondition(StatusIconRenderer.normalizedLevel(.nan) == nil)
    let normalImage = StatusIconRenderer.image(for: normal)
    precondition(normalImage.isTemplate && normalImage.size == StatusIconRenderer.size)
    precondition(StatusIconRenderer.image(for: unavailable).tiffRepresentation != StatusIconRenderer.image(for: zero).tiffRepresentation)
    print("PASS: bilingual system status, unavailable versus zero, no-battery devices and adaptive icon")
}
