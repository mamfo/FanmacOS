import AppKit
import UniformTypeIdentifiers

final class HistoryChartView: NSView {
    private var title = ""
    private var series: [(name: String, color: NSColor, values: [Double?])] = []
    private var dates: [Date] = []
    private var formatter: (Double) -> String = { String(format: "%.0f", $0) }

    func configure(
        title: String,
        series: [(name: String, color: NSColor, values: [Double?])],
        dates: [Date],
        formatter: @escaping (Double) -> String
    ) {
        self.title = title
        self.series = series
        self.dates = dates
        self.formatter = formatter
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
        let background = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        background.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        background.lineWidth = 1
        background.stroke()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        (title as NSString).draw(at: NSPoint(x: 12, y: bounds.height - 22), withAttributes: titleAttributes)

        let legendAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        var legendX = bounds.width - 12
        for item in series.reversed() {
            let size = (item.name as NSString).size(withAttributes: legendAttributes)
            legendX -= size.width
            (item.name as NSString).draw(at: NSPoint(x: legendX, y: bounds.height - 21), withAttributes: legendAttributes)
            legendX -= 14
            item.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: legendX, y: bounds.height - 16, width: 7, height: 7)).fill()
            legendX -= 10
        }

        let plot = NSRect(x: 44, y: 24, width: bounds.width - 58, height: bounds.height - 58)
        let grid = NSBezierPath()
        for index in 0...3 {
            let y = plot.minY + plot.height * CGFloat(index) / 3
            grid.move(to: NSPoint(x: plot.minX, y: y))
            grid.line(to: NSPoint(x: plot.maxX, y: y))
        }
        grid.move(to: NSPoint(x: plot.midX, y: plot.minY))
        grid.line(to: NSPoint(x: plot.midX, y: plot.maxY))
        NSColor.separatorColor.withAlphaComponent(0.25).setStroke()
        grid.lineWidth = 0.7
        grid.stroke()

        let allValues = series.flatMap { $0.values.compactMap { $0 } }
        guard !dates.isEmpty, !allValues.isEmpty else {
            let emptyAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            ("Sem dados" as NSString).draw(
                at: NSPoint(x: plot.midX - 28, y: plot.midY - 6),
                withAttributes: emptyAttributes
            )
            return
        }

        let maximum = allValues.max() ?? 1
        let minimum = allValues.min() ?? 0
        let lower: Double
        let upper: Double
        if maximum <= 1 {
            lower = 0
            upper = 1
        } else if maximum > 100 || (minimum > 0 && maximum > minimum * 4) {
            lower = 0
            upper = maximum * 1.1
        } else {
            lower = max(0, minimum - 2)
            upper = maximum + 2
        }
        let span = max(upper - lower, 0.001)
        let times = dates.map(\.timeIntervalSince1970)
        let firstTime = times.first ?? 0
        let lastTime = times.last ?? firstTime
        let timeSpan = max(lastTime - firstTime, 1)

        for item in series {
            let path = NSBezierPath()
            var started = false
            for index in item.values.indices {
                guard index < times.count, let value = item.values[index] else {
                    started = false
                    continue
                }
                let x = plot.minX + (times[index] - firstTime) / timeSpan * plot.width
                let y = plot.minY + (value - lower) / span * plot.height
                let point = NSPoint(x: x, y: y)
                if started {
                    path.line(to: point)
                } else {
                    path.move(to: point)
                    started = true
                }
            }
            item.color.setStroke()
            path.lineWidth = 1.6
            path.lineJoinStyle = .round
            path.stroke()
        }

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (formatter(upper) as NSString).draw(
            at: NSPoint(x: 6, y: plot.maxY - 5),
            withAttributes: labelAttributes
        )
        (formatter(lower) as NSString).draw(
            at: NSPoint(x: 6, y: plot.minY - 5),
            withAttributes: labelAttributes
        )

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        if let first = dates.first, let last = dates.last {
            let firstText = timeFormatter.string(from: first)
            let lastText = timeFormatter.string(from: last)
            (firstText as NSString).draw(
                at: NSPoint(x: plot.minX, y: 5),
                withAttributes: labelAttributes
            )
            let lastSize = (lastText as NSString).size(withAttributes: labelAttributes)
            (lastText as NSString).draw(
                at: NSPoint(x: plot.maxX - lastSize.width, y: 5),
                withAttributes: labelAttributes
            )
        }
    }
}

final class HistoryWindowController: NSWindowController {
    private let history: MetricsHistory
    private let temperatureChart = HistoryChartView()
    private let networkChart = HistoryChartView()
    private let diskChart = HistoryChartView()

    init(history: MetricsHistory) {
        self.history = history

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Histórico do FanmacOS"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        update(history)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        if let window, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(_ history: MetricsHistory) {
        let samples = history.samples
        let dates = samples.map(\.date)

        temperatureChart.configure(
            title: "Temperatura da CPU",
            series: [
                ("CPU", .systemGreen, samples.map { $0.cpuMax }),
                ("Sistema", .systemOrange, samples.map { $0.systemMax })
            ],
            dates: dates,
            formatter: { String(format: "%.0f °C", $0) }
        )

        networkChart.configure(
            title: "Rede",
            series: [
                ("Receber", NetworkFormatting.downloadColor, samples.map { $0.download }),
                ("Enviar", NetworkFormatting.uploadColor, samples.map { $0.upload })
            ],
            dates: dates,
            formatter: { RateFormatting.rate($0) }
        )

        diskChart.configure(
            title: "Discos",
            series: [
                ("Ler", DiskFormatting.readColor, samples.map { $0.diskRead }),
                ("Escrever", DiskFormatting.writeColor, samples.map { $0.diskWrite })
            ],
            dates: dates,
            formatter: { RateFormatting.rate($0) }
        )
    }

    private func buildContent() {
        guard let window else { return }

        let content = NSView()
        window.contentView = content

        let header = NSTextField(labelWithString: "Últimos 15 minutos")
        header.font = .systemFont(ofSize: 11)
        header.textColor = .secondaryLabelColor

        let export = NSButton(title: "Exportar CSV…", target: self, action: #selector(exportCSV))
        export.bezelStyle = .rounded
        let clear = NSButton(title: "Limpar", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [header, spacer, export, clear])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        for chart in [temperatureChart, networkChart, diskChart] {
            chart.translatesAutoresizingMaskIntoConstraints = false
            chart.heightAnchor.constraint(equalToConstant: 150).isActive = true
        }

        let stack = NSStackView(views: [buttons, temperatureChart, networkChart, diskChart])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -14),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            temperatureChart.widthAnchor.constraint(equalTo: stack.widthAnchor),
            networkChart.widthAnchor.constraint(equalTo: stack.widthAnchor),
            diskChart.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FanmacOS-historico.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try history.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Não foi possível exportar o histórico"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func clearHistory() {
        history.clear()
        update(history)
    }
}
