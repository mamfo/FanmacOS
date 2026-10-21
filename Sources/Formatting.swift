import AppKit

enum TemperatureStyle {
    static func text(_ celsius: Double, unit: TemperatureUnit, decimals: Int, includeUnit: Bool = true) -> String {
        let value = unit.convert(celsius)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
        return includeUnit ? "\(number) \(unit.symbol)" : number
    }

    static func compact(_ celsius: Double, unit: TemperatureUnit) -> String {
        let value = unit.convert(celsius).rounded()
        return "\(Int(value))\(unit.symbol)"
    }

    static func statusColor(_ celsius: Double) -> NSColor {
        switch celsius {
        case ..<70: return .labelColor
        case ..<85: return .systemOrange
        default: return .systemRed
        }
    }

    static func dotColor(_ celsius: Double) -> NSColor {
        switch celsius {
        case ..<45: return .systemTeal
        case ..<60: return .systemGreen
        case ..<75: return .systemYellow
        case ..<90: return .systemOrange
        default: return .systemRed
        }
    }
}


enum NetworkFormatting {
    static let downloadColor = NSColor(srgbRed: 0.00, green: 0.44, blue: 1.00, alpha: 1.0)
    static let uploadColor = NSColor(srgbRed: 0.72, green: 0.08, blue: 0.96, alpha: 1.0)

    private static let units = ["B/s", "KB/s", "MB/s", "GB/s"]

    private static let plainFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func rate(_ bytesPerSecond: Double) -> String {
        var value = (bytesPerSecond.isFinite ? bytesPerSecond : 0)
        value = max(0, value)

        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }

        let digits = (unit == 0 || value >= 100) ? 0 : 1
        let formatter = digits == 0 ? plainFormatter : decimalFormatter
        let number = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
        return "\(number) \(units[unit])"
    }

    static func interfaceSummary(_ network: NetworkRate) -> String {
        "↓ \(rate(network.download))  ↑ \(rate(network.upload))"
    }

    static func coloredInterface(_ network: NetworkRate) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        let value = NSMutableAttributedString(
            string: "↓ \(rate(network.download))",
            attributes: [
                .font: font,
                .foregroundColor: downloadColor,
                .paragraphStyle: paragraph
            ]
        )
        value.append(NSAttributedString(
            string: "  ↑ \(rate(network.upload))",
            attributes: [
                .font: font,
                .foregroundColor: uploadColor,
                .paragraphStyle: paragraph
            ]
        ))
        return value
    }
}

enum NetworkStatusImage {
    static func make(download: Double, upload: Double) -> NSImage? {
        let down = "↓ \(NetworkFormatting.rate(download))"
        let up = "↑ \(NetworkFormatting.rate(upload))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let downSize = (down as NSString).size(withAttributes: textAttributes)
        let upSize = (up as NSString).size(withAttributes: textAttributes)
        let height: CGFloat = 18
        let padding: CGFloat = 6
        let gap: CGFloat = 4
        let width = ceil(downSize.width + padding * 2 + gap + upSize.width + padding * 2) + 4
        let scale: CGFloat = 2

        let pixelWidth = Int(ceil(width * scale))
        let pixelHeight = Int(ceil(height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = context

        let downRect = NSRect(x: 0, y: 0, width: padding * 2 + downSize.width, height: height)
        let upRect = NSRect(
            x: downRect.width + gap,
            y: 0,
            width: padding * 2 + upSize.width,
            height: height
        )

        NetworkFormatting.downloadColor.setFill()
        NSBezierPath(roundedRect: downRect, xRadius: height / 2, yRadius: height / 2).fill()

        NetworkFormatting.uploadColor.setFill()
        NSBezierPath(roundedRect: upRect, xRadius: height / 2, yRadius: height / 2).fill()

        (down as NSString).draw(
            at: NSPoint(x: downRect.minX + padding, y: downRect.midY - downSize.height / 2),
            withAttributes: textAttributes
        )
        (up as NSString).draw(
            at: NSPoint(x: upRect.minX + padding, y: upRect.midY - upSize.height / 2),
            withAttributes: textAttributes
        )

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}
