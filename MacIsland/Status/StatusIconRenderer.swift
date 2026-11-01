import AppKit

/// A single template image keeps the three live readings legible in either menu bar appearance.
/// All geometry is drawn locally; no remote assets or system queries are used while rendering.
enum StatusIconRenderer {
    static let size = NSSize(width: 22, height: 22)

    static func image(for snapshot: SystemStatusSnapshot) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
            context.setShouldAntialias(true)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            drawBattery(snapshot.battery, in: context)
            drawWiFi(snapshot.wifi, in: context)
            drawAudio(snapshot.audio, in: context)
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }

    static func normalizedLevel(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    static func volumeSteps(for audio: AudioStatus) -> Int? {
        if audio.isMuted { return 0 }
        guard let level = normalizedLevel(audio.level) else { return nil }
        return Int(ceil(level * 4))
    }

    private static func drawBattery(_ battery: BatteryStatus, in context: CGContext) {
        let radius: CGFloat = 9
        let center = CGPoint(x: 11, y: 11)
        let level = normalizedLevel(battery.level)
        context.saveGState()
        if battery.isPresent && level == nil {
            // Unknown is a broken track, rather than an empty battery reading.
            context.setLineDash(phase: 0, lengths: [1.6, 2.2])
            arc(center: center, radius: radius, start: 210, end: -30,
                width: 1.65, alpha: 0.48, in: context)
        } else {
            arc(center: center, radius: radius, start: 210, end: -30,
                width: 1.8, alpha: battery.isPresent ? 0.22 : 0.16, in: context)
            if battery.isPresent, let level, level > 0 {
                arc(center: center, radius: radius, start: 210, end: 210 - 240 * level,
                    width: 1.8, alpha: 1, in: context)
            }
        }
        context.restoreGState()

        if battery.isCharging {
            clear(CGRect(x: 9, y: 17.1, width: 4, height: 4.8), in: context)
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: 11.7, y: 21))
            bolt.addLine(to: CGPoint(x: 9.5, y: 18.8))
            bolt.addLine(to: CGPoint(x: 10.8, y: 18.8))
            bolt.addLine(to: CGPoint(x: 10.3, y: 17.4))
            bolt.addLine(to: CGPoint(x: 12.5, y: 19.7))
            bolt.addLine(to: CGPoint(x: 11.2, y: 19.7))
            bolt.closeSubpath()
            context.addPath(bolt)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
        } else if battery.isPluggedIn || !battery.isPresent {
            // The plug is also used on desktops; it never implies a fictional 100% battery.
            clear(CGRect(x: 8.9, y: 17.4, width: 4.2, height: 4.6), in: context)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(0.85)
            let plug = CGMutablePath()
            plug.move(to: CGPoint(x: 10.1, y: 21))
            plug.addLine(to: CGPoint(x: 10.1, y: 19.9))
            plug.move(to: CGPoint(x: 11.9, y: 21))
            plug.addLine(to: CGPoint(x: 11.9, y: 19.9))
            plug.move(to: CGPoint(x: 9.5, y: 19.9))
            plug.addLine(to: CGPoint(x: 12.5, y: 19.9))
            plug.addLine(to: CGPoint(x: 12.5, y: 19.3))
            plug.addCurve(to: CGPoint(x: 9.5, y: 19.3),
                          control1: CGPoint(x: 12.5, y: 17.5), control2: CGPoint(x: 9.5, y: 17.5))
            plug.addLine(to: CGPoint(x: 9.5, y: 19.9))
            plug.move(to: CGPoint(x: 11, y: 18))
            plug.addLine(to: CGPoint(x: 11, y: 17.5))
            context.addPath(plug)
            context.strokePath()
        }
    }

    private static func drawWiFi(_ wifi: WiFiStatus, in context: CGContext) {
        let center = CGPoint(x: 11, y: 8)
        let strength: Int?
        switch wifi {
        case .connected(let value): strength = value.map { min(3, max(0, $0)) }
        default: strength = nil
        }
        if case .unavailable = wifi {
            // A question mark is distinct from Wi-Fi being off or connected at zero bars.
            let question = CGMutablePath()
            question.move(to: CGPoint(x: 8.9, y: 12.8))
            question.addCurve(to: CGPoint(x: 11, y: 10.2),
                              control1: CGPoint(x: 8.6, y: 16.4), control2: CGPoint(x: 16.5, y: 13.4))
            question.addLine(to: CGPoint(x: 11, y: 9.7))
            context.addPath(question)
            context.setLineWidth(1.4)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            context.strokePath()
            dot(at: center, radius: 0.8, alpha: 0.6, in: context)
            return
        }
        let isConnected: Bool
        if case .connected = wifi { isConnected = true } else { isConnected = false }
        for index in 1...3 {
            let alpha: CGFloat
            if isConnected {
                alpha = strength.map { index <= $0 ? 1 : 0.22 } ?? 0.48
            } else {
                alpha = 0.22
            }
            arc(center: center, radius: CGFloat(index) * 2.1 + 0.2,
                start: 132, end: 48, width: 1.3, alpha: alpha, in: context)
        }
        dot(at: center, radius: 0.95, alpha: isConnected ? 1 : 0.22, in: context)
        if case .off = wifi {
            let slash = CGMutablePath()
            slash.move(to: CGPoint(x: 7, y: 15))
            slash.addLine(to: CGPoint(x: 15, y: 7.5))
            context.saveGState()
            context.setBlendMode(.clear)
            context.setLineWidth(3)
            context.addPath(slash)
            context.strokePath()
            context.restoreGState()
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1.3)
            context.addPath(slash)
            context.strokePath()
        }
    }

    private static func drawAudio(_ audio: AudioStatus, in context: CGContext) {
        let steps = volumeSteps(for: audio)
        let angles: [CGFloat] = [230, 257, 283, 310]
        for (index, angle) in angles.enumerated() {
            if audio.isMuted && (index == 1 || index == 2) { continue }
            let radians = angle * .pi / 180
            let point = CGPoint(x: 11 + 9 * cos(radians), y: 11 + 9 * sin(radians))
            if let steps {
                dot(at: point, radius: 1.08, alpha: index < steps ? 1 : 0.22, in: context)
            } else {
                context.setLineWidth(0.65)
                context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
                context.strokeEllipse(in: CGRect(x: point.x - 0.85, y: point.y - 0.85, width: 1.7, height: 1.7))
            }
        }
        if audio.isMuted {
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: 9.6, y: 2))
            context.addLine(to: CGPoint(x: 12.4, y: 4.8))
            context.move(to: CGPoint(x: 9.6, y: 4.8))
            context.addLine(to: CGPoint(x: 12.4, y: 2))
            context.strokePath()
        }
    }

    private static func arc(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat,
                            width: CGFloat, alpha: CGFloat, in context: CGContext) {
        context.setStrokeColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(width)
        context.addArc(center: center, radius: radius, startAngle: start * .pi / 180,
                       endAngle: end * .pi / 180, clockwise: true)
        context.strokePath()
    }

    private static func dot(at point: CGPoint, radius: CGFloat, alpha: CGFloat, in context: CGContext) {
        context.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                      width: radius * 2, height: radius * 2))
    }

    private static func clear(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(rect)
        context.restoreGState()
    }
}
