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

    static func capsuleColor(_ celsius: Double) -> NSColor {
        switch celsius {
        case ..<60:
            return NSColor(srgbRed: 0.05, green: 0.48, blue: 0.24, alpha: 1)
        case ..<80:
            return NSColor(srgbRed: 0.70, green: 0.33, blue: 0.02, alpha: 1)
        default:
            return NSColor(srgbRed: 0.73, green: 0.11, blue: 0.11, alpha: 1)
        }
    }

    static let capsuleFallback = NSColor(srgbRed: 0.32, green: 0.32, blue: 0.36, alpha: 1)

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


enum RateFormatting {
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
}

enum NetworkFormatting {
    static let downloadColor = NSColor(srgbRed: 0.00, green: 0.44, blue: 1.00, alpha: 1.0)
    static let uploadColor = NSColor(srgbRed: 0.72, green: 0.08, blue: 0.96, alpha: 1.0)

    static func rate(_ bytesPerSecond: Double) -> String {
        RateFormatting.rate(bytesPerSecond)
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

enum DiskFormatting {
    static let readColor = NSColor(srgbRed: 0.04, green: 0.44, blue: 0.52, alpha: 1.0)
    static let writeColor = NSColor(srgbRed: 0.70, green: 0.33, blue: 0.02, alpha: 1.0)

    static func summary(read: Double, write: Double) -> String {
        "R \(RateFormatting.rate(read))  W \(RateFormatting.rate(write))"
    }

    static func coloredSummary(read: Double, write: Double) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        let value = NSMutableAttributedString(
            string: "R \(RateFormatting.rate(read))",
            attributes: [
                .font: font,
                .foregroundColor: readColor,
                .paragraphStyle: paragraph
            ]
        )
        value.append(NSAttributedString(
            string: "  W \(RateFormatting.rate(write))",
            attributes: [
                .font: font,
                .foregroundColor: writeColor,
                .paragraphStyle: paragraph
            ]
        ))
        return value
    }
}

extension DiskKind {
    var dotColor: NSColor {
        switch self {
        case .internalDisk: return .secondaryLabelColor
        case .sdCard: return .systemTeal
        case .usb: return .systemOrange
        case .external: return .systemBlue
        }
    }
}

struct CapsuleSegment {
    let text: String
    let color: NSColor
    let symbolName: String?
}

enum StatusCapsuleImage {
    static func make(_ segments: [CapsuleSegment], leadingPadding: CGFloat = 0, trailingPadding: CGFloat = 4) -> NSImage? {
        guard !segments.isEmpty else { return nil }

        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let height: CGFloat = 18
        let padding: CGFloat = 6
        let gap: CGFloat = 4

        struct Prepared {
            let text: String
            let color: NSColor
            let symbol: NSImage?
            let textSize: NSSize
            let contentWidth: CGFloat
        }

        let prepared: [Prepared] = segments.map { segment in
            let textSize = (segment.text as NSString).size(withAttributes: textAttributes)
            let symbol = segment.symbolName.flatMap { tintedSymbol(named: $0) }
            let symbolWidth = symbol.map { $0.size.width + 3 } ?? 0
            return Prepared(
                text: segment.text,
                color: segment.color,
                symbol: symbol,
                textSize: textSize,
                contentWidth: symbolWidth + textSize.width
            )
        }

        let capsulesWidth = prepared.reduce(0) { $0 + $1.contentWidth + padding * 2 }
        let width = ceil(leadingPadding + capsulesWidth + gap * CGFloat(max(0, prepared.count - 1)) + trailingPadding)
        let scale: CGFloat = 2

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(width * scale)),
            pixelsHigh: Int(ceil(height * scale)),
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

        var x: CGFloat = leadingPadding
        for item in prepared {
            let rect = NSRect(x: x, y: 0, width: padding * 2 + item.contentWidth, height: height)
            item.color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()

            var contentX = rect.minX + padding
            if let symbol = item.symbol {
                symbol.draw(in: NSRect(
                    x: contentX,
                    y: (height - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                ))
                contentX += symbol.size.width + 3
            }

            (item.text as NSString).draw(
                at: NSPoint(x: contentX, y: rect.midY - item.textSize.height / 2),
                withAttributes: textAttributes
            )

            x = rect.maxX + gap
        }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private static func tintedSymbol(named name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else {
            return nil
        }

        let size = symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
