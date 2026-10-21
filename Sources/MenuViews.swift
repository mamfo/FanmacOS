import AppKit

final class DotView: NSView {
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

final class AccentBarView: NSView {
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2).fill()
    }
}

final class MenuHeaderView: NSView {
    private let accent = AccentBarView()
    private let valueLabel = NSTextField(labelWithString: "--")
    private let captionLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 74))

        accent.frame = NSRect(x: 16, y: 16, width: 3, height: 44)
        addSubview(accent)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 25, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.frame = NSRect(x: 30, y: 9, width: width - 46, height: 32)
        addSubview(valueLabel)

        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.frame = NSRect(x: 31, y: 40, width: width - 47, height: 15)
        addSubview(captionLabel)

        detailLabel.font = .systemFont(ofSize: 10.5)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.frame = NSRect(x: 31, y: 54, width: width - 47, height: 14)
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(value: String, color: NSColor, caption: String, detail: String) {
        valueLabel.stringValue = value
        valueLabel.textColor = color
        accent.color = color
        captionLabel.stringValue = caption
        detailLabel.stringValue = detail
    }
}

final class SensorRowView: NSView {
    private let dot = DotView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    override var isFlipped: Bool { true }

    init(width: CGFloat, height: CGFloat = 22, indentation: CGFloat = 0, valueWidth: CGFloat = 84) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))

        dot.frame = NSRect(x: 14 + indentation, y: (height - 8) / 2, width: 8, height: 8)
        addSubview(dot)

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(
            x: 30 + indentation,
            y: (height - 17) / 2,
            width: width - valueWidth - 36 - indentation,
            height: 17
        )
        addSubview(nameLabel)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.frame = NSRect(
            x: width - valueWidth - 14,
            y: (height - 17) / 2,
            width: valueWidth,
            height: 17
        )
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, value: String, celsius: Double?, bold: Bool = false) {
        configure(
            name: name,
            value: value,
            dotColor: celsius.map(TemperatureStyle.dotColor) ?? .tertiaryLabelColor,
            bold: bold
        )
    }

    func configure(name: String, value: String, dotColor: NSColor, bold: Bool = false) {
        configure(
            name: name,
            value: value,
            dotColor: dotColor,
            valueColor: bold ? .labelColor : .secondaryLabelColor,
            bold: bold
        )
    }

    func configure(name: String, value: String, dotColor: NSColor, valueColor: NSColor, bold: Bool = false) {
        nameLabel.stringValue = name
        nameLabel.font = bold ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
        valueLabel.stringValue = value
        valueLabel.textColor = valueColor
        dot.color = dotColor
    }

    func configure(name: String, attributedValue: NSAttributedString, dotColor: NSColor) {
        nameLabel.stringValue = name
        nameLabel.font = .systemFont(ofSize: 13)
        valueLabel.attributedStringValue = attributedValue
        dot.color = dotColor
    }
}
