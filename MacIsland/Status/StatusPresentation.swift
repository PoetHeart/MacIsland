import Foundation

/// Shared by the menu, tooltip and VoiceOver; never describe unavailable data as zero.
enum StatusPresentation {
    static func lines(for snapshot: SystemStatusSnapshot, language: String) -> [String] {
        func text(_ source: String) -> String { AppText.text(source, language: language) }
        func percent(_ level: Double?) -> String {
            guard let level, level.isFinite else { return text("暂不可用") }
            return "\(Int((min(1, max(0, level)) * 100).rounded()))%"
        }
        let battery = snapshot.battery
        var power = battery.isPresent ? percent(battery.level) : text("无内置电池")
        if battery.isCharging { power += " · " + text("正在充电") }
        else if battery.isPluggedIn { power += " · " + text("已接电源") }
        let wifi: String
        switch snapshot.wifi {
        case .unavailable: wifi = text("暂不可用")
        case .off: wifi = text("已关闭")
        case .disconnected: wifi = text("未连接")
        case .connected(let strength):
            let signal: String
            switch strength {
            case 3?: signal = text("信号强")
            case 2?: signal = text("信号中等")
            case 0?, 1?: signal = text("信号弱")
            default: signal = text("信号未知")
            }
            wifi = text("已连接") + " · " + signal
        }
        let audio = snapshot.audio.isMuted ? text("已静音") : percent(snapshot.audio.level)
        return [text("电量") + ": " + power, "Wi-Fi: " + wifi, text("音量") + ": " + audio]
    }
}
