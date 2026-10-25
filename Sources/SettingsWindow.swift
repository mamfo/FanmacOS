import AppKit

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsWindowController: NSWindowController {
    private let prefs = Preferences.shared
    private let fanService = FanControlService()

    var onChange: (() -> Void)?
    var onOpenFans: (() -> Void)?
    var onCheckUpdates: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onTestAlert: (() -> Void)?
    var onEnableAlerts: (() -> Void)?

    private var presetPopup: NSPopUpButton!
    private var temperatureCheckbox: NSButton!
    private var batteryCheckbox: NSButton!
    private var powerCheckbox: NSButton!
    private var cpuCheckbox: NSButton!
    private var ramCheckbox: NSButton!
    private var networkCheckbox: NSButton!
    private var diskCheckbox: NSButton!
    private var compactCheckbox: NSButton!
    private var iconCheckbox: NSButton!
    private var unitPopup: NSPopUpButton!
    private var intervalPopup: NSPopUpButton!
    private var alertsCheckbox: NSButton!
    private var systemAlertsCheckbox: NSButton!
    private var quietCheckbox: NSButton!
    private var thresholdSlider: NSSlider!
    private var thresholdLabel: NSTextField!
    private var lowPowerCheckbox: NSButton!
    private var restoreFansCheckbox: NSButton!
    private var autoUpdatesCheckbox: NSButton!
    private var helperLabel: NSTextField!

    private let intervals: [TimeInterval] = [1, 2, 5, 10, 30]

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Definições do FanmacOS"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        reload()
        if let window {
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
                let visible = screen.visibleFrame
                window.setFrameOrigin(NSPoint(
                    x: visible.midX - window.frame.width / 2,
                    y: visible.midY - window.frame.height / 2
                ))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        guard temperatureCheckbox != nil else { return }

        updatePresetSelection()
        temperatureCheckbox.state = prefs.showTemperatureInMenuBar ? .on : .off
        batteryCheckbox.state = prefs.showBatteryInMenuBar ? .on : .off
        powerCheckbox.state = prefs.showPowerInMenuBar ? .on : .off
        cpuCheckbox.state = prefs.showCPUInMenuBar ? .on : .off
        ramCheckbox.state = prefs.showRAMInMenuBar ? .on : .off
        networkCheckbox.state = prefs.showNetworkInMenuBar ? .on : .off
        diskCheckbox.state = prefs.showDiskInMenuBar ? .on : .off
        compactCheckbox.state = prefs.compactRates ? .on : .off
        iconCheckbox.state = prefs.showIcon ? .on : .off
        unitPopup.selectItem(at: prefs.unit == .fahrenheit ? 1 : 0)
        intervalPopup.selectItem(at: intervals.firstIndex(of: prefs.refreshInterval) ?? 1)
        alertsCheckbox.state = prefs.alertsEnabled ? .on : .off
        systemAlertsCheckbox.state = prefs.systemAlertsEnabled ? .on : .off
        quietCheckbox.state = prefs.quietHoursEnabled ? .on : .off
        thresholdSlider.doubleValue = prefs.alertThreshold
        thresholdLabel.stringValue = String(format: "Limite: %.0f °C", prefs.alertThreshold)
        lowPowerCheckbox.state = prefs.lowPowerMode ? .on : .off
        restoreFansCheckbox.state = prefs.restoreFansOnQuit ? .on : .off
        autoUpdatesCheckbox.state = prefs.autoUpdates ? .on : .off
        helperLabel.stringValue = fanService.isReady
            ? "Assistente de ventoinhas instalado."
            : (fanService.isInstalled
                ? "Assistente de ventoinhas desatualizado."
                : "Assistente de ventoinhas não instalado.")
    }

    private func buildContent() {
        guard let window else { return }

        let content = NSView()
        window.contentView = content

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        content.addSubview(scrollView)

        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Definições")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopup.addItems(withTitles: BarPreset.allCases.map(\.title) + ["Personalizado"])
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        let presetRow = NSStackView(views: [
            NSTextField(labelWithString: "Preset da barra:"),
            presetPopup
        ])
        presetRow.orientation = .horizontal
        presetRow.spacing = 8

        temperatureCheckbox = checkbox("Mostrar temperatura na barra", action: #selector(changed))
        batteryCheckbox = checkbox("Mostrar bateria na barra", action: #selector(changed))
        powerCheckbox = checkbox("Mostrar consumo na barra (sem bateria)", action: #selector(changed))
        cpuCheckbox = checkbox("Mostrar CPU em uso na barra", action: #selector(changed))
        ramCheckbox = checkbox("Mostrar RAM em uso na barra", action: #selector(changed))
        networkCheckbox = checkbox("Mostrar rede na barra", action: #selector(changed))
        diskCheckbox = checkbox("Mostrar discos na barra", action: #selector(changed))
        compactCheckbox = checkbox("Valores compactos (K/M/G)", action: #selector(changed))
        iconCheckbox = checkbox("Mostrar ícone dentro da temperatura", action: #selector(changed))

        let unitRow = NSStackView(views: [
            NSTextField(labelWithString: "Unidade:"),
            makeUnitPopup()
        ])
        unitRow.orientation = .horizontal
        unitRow.spacing = 8

        let intervalRow = NSStackView(views: [
            NSTextField(labelWithString: "Atualizar a cada:"),
            makeIntervalPopup()
        ])
        intervalRow.orientation = .horizontal
        intervalRow.spacing = 8

        let dragNote = note("Mantém ⌘ e arrasta o item na barra para o colocares junto ao relógio. O macOS guarda a posição.")

        alertsCheckbox = checkbox("Ativar alertas", action: #selector(alertsChanged))
        systemAlertsCheckbox = checkbox("Bateria baixa, ventoinhas, carga alta e disco cheio", action: #selector(systemAlertsChanged))
        quietCheckbox = checkbox("Silêncio das notificações das 23:00 às 08:00", action: #selector(quietChanged))
        let testAlertButton = NSButton(title: "Enviar notificação de teste", target: self, action: #selector(testAlert))
        testAlertButton.bezelStyle = .rounded
        thresholdSlider = NSSlider(value: prefs.alertThreshold, minValue: 60, maxValue: 105, target: self, action: #selector(thresholdChanged))
        thresholdSlider.isContinuous = false
        thresholdSlider.translatesAutoresizingMaskIntoConstraints = false
        thresholdLabel = NSTextField(labelWithString: "")
        thresholdLabel.font = .systemFont(ofSize: 11)
        thresholdLabel.textColor = .secondaryLabelColor

        lowPowerCheckbox = checkbox("Poupar energia a baterias (intervalo ≥5 s)", action: #selector(changed))
        restoreFansCheckbox = checkbox("Restaurar automático ao sair", action: #selector(changed))
        let openFansButton = NSButton(title: "Abrir controlo das ventoinhas…", target: self, action: #selector(openFans))
        openFansButton.bezelStyle = .rounded

        helperLabel = NSTextField(labelWithString: "")
        helperLabel.font = .systemFont(ofSize: 10.5)
        helperLabel.textColor = .secondaryLabelColor

        let historyButton = NSButton(title: "Abrir histórico…", target: self, action: #selector(openHistory))
        historyButton.bezelStyle = .rounded

        autoUpdatesCheckbox = checkbox("Atualizações automáticas", action: #selector(changed))
        let checkUpdatesButton = NSButton(title: "Procurar atualizações…", target: self, action: #selector(checkUpdates))
        checkUpdatesButton.bezelStyle = .rounded

        let footer = NSTextField(labelWithString: AppInfo.footer)
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor

        let views: [NSView] = [
            title,
            section("BARRA DE MENUS"),
            presetRow,
            temperatureCheckbox,
            batteryCheckbox,
            powerCheckbox,
            cpuCheckbox,
            ramCheckbox,
            networkCheckbox,
            diskCheckbox,
            compactCheckbox,
            iconCheckbox,
            unitRow,
            intervalRow,
            dragNote,
            section("ALERTAS"),
            alertsCheckbox,
            systemAlertsCheckbox,
            quietCheckbox,
            testAlertButton,
            thresholdSlider,
            thresholdLabel,
            section("ENERGIA"),
            lowPowerCheckbox,
            section("VENTOINHAS"),
            restoreFansCheckbox,
            openFansButton,
            helperLabel,
            section("DADOS"),
            historyButton,
            section("ATUALIZAÇÕES"),
            autoUpdatesCheckbox,
            checkUpdatesButton,
            footer
        ]
        for view in views {
            stack.addArrangedSubview(view)
        }

        document.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
            dragNote.widthAnchor.constraint(equalTo: stack.widthAnchor),
            thresholdSlider.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func checkbox(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.font = .systemFont(ofSize: 12)
        return button
    }

    private func makeUnitPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Celsius (°C)", "Fahrenheit (°F)"])
        popup.target = self
        popup.action = #selector(changed)
        unitPopup = popup
        return popup
    }

    private func makeIntervalPopup() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: intervals.map { $0 == 1 ? "1 segundo" : "\(Int($0)) segundos" })
        popup.target = self
        popup.action = #selector(changed)
        intervalPopup = popup
        return popup
    }

    private func section(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 10.5)
        label.textColor = .tertiaryLabelColor
        return label
    }

    @objc private func changed() {
        prefs.showTemperatureInMenuBar = temperatureCheckbox.state == .on
        prefs.showNetworkInMenuBar = networkCheckbox.state == .on
        prefs.showBatteryInMenuBar = batteryCheckbox.state == .on
        prefs.showPowerInMenuBar = powerCheckbox.state == .on
        prefs.showCPUInMenuBar = cpuCheckbox.state == .on
        prefs.showRAMInMenuBar = ramCheckbox.state == .on
        updatePresetSelection()
        prefs.showDiskInMenuBar = diskCheckbox.state == .on
        prefs.compactRates = compactCheckbox.state == .on
        prefs.showIcon = iconCheckbox.state == .on
        prefs.unit = unitPopup.indexOfSelectedItem == 1 ? .fahrenheit : .celsius
        prefs.refreshInterval = intervals[max(0, min(intervalPopup.indexOfSelectedItem, intervals.count - 1))]
        prefs.lowPowerMode = lowPowerCheckbox.state == .on
        prefs.restoreFansOnQuit = restoreFansCheckbox.state == .on
        prefs.autoUpdates = autoUpdatesCheckbox.state == .on
        onChange?()
    }

    private func updatePresetSelection() {
        guard presetPopup != nil else { return }
        let current = BarPreset.matching(prefs)
        if let current, let index = BarPreset.allCases.firstIndex(of: current) {
            presetPopup.selectItem(at: index)
        } else {
            presetPopup.selectItem(at: BarPreset.allCases.count)
        }
    }

    @objc private func presetChanged() {
        let index = presetPopup.indexOfSelectedItem
        guard index >= 0, index < BarPreset.allCases.count else { return }
        BarPreset.allCases[index].apply(to: prefs)
        reload()
        onChange?()
    }

    @objc private func alertsChanged() {
        prefs.alertsEnabled = alertsCheckbox.state == .on
        if prefs.alertsEnabled {
            onEnableAlerts?()
        }
        onChange?()
    }

    @objc private func systemAlertsChanged() {
        prefs.systemAlertsEnabled = systemAlertsCheckbox.state == .on
        onChange?()
    }

    @objc private func quietChanged() {
        prefs.quietHoursEnabled = quietCheckbox.state == .on
    }

    @objc private func testAlert() {
        onTestAlert?()
    }

    @objc private func thresholdChanged() {
        prefs.alertThreshold = thresholdSlider.doubleValue
        thresholdLabel.stringValue = String(format: "Limite: %.0f °C", prefs.alertThreshold)
        onChange?()
    }

    @objc private func openFans() {
        onOpenFans?()
    }

    @objc private func checkUpdates() {
        onCheckUpdates?()
    }

    @objc private func openHistory() {
        onOpenHistory?()
    }
}
