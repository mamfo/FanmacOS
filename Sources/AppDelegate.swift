import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private let monitor = TemperatureMonitor()
    private let fanService = FanControlService()
    private let statusItem: NSStatusItem = {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "FanmacOSTemperature"
        return item
    }()
    private let menu = NSMenu()
    private let refreshIntervals: [TimeInterval] = [1, 2, 5, 10, 30]
    private var snapshot = TemperatureSnapshot.empty
    private var fans: [FanInfo] = []
    private var fanController: FanController? = try? FanController()
    private var fanWindow: FanWindowController?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastFanReassert = Date.distantPast
    private let networkMonitor = NetworkMonitor()
    private var networkSnapshot = NetworkSnapshot.empty
    private let diskMonitor = DiskMonitor()
    private var diskSnapshot = DiskSnapshot.empty
    private let updateService = UpdateService()
    private let alertManager = AlertManager()
    private var settingsWindow: SettingsWindowController?
    private var availableUpdate: UpdateInfo?
    private var updateCheckTimer: Timer?
    private var isCheckingForUpdates = false
    private var isPreparingUpdate = false
    private var isRelaunchingForUpdate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()

        menu.delegate = self
        menu.minimumWidth = 284
        statusItem.menu = menu

        refresh()
        if !fans.contains(where: { $0.manual }) {
            prefs.clearManualTargets()
        }
        scheduleTimer()
        scheduleUpdateChecks()

        if prefs.alertsEnabled {
            alertManager.requestAuthorization()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.monitor.invalidate()
            self.fanController = try? FanController()
            self.networkMonitor.reset()
            self.diskMonitor.reset()
            self.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.reapplyManualFans()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        updateCheckTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = statusImage()
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("Temperaturas do hardware")
        button.toolTip = "FanmacOS"
    }

    private func statusImage() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .medium)
        let image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "Temperatura")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "thermometer", accessibilityDescription: "Temperatura")
        image?.isTemplate = true
        return image
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: prefs.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = min(prefs.refreshInterval * 0.2, 1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        snapshot = monitor.snapshot()
        networkSnapshot = networkMonitor.sample()
        diskSnapshot = diskMonitor.sample()
        alertManager.evaluate(snapshot: snapshot)
        refreshFans()
        superviseManualFans()
        updateStatusItem()
        fanWindow?.update(fans: fans)
    }

    private func superviseManualFans() {
        let targets = prefs.manualFanTargets
        guard !targets.isEmpty, fanService.isInstalled else { return }

        let drifted = fans.contains { fan in
            guard let target = targets[fan.index] else { return false }
            return !fan.manual || abs(fan.targetRPM - target) > 50
        }
        guard drifted, Date().timeIntervalSince(lastFanReassert) > 4 else { return }

        lastFanReassert = Date()
        for (index, rpm) in targets {
            try? fanService.setSpeed(fan: index, rpm: rpm)
        }
    }

    private func refreshFans() {
        if fanController == nil {
            fanController = try? FanController()
        }
        fans = fanController?.fans() ?? []
    }

    private func reapplyManualFans() {
        let targets = prefs.manualFanTargets
        guard !targets.isEmpty, fanService.isInstalled else { return }
        for (index, rpm) in targets {
            try? fanService.setSpeed(fan: index, rpm: rpm)
        }
        refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isRelaunchingForUpdate { return .terminateNow }
        guard prefs.restoreFansOnQuit, fanService.isInstalled else { return .terminateNow }
        let manual = (fanController?.fans() ?? fans).contains { $0.manual }
        if manual {
            do {
                try fanService.setAutoAll()
                prefs.clearManualTargets()
            } catch {
                // As ventoinhas voltam ao automático no próximo arranque do Mac.
            }
        }
        return .terminateNow
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        let (value, caption) = displayedValue()
        let text = value.map { TemperatureStyle.compact($0, unit: prefs.unit) } ?? "--"

        if prefs.mode == .iconOnly {
            button.image = statusImage()
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        } else {
            var segments: [CapsuleSegment] = []
            let disks = relevantDisks
            let compact = prefs.compactRates

            if prefs.showDiskInMenuBar, !disks.isEmpty {
                let read = disks.reduce(0) { $0 + $1.readRate }
                let write = disks.reduce(0) { $0 + $1.writeRate }
                let symbol = disks.contains { !$0.isInternal } ? "externaldrive" : "internaldrive"
                let readText = compact ? RateFormatting.compact(read) : RateFormatting.rate(read)
                let writeText = compact ? RateFormatting.compact(write) : RateFormatting.rate(write)
                let width = compact ? StatusCapsuleImage.diskCompactTextWidth : StatusCapsuleImage.diskTextWidth

                segments.append(CapsuleSegment(
                    text: "R \(readText)",
                    color: DiskFormatting.readColor,
                    symbolName: symbol,
                    fixedTextWidth: width
                ))
                segments.append(CapsuleSegment(
                    text: "W \(writeText)",
                    color: DiskFormatting.writeColor,
                    fixedTextWidth: width
                ))
            }

            if prefs.showNetworkInMenuBar {
                let downText = compact ? RateFormatting.compact(networkSnapshot.download) : NetworkFormatting.rate(networkSnapshot.download)
                let upText = compact ? RateFormatting.compact(networkSnapshot.upload) : NetworkFormatting.rate(networkSnapshot.upload)
                let width = compact ? StatusCapsuleImage.networkCompactTextWidth : StatusCapsuleImage.networkTextWidth

                segments.append(CapsuleSegment(
                    text: "↓ \(downText)",
                    color: NetworkFormatting.downloadColor,
                    fixedTextWidth: width
                ))
                segments.append(CapsuleSegment(
                    text: "↑ \(upText)",
                    color: NetworkFormatting.uploadColor,
                    fixedTextWidth: width
                ))
            }

            if prefs.showTemperatureInMenuBar {
                let color = value.map(TemperatureStyle.capsuleColor) ?? TemperatureStyle.capsuleFallback
                segments.append(CapsuleSegment(
                    text: text,
                    color: color,
                    symbolName: prefs.showIcon ? "thermometer.medium" : nil,
                    fixedTextWidth: StatusCapsuleImage.temperatureTextWidth
                ))
            }

            if segments.isEmpty {
                button.image = statusImage()
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly
            } else {
                let image = StatusCapsuleImage.make(segments)
                button.image = image
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly

                if image == nil {
                    button.image = nil
                    button.attributedTitle = NSAttributedString(
                        string: text,
                        attributes: [
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                    button.imagePosition = .noImage
                }
            }
        }

        button.toolTip = tooltipText(caption: caption)
        button.setAccessibilityValue(text)
    }

    private func displayedValue() -> (Double?, String) {
        switch prefs.mode {
        case .cpuMax:
            return (snapshot.cpuMax, "CPU · máxima")
        case .systemMax:
            return (snapshot.systemMax, "Sistema · máxima")
        case .storage:
            return (snapshot.storageMax, "SSD · máxima")
        case .specificSensor:
            if let name = prefs.sensorName, let sample = snapshot.sample(named: name) {
                return (sample.celsius, sample.displayName)
            }
            return (snapshot.cpuMax, "CPU · máxima")
        case .iconOnly:
            return (snapshot.cpuMax, "CPU · máxima")
        }
    }

    private func tooltipText(caption: String) -> String {
        guard !snapshot.isEmpty else { return "FanmacOS · sem sensores disponíveis" }
        var lines = ["FanmacOS — \(caption)"]
        if let value = displayedValue().0 {
            lines.append(TemperatureStyle.text(value, unit: prefs.unit, decimals: 1))
        }
        if let cpu = snapshot.cpuMax, prefs.mode != .cpuMax {
            lines.append("CPU \(TemperatureStyle.text(cpu, unit: prefs.unit, decimals: 1))")
        }
        if let storage = snapshot.storageMax {
            lines.append("SSD \(TemperatureStyle.text(storage, unit: prefs.unit, decimals: 1))")
        }
        for fan in fans {
            lines.append("Ventoinha \(fan.index + 1): \(FanCardView.rpmText(fan.actualRPM))\(fan.manual ? " · manual" : "")")
        }
        lines.append("Rede ↓ \(NetworkFormatting.rate(networkSnapshot.download))  ↑ \(NetworkFormatting.rate(networkSnapshot.upload))")
        for disk in relevantDisks {
            lines.append("\(disk.name): R \(RateFormatting.rate(disk.readRate))  W \(RateFormatting.rate(disk.writeRate))")
        }
        let time = DateFormatter.localizedString(from: snapshot.date, dateStyle: .none, timeStyle: .medium)
        lines.append("Atualizado às \(time)")
        return lines.joined(separator: "\n")
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let (value, caption) = displayedValue()
        let header = MenuHeaderView(width: menu.minimumWidth)
        let detail: String
        if snapshot.isEmpty {
            detail = "Nenhum sensor de temperatura encontrado"
        } else if let average = snapshot.cpuAverage {
            detail = "Média da CPU \(TemperatureStyle.text(average, unit: prefs.unit, decimals: 1)) · \(snapshot.samples.count) sensores"
        } else {
            detail = "\(snapshot.samples.count) sensores"
        }
        header.configure(
            value: value.map { TemperatureStyle.text($0, unit: prefs.unit, decimals: 1) } ?? "--",
            color: value.map(TemperatureStyle.statusColor) ?? .secondaryLabelColor,
            caption: snapshot.isEmpty ? "Sem leituras" : caption,
            detail: detail
        )
        let headerItem = NSMenuItem()
        headerItem.view = header
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(.separator())

        menu.addItem(rowItem(name: "CPU · máxima", celsius: snapshot.cpuMax, bold: true))
        menu.addItem(rowItem(name: "CPU · média", celsius: snapshot.cpuAverage))
        menu.addItem(rowItem(name: "SSD · máxima", celsius: snapshot.storageMax))
        menu.addItem(rowItem(name: "Outros · máxima", celsius: snapshot.otherMax))

        menu.addItem(.separator())
        addFanItems()
        menu.addItem(.separator())
        addNetworkItems(to: menu)
        menu.addItem(.separator())
        addDiskItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(allSensorsItem())
        menu.addItem(.separator())

        menu.addItem(displayModeItem())
        menu.addItem(refreshIntervalItem())

        let iconItem = NSMenuItem(title: "Mostrar ícone na barra", action: #selector(toggleIcon), keyEquivalent: "")
        iconItem.target = self
        iconItem.state = prefs.showIcon ? .on : .off
        menu.addItem(iconItem)

        let temperatureBarItem = NSMenuItem(title: "Mostrar temperatura na barra", action: #selector(toggleTemperatureInBar), keyEquivalent: "")
        temperatureBarItem.target = self
        temperatureBarItem.state = prefs.showTemperatureInMenuBar ? .on : .off
        menu.addItem(temperatureBarItem)

        let networkBarItem = NSMenuItem(title: "Mostrar rede na barra", action: #selector(toggleNetworkInBar), keyEquivalent: "")
        networkBarItem.target = self
        networkBarItem.state = prefs.showNetworkInMenuBar ? .on : .off
        menu.addItem(networkBarItem)

        let diskBarItem = NSMenuItem(title: "Mostrar discos na barra", action: #selector(toggleShowDiskInBar), keyEquivalent: "")
        diskBarItem.target = self
        diskBarItem.state = prefs.showDiskInMenuBar ? .on : .off
        menu.addItem(diskBarItem)

        let internalDiskItem = NSMenuItem(title: "Incluir disco interno na barra", action: #selector(toggleIncludeInternalDisk), keyEquivalent: "")
        internalDiskItem.target = self
        internalDiskItem.state = prefs.diskIncludeInternal ? .on : .off
        menu.addItem(internalDiskItem)

        let compactItem = NSMenuItem(title: "Valores compactos (K/M/G)", action: #selector(toggleCompactRates), keyEquivalent: "")
        compactItem.target = self
        compactItem.state = prefs.compactRates ? .on : .off
        menu.addItem(compactItem)

        let unitItem = NSMenuItem(title: "Mostrar em Fahrenheit", action: #selector(toggleFahrenheit), keyEquivalent: "")
        unitItem.target = self
        unitItem.state = prefs.unit == .fahrenheit ? .on : .off
        menu.addItem(unitItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Iniciar ao iniciar sessão", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        let autoUpdateItem = NSMenuItem(title: "Atualizações automáticas", action: #selector(toggleAutoUpdates), keyEquivalent: "")
        autoUpdateItem.target = self
        autoUpdateItem.state = prefs.autoUpdates ? .on : .off
        menu.addItem(autoUpdateItem)

        let alertsItem = NSMenuItem(title: "Alertas de temperatura", action: #selector(toggleTemperatureAlerts), keyEquivalent: "")
        alertsItem.target = self
        alertsItem.state = prefs.alertsEnabled ? .on : .off
        menu.addItem(alertsItem)

        let refreshItem = NSMenuItem(title: "Atualizar agora", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        if let update = availableUpdate, !isPreparingUpdate, !isRelaunchingForUpdate {
            let updateItem = NSMenuItem(
                title: "Instalar atualização \(update.version)…",
                action: #selector(installAvailableUpdate),
                keyEquivalent: ""
            )
            updateItem.target = self
            menu.addItem(updateItem)
        }

        if isPreparingUpdate || isRelaunchingForUpdate {
            let status = NSMenuItem(
                title: isRelaunchingForUpdate ? "A instalar atualização…" : "A transferir atualização…",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
        } else {
            let checkItem = NSMenuItem(title: "Procurar atualizações…", action: #selector(checkForUpdatesMenu), keyEquivalent: "")
            checkItem.target = self
            menu.addItem(checkItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Definições…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "Sobre o FanmacOS", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Sair do FanmacOS", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.addItem(footerMenuItem())
    }

    private func footerMenuItem() -> NSMenuItem {
        let footer = NSMenuItem()
        footer.attributedTitle = NSAttributedString(
            string: AppInfo.footer,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        )
        footer.isEnabled = false
        return footer
    }

    private func addNetworkItems(to target: NSMenu) {
        target.addItem(networkRow(
            name: "↓ Receber",
            value: NetworkFormatting.rate(networkSnapshot.download),
            color: NetworkFormatting.downloadColor
        ))
        target.addItem(networkRow(
            name: "↑ Enviar",
            value: NetworkFormatting.rate(networkSnapshot.upload),
            color: NetworkFormatting.uploadColor
        ))

        let interfacesItem = NSMenuItem(title: "Interfaces", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Interfaces")
        submenu.minimumWidth = 284

        if networkSnapshot.interfaces.isEmpty {
            let empty = NSMenuItem(title: "Sem tráfego", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for network in networkSnapshot.interfaces {
                let row = SensorRowView(width: submenu.minimumWidth - 8, valueWidth: 176)
                row.configure(
                    name: network.name,
                    attributedValue: NetworkFormatting.coloredInterface(network),
                    dotColor: NetworkFormatting.downloadColor
                )
                let item = NSMenuItem()
                item.view = row
                item.isEnabled = false
                submenu.addItem(item)
            }
        }

        interfacesItem.submenu = submenu
        target.addItem(interfacesItem)
    }

    private func networkRow(name: String, value: String, color: NSColor) -> NSMenuItem {
        let view = SensorRowView(width: menu.minimumWidth - 8, valueWidth: 116)
        view.configure(name: name, value: value, dotColor: color, valueColor: color)
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    private func addDiskItems(to target: NSMenu) {
        target.addItem(sectionHeader("Discos"))

        guard !diskSnapshot.disks.isEmpty else {
            let item = NSMenuItem(title: "Sem discos detetados", action: nil, keyEquivalent: "")
            item.isEnabled = false
            target.addItem(item)
            return
        }

        for disk in diskSnapshot.disks {
            let view = SensorRowView(width: menu.minimumWidth - 8, valueWidth: 168)
            view.configure(
                name: disk.name,
                attributedValue: DiskFormatting.coloredSummary(read: disk.readRate, write: disk.writeRate),
                dotColor: disk.kind.dotColor
            )
            view.toolTip = "\(disk.detail) · leitura \(RateFormatting.rate(disk.readRate)) · escrita \(RateFormatting.rate(disk.writeRate))"

            let item = NSMenuItem()
            item.view = view
            item.isEnabled = false
            target.addItem(item)
        }
    }

    private var relevantDisks: [DiskInfo] {
        var result = diskSnapshot.externalDisks
        if prefs.diskIncludeInternal {
            result += diskSnapshot.internalDisks
        }
        return result
    }

    @objc private func toggleTemperatureInBar() {
        prefs.showTemperatureInMenuBar.toggle()
        updateStatusItem()
        settingsWindow?.reload()
    }

    @objc private func toggleShowDiskInBar() {
        prefs.showDiskInMenuBar.toggle()
        updateStatusItem()
        settingsWindow?.reload()
    }

    @objc private func toggleIncludeInternalDisk() {
        prefs.diskIncludeInternal.toggle()
        updateStatusItem()
        settingsWindow?.reload()
    }

    @objc private func toggleCompactRates() {
        prefs.compactRates.toggle()
        updateStatusItem()
        settingsWindow?.reload()
    }

    @objc private func toggleTemperatureAlerts() {
        prefs.alertsEnabled.toggle()
        if prefs.alertsEnabled {
            alertManager.requestAuthorization()
        }
        settingsWindow?.reload()
    }

    @objc private func toggleNetworkInBar() {
        prefs.showNetworkInMenuBar.toggle()
        updateStatusItem()
        settingsWindow?.reload()
    }

    private func rowItem(name: String, celsius: Double?, width: CGFloat? = nil, bold: Bool = false) -> NSMenuItem {
        let view = SensorRowView(width: width ?? (menu.minimumWidth - 8))
        view.configure(
            name: name,
            value: celsius.map { TemperatureStyle.text($0, unit: prefs.unit, decimals: 1) } ?? "--",
            celsius: celsius,
            bold: bold
        )
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        return item
    }

    private func addFanItems() {
        if fans.isEmpty {
            let item = NSMenuItem(title: "Sem ventoinhas detetadas", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for fan in fans {
                let view = SensorRowView(width: menu.minimumWidth - 8, valueWidth: 116)
                view.configure(
                    name: "Ventoinha \(fan.index + 1)",
                    value: "\(FanCardView.rpmText(fan.actualRPM)) · \(fan.manual ? "manual" : "auto")",
                    dotColor: fan.manual ? .systemOrange : .secondaryLabelColor,
                    valueColor: fan.manual ? .systemOrange : .secondaryLabelColor
                )
                let item = NSMenuItem()
                item.view = view
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        let control = NSMenuItem(title: "Controlo das ventoinhas…", action: #selector(openFanControl), keyEquivalent: "")
        control.target = self
        menu.addItem(control)

        if fanService.isInstalled {
            let remove = NSMenuItem(title: "Remover assistente de ventoinhas…", action: #selector(removeFanHelper), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
        }
    }

    @objc private func openFanControl() {
        refreshFans()
        if fanWindow == nil {
            fanWindow = FanWindowController()
        }
        fanWindow?.update(fans: fans)
        fanWindow?.show()
    }

    @objc private func removeFanHelper() {
        let alert = NSAlert()
        alert.messageText = "Remover o assistente de ventoinhas?"
        alert.informativeText = "As ventoinhas voltam ao controlo automático do macOS e o assistente é apagado de /Library/FanmacOS. Será pedida a palavra-passe de administrador."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remover")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try fanService.uninstall()
            prefs.clearManualTargets()
            refreshFans()
            fanWindow?.update(fans: fans)
            fanWindow?.setStatus("Assistente removido; ventoinhas em automático.")
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Não foi possível remover o assistente"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }

    private func allSensorsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Todos os sensores", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.minimumWidth = 272

        for entry in snapshot.grouped {
            submenu.addItem(sectionHeader(entry.group.title))
            for sample in entry.samples {
                submenu.addItem(rowItem(
                    name: sample.displayName,
                    celsius: sample.celsius,
                    width: submenu.minimumWidth - 8
                ))
            }
        }

        if snapshot.isEmpty {
            let empty = NSMenuItem(title: "Sem sensores disponíveis", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }

        item.submenu = submenu
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        item.isEnabled = false
        return item
    }

    private func displayModeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Mostrar na barra", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Mostrar na barra")

        let choices: [(String, MenuBarMode)] = [
            ("Temperatura da CPU", .cpuMax),
            ("Máxima do sistema", .systemMax),
            ("Temperatura do SSD", .storage),
            ("Só o ícone", .iconOnly)
        ]
        for (title, mode) in choices {
            submenu.addItem(choiceItem(title, action: #selector(selectMode), represented: mode.rawValue, checked: prefs.mode == mode))
        }

        submenu.addItem(.separator())

        let specific = NSMenuItem(title: "Sensor específico", action: nil, keyEquivalent: "")
        specific.state = prefs.mode == .specificSensor ? .on : .off
        let sensorsMenu = NSMenu(title: "Sensor específico")
        sensorsMenu.minimumWidth = 272
        for sample in snapshot.samples {
            sensorsMenu.addItem(choiceItem(
                sample.displayName,
                action: #selector(selectSpecificSensor),
                represented: sample.name,
                checked: prefs.mode == .specificSensor && prefs.sensorName == sample.name
            ))
        }
        if snapshot.isEmpty {
            let empty = NSMenuItem(title: "Sem sensores disponíveis", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sensorsMenu.addItem(empty)
        }
        specific.submenu = sensorsMenu
        submenu.addItem(specific)

        item.submenu = submenu
        return item
    }

    private func refreshIntervalItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Atualizar a cada", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Atualizar a cada")
        for interval in refreshIntervals {
            let title = interval == 1 ? "1 segundo" : "\(Int(interval)) segundos"
            submenu.addItem(choiceItem(
                title,
                action: #selector(selectInterval),
                represented: interval,
                checked: prefs.refreshInterval == interval
            ))
        }
        item.submenu = submenu
        return item
    }

    private func choiceItem(_ title: String, action: Selector, represented: Any, checked: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        item.state = checked ? .on : .off
        return item
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = MenuBarMode(rawValue: raw) else { return }
        prefs.mode = mode
        refresh()
    }

    @objc private func selectSpecificSensor(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        prefs.sensorName = name
        prefs.mode = .specificSensor
        refresh()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? Double else { return }
        prefs.refreshInterval = interval
        scheduleTimer()
    }

    @objc private func toggleIcon() {
        prefs.showIcon.toggle()
        updateStatusItem()
    }

    @objc private func toggleFahrenheit() {
        prefs.unit = prefs.unit == .celsius ? .fahrenheit : .celsius
        updateStatusItem()
    }

    @objc private func toggleLoginItem() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentLoginError(error)
        }
    }

    private func presentLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Não foi possível alterar o início automático"
        alert.informativeText = """
        \(error.localizedDescription)

        Dica: mova o FanmacOS para a pasta Aplicações e tente novamente.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func refreshNow() {
        monitor.invalidate()
        refresh()
    }

    @objc private func showAbout() {
        let credits = NSAttributedString(
            string: "Temperaturas dos sensores do hardware na barra de menus e controlo das ventoinhas.\nTemperaturas via IOHID e ventoinhas via SMC.\n\nDesenvolvido por \(AppInfo.developer)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "FanmacOS",
            .credits: credits
        ])
    }

    private func scheduleUpdateChecks() {
        updateCheckTimer?.invalidate()

        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates(userInitiated: false)
        }
        timer.tolerance = 600
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.checkForUpdates(userInitiated: false)
        }
    }

    @objc private func checkForUpdatesMenu() {
        checkForUpdates(userInitiated: true)
    }

    private func checkForUpdates(userInitiated: Bool) {
        guard !isPreparingUpdate, !isRelaunchingForUpdate else { return }
        guard !isCheckingForUpdates else {
            if userInitiated {
                presentSimpleAlert(
                    title: "A procurar atualizações",
                    message: "Já está a decorrer uma verificação."
                )
            }
            return
        }

        isCheckingForUpdates = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let update = try await self.updateService.check()
                self.isCheckingForUpdates = false

                if let update {
                    self.availableUpdate = update
                    if self.prefs.autoUpdates,
                       self.updateService.isRunningFromApplications,
                       !userInitiated {
                        self.beginUpdate(update, notifyErrors: false)
                    } else if userInitiated {
                        self.presentUpdateAvailable(update)
                    }
                } else if userInitiated {
                    self.presentSimpleAlert(
                        title: "O FanmacOS está atualizado",
                        message: "Versão \(AppInfo.version)."
                    )
                }
            } catch {
                self.isCheckingForUpdates = false
                if userInitiated {
                    self.presentUpdateError(error)
                }
            }
        }
    }

    @objc private func installAvailableUpdate() {
        guard let update = availableUpdate, !isPreparingUpdate else { return }

        guard updateService.isRunningFromApplications else {
            presentSimpleAlert(
                title: "Atualização manual necessária",
                message: "Para receber atualizações automáticas, arrasta o FanmacOS para a pasta Aplicações. Também podes descarregar a versão nova em github.com/mamfo/FanmacOS/releases."
            )
            return
        }

        beginUpdate(update, notifyErrors: true)
    }

    private func beginUpdate(_ update: UpdateInfo, notifyErrors: Bool) {
        guard !isPreparingUpdate, !isRelaunchingForUpdate else { return }
        isPreparingUpdate = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stagedApp = try await self.updateService.prepare(update)
                self.isRelaunchingForUpdate = true
                try self.updateService.install(stagedApp: stagedApp)
                self.isPreparingUpdate = false
                self.availableUpdate = nil
                NSApp.terminate(nil)
            } catch {
                self.isPreparingUpdate = false
                self.isRelaunchingForUpdate = false
                self.availableUpdate = update
                if notifyErrors {
                    self.presentUpdateError(error, update: update)
                }
            }
        }
    }

    private func presentUpdateAvailable(_ update: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "FanmacOS \(update.version) disponível"
        var message = "A app vai descarregar, instalar e reiniciar."
        if let notes = update.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            let snippet = notes.count > 400 ? String(notes.prefix(400)) + "…" : notes
            message += "\n\n" + snippet
        }
        alert.informativeText = message
        alert.addButton(withTitle: "Instalar agora")
        alert.addButton(withTitle: "Mais tarde")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            beginUpdate(update, notifyErrors: true)
        }
    }

    private func presentUpdateError(_ error: Error, update: UpdateInfo? = nil) {
        let alert = NSAlert()
        alert.messageText = "Não foi possível instalar a atualização"
        alert.informativeText = "\(error.localizedDescription)\n\nPodes descarregar a versão mais recente em github.com/mamfo/FanmacOS/releases."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Abrir página")
        alert.addButton(withTitle: "Fechar")
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update?.releaseURL ?? AppInfo.releasesURL)
        }
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleAutoUpdates() {
        prefs.autoUpdates.toggle()
        settingsWindow?.reload()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController()
            controller.onChange = { [weak self] in
                self?.scheduleTimer()
                self?.updateStatusItem()
            }
            controller.onOpenFans = { [weak self] in
                self?.openFanControl()
            }
            controller.onCheckUpdates = { [weak self] in
                self?.checkForUpdatesMenu()
            }
            controller.onEnableAlerts = { [weak self] in
                self?.alertManager.requestAuthorization()
            }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
