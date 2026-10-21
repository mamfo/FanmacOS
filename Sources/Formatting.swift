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

    static func coloredBar(download: Double, upload: Double) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let title = NSMutableAttributedString(
            string: "↓ \(rate(download))",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.systemBlue
            ]
        )
        title.append(NSAttributedString(
            string: "  ↑ \(rate(upload))",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.systemPurple
            ]
        ))
        return title
    }

    static func coloredInterface(_ network: NetworkRate) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        let value = NSMutableAttributedString(
            string: "↓ \(rate(network.download))",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.systemBlue,
                .paragraphStyle: paragraph
            ]
        )
        value.append(NSAttributedString(
            string: "  ↑ \(rate(network.upload))",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.systemPurple,
                .paragraphStyle: paragraph
            ]
        ))
        return value
    }
}
