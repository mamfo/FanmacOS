import AppKit
import CoreGraphics

final class FanWindowController: NSWindowController {
    private let service = FanControlService()
    private let prefs = Preferences.shared
    private var fans: [FanInfo] = []
    private var cards: [FanCardView] = []
    private let cardsStack = NSStackView()
    private let helperLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let autoAllButton = NSButton(title: "Tudo automático", target: nil, action: nil)
    private let maxButton = NSButton(title: "Máximo", target: nil, action: nil)
    private var restoreCheckbox: NSButton!
    private var isApplying = false
    private var curveActive = false
    private var isUpdatingCurve = false
    private var curveCheckbox: NSButton!
    private var profilePopup: NSPopUpButton!
    private var curveStartSlider: NSSlider!
    private var curveFullSlider: NSSlider!
    private var curveStartLabel: NSTextField!
    private var curveFullLabel: NSTextField!
    private var curveStatusLabel: NSTextField!

    var onCurveToggle: ((Bool) -> Void)?
    var onCurveSettingsChanged: ((Double, Double) -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Controlo das ventoinhas"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        placeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func placeWindow() {
        guard let window, let screen = Self.preferredScreen() else { return }

        let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(displayNumber?.uint32Value ?? 0)
        let isBuiltIn = displayID != 0 && CGDisplayIsBuiltin(displayID) != 0

        window.setFrameOrigin(Self.windowOrigin(
            visibleFrame: screen.visibleFrame,
            notchLeft: screen.auxiliaryTopLeftArea?.maxX,
            isBuiltIn: isBuiltIn,
            windowSize: window.frame.size
        ))
    }

    static func preferredScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            return notched
        }

        if let builtIn = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtIn
        }

        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func windowOrigin(
        visibleFrame: NSRect,
        notchLeft: CGFloat?,
        isBuiltIn: Bool,
        windowSize: NSSize
    ) -> NSPoint {
        let margin: CGFloat = 12

        if isBuiltIn || notchLeft != nil {
            let rightLimit = notchLeft ?? (visibleFrame.midX - 40)
            let x = max(visibleFrame.minX + margin, rightLimit - windowSize.width - margin)
            let y = visibleFrame.maxY - windowSize.height - margin
            return NSPoint(x: x, y: y)
        }

        return NSPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2
        )
    }

    func setStatus(_ message: String) {
        statusLabel.stringValue = message
    }

    func reloadCurvePreferences() {
        guard curveCheckbox != nil else { return }
        isUpdatingCurve = true
        curveCheckbox.state = prefs.fanCurveEnabled ? .on : .off
        let settings = FanCurve.normalizedSettings(start: prefs.fanCurveStart, full: prefs.fanCurveFull)
        updateProfileSelection(start: settings.start, full: settings.full)
        curveStartSlider.doubleValue = settings.start
        curveFullSlider.doubleValue = settings.full
        updateCurveLabels()
        curveStatusLabel.stringValue = prefs.fanCurveEnabled ? "A preparar curva…" : "Curva desligada."
        isUpdatingCurve = false
    }

    func setCurveStatus(active: Bool, target: Double?, temperature: Double?, message: String?) {
        curveActive = active
        isUpdatingCurve = true
        curveCheckbox.state = prefs.fanCurveEnabled ? .on : .off
        if let target {
            var status = "Ativa · alvo \(FanCardView.rpmText(target))"
            if let temperature {
                status += String(format: " · CPU %.0f °C", temperature)
            }
            curveStatusLabel.stringValue = status
        } else if let message {
            curveStatusLabel.stringValue = message
        } else {
            curveStatusLabel.stringValue = active ? "Curva ativa." : "Curva desligada."
        }
        isUpdatingCurve = false

        for card in cards {
            card.setCurveActive(active)
        }
        maxButton.isEnabled = !fans.isEmpty && !active
    }

    private func updateCurveLabels() {
        curveStartLabel.stringValue = String(format: "Início: %.0f °C", curveStartSlider.doubleValue)
        curveFullLabel.stringValue = String(format: "Máximo: %.0f °C", curveFullSlider.doubleValue)
    }

    private func updateProfileSelection(start: Double, full: Double) {
        guard profilePopup != nil else { return }
        if let profile = FanProfile.matching(start: start, full: full),
           let index = FanProfile.allCases.firstIndex(of: profile) {
            profilePopup.selectItem(at: index)
        } else {
            profilePopup.selectItem(at: FanProfile.allCases.count)
        }
    }

    func update(fans: [FanInfo]) {
        self.fans = fans

        if cards.count != fans.count {
            rebuildCards()
        }
        for (card, fan) in zip(cards, fans) {
            card.setFan(fan)
            if curveActive {
                card.setCurveActive(true)
            }
        }

        autoAllButton.isEnabled = !fans.isEmpty
        maxButton.isEnabled = !fans.isEmpty && !curveActive
        updateHelperLabel()

        if fans.isEmpty {
            statusLabel.stringValue = "Este Mac não tem ventoinhas controláveis."
        }
    }

    private func buildContent() {
        guard let window else { return }

        let content = NSView()
        window.contentView = content

        let title = NSTextField(labelWithString: "Ventoinhas")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "As ventoinhas seguem o macOS por omissão e voltam ao automático ao reiniciar.")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        curveCheckbox = NSButton(
            checkboxWithTitle: "Curva automática pela temperatura da CPU",
            target: self,
            action: #selector(curveToggled)
        )
        curveCheckbox.font = .systemFont(ofSize: 12, weight: .medium)
        curveCheckbox.state = prefs.fanCurveEnabled ? .on : .off

        profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        profilePopup.addItems(withTitles: FanProfile.allCases.map(\.title) + ["Personalizado"])
        profilePopup.target = self
        profilePopup.action = #selector(curveProfileChanged)

        let profileRow = NSStackView(views: [
            NSTextField(labelWithString: "Perfil:"),
            profilePopup
        ])
        profileRow.orientation = .horizontal
        profileRow.spacing = 8

        let curveSettings = FanCurve.normalizedSettings(start: prefs.fanCurveStart, full: prefs.fanCurveFull)
        curveStartLabel = NSTextField(labelWithString: "")
        curveStartLabel.font = .systemFont(ofSize: 10.5)
        curveStartLabel.textColor = .secondaryLabelColor
        curveStartSlider = NSSlider(
            value: curveSettings.start,
            minValue: 30,
            maxValue: 95,
            target: self,
            action: #selector(curveSliderChanged)
        )
        curveStartSlider.isContinuous = false

        curveFullLabel = NSTextField(labelWithString: "")
        curveFullLabel.font = .systemFont(ofSize: 10.5)
        curveFullLabel.textColor = .secondaryLabelColor
        curveFullSlider = NSSlider(
            value: curveSettings.full,
            minValue: 40,
            maxValue: 105,
            target: self,
            action: #selector(curveSliderChanged)
        )
        curveFullSlider.isContinuous = false

        curveStatusLabel = NSTextField(wrappingLabelWithString: "")
        curveStatusLabel.font = .systemFont(ofSize: 10.5)
        curveStatusLabel.textColor = .secondaryLabelColor
        updateCurveLabels()

        let curveStack = NSStackView(views: [
            curveCheckbox,
            profileRow,
            curveStartLabel,
            curveStartSlider,
            curveFullLabel,
            curveFullSlider,
            curveStatusLabel
        ])
        curveStack.orientation = .vertical
        curveStack.alignment = .leading
        curveStack.spacing = 4

        helperLabel.font = .systemFont(ofSize: 10.5)
        helperLabel.textColor = .secondaryLabelColor

        cardsStack.orientation = .vertical
        cardsStack.alignment = .leading
        cardsStack.spacing = 10

        let safety = NSTextField(wrappingLabelWithString: "As velocidades são limitadas ao mínimo e máximo de cada ventoinha. Reiniciar o Mac devolve sempre o controlo ao macOS.")
        safety.font = .systemFont(ofSize: 10.5)
        safety.textColor = .tertiaryLabelColor

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = ""

        autoAllButton.target = self
        autoAllButton.action = #selector(autoAll)
        autoAllButton.bezelStyle = .rounded

        maxButton.target = self
        maxButton.action = #selector(maximum)
        maxButton.bezelStyle = .rounded
        maxButton.toolTip = "Coloca as ventoinhas na velocidade máxima."

        restoreCheckbox = NSButton(
            checkboxWithTitle: "Restaurar automático ao sair",
            target: self,
            action: #selector(toggleRestore)
        )
        restoreCheckbox.state = prefs.restoreFansOnQuit ? .on : .off
        restoreCheckbox.font = .systemFont(ofSize: 11)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 8).isActive = true

        let buttons = NSStackView(views: [autoAllButton, maxButton, spacer, restoreCheckbox])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let footer = NSTextField(labelWithString: AppInfo.footer)
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        footer.alignment = .center

        let outer = NSStackView(views: [
            title,
            subtitle,
            curveStack,
            helperLabel,
            cardsStack,
            safety,
            statusLabel,
            buttons,
            footer
        ])
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 10
        outer.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(outer)

        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            outer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            outer.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            outer.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            subtitle.widthAnchor.constraint(equalTo: outer.widthAnchor),
            curveStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
            curveStartSlider.widthAnchor.constraint(equalTo: outer.widthAnchor),
            curveFullSlider.widthAnchor.constraint(equalTo: outer.widthAnchor),
            curveStatusLabel.widthAnchor.constraint(equalTo: outer.widthAnchor),
            helperLabel.widthAnchor.constraint(equalTo: outer.widthAnchor),
            cardsStack.widthAnchor.constraint(equalTo: outer.widthAnchor),
            safety.widthAnchor.constraint(equalTo: outer.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: outer.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: outer.widthAnchor),
            footer.widthAnchor.constraint(equalTo: outer.widthAnchor)
        ])
    }

    private func rebuildCards() {
        for view in cardsStack.arrangedSubviews {
            view.removeFromSuperview()
        }
        cards = fans.map { fan in
            let card = FanCardView(index: fan.index)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.onManualChange = { [weak self, weak card] enabled in
                guard let self, let card else { return }
                self.manualChanged(card: card, enabled: enabled)
            }
            card.onSpeedChange = { [weak self, weak card] rpm in
                guard let self, let card else { return }
                self.speedChanged(card: card, rpm: rpm)
            }
            cardsStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: cardsStack.widthAnchor).isActive = true
            if curveActive {
                card.setCurveActive(true)
            }
            return card
        }
    }

    private func updateHelperLabel() {
        if service.isReady {
            helperLabel.stringValue = "Assistente de ventoinhas instalado."
        } else if service.isInstalled {
            helperLabel.stringValue = "Assistente desatualizado; será atualizado na próxima alteração."
        } else {
            helperLabel.stringValue = "O controlo manual pede autorização de administrador uma vez."
        }
    }

    private func manualChanged(card: FanCardView, enabled: Bool) {
        guard !curveActive else { return }

        guard enabled else {
            do {
                if service.isInstalled {
                    try service.setAuto(fan: card.index)
                }
                prefs.setManualTarget(fan: card.index, rpm: nil)
                card.setControls(manual: false, rpm: card.currentRPM)
                statusLabel.stringValue = "Ventoinha \(card.index + 1) em automático."
            } catch {
                statusLabel.stringValue = error.localizedDescription
                card.setControls(manual: true, rpm: card.sliderRPM)
            }
            return
        }

        guard ensureHelper() else {
            card.setControls(manual: false, rpm: card.currentRPM)
            return
        }
        applySpeed(card: card, rpm: card.sliderRPM)
    }

    private func speedChanged(card: FanCardView, rpm: Double) {
        guard !curveActive, card.isManualEnabled, !isApplying else { return }
        guard ensureHelper() else {
            card.setControls(manual: false, rpm: card.currentRPM)
            return
        }
        applySpeed(card: card, rpm: rpm)
    }

    private func applySpeed(card: FanCardView, rpm: Double) {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            try service.setSpeed(fan: card.index, rpm: rpm)
            prefs.setManualTarget(fan: card.index, rpm: rpm)
            card.setControls(manual: true, rpm: rpm)
            statusLabel.stringValue = "Ventoinha \(card.index + 1) em manual a \(FanCardView.rpmText(rpm))."
        } catch {
            statusLabel.stringValue = error.localizedDescription
            try? service.setAuto(fan: card.index)
            card.setControls(manual: false, rpm: card.currentRPM)
        }
    }

    private func ensureHelper() -> Bool {
        if service.isReady {
            return true
        }

        let updating = service.isInstalled
        let alert = NSAlert()
        alert.messageText = updating
            ? "Atualizar o assistente de ventoinhas?"
            : "Autorizar o controlo das ventoinhas?"
        alert.informativeText = updating
            ? "O assistente instalado será atualizado. Será pedida a sua palavra-passe de administrador.\n\nO assistente só permite alterar a velocidade das ventoinhas."
            : "Para fixar a velocidade das ventoinhas, o FanmacOS instala um pequeno assistente em /Library/FanmacOS. Será pedida a sua palavra-passe de administrador uma vez.\n\nO assistente só permite alterar a velocidade das ventoinhas e pode ser removido no menu do FanmacOS."
        alert.alertStyle = .informational
        alert.addButton(withTitle: updating ? "Atualizar" : "Continuar")
        alert.addButton(withTitle: "Cancelar")

        guard alert.runModal() == .alertFirstButtonReturn else {
            statusLabel.stringValue = "Autorização cancelada."
            return false
        }

        do {
            try service.install()
            updateHelperLabel()
            statusLabel.stringValue = "Assistente instalado."
            return true
        } catch {
            statusLabel.stringValue = error.localizedDescription
            return false
        }
    }

    @objc private func autoAll() {
        if curveActive || prefs.fanCurveEnabled {
            isUpdatingCurve = true
            curveCheckbox.state = .off
            isUpdatingCurve = false
            onCurveToggle?(false)
            return
        }

        do {
            if service.isInstalled {
                try service.setAutoAll()
            }
            prefs.clearManualTargets()
            for card in cards {
                card.setControls(manual: false, rpm: card.currentRPM)
            }
            statusLabel.stringValue = "Controlo automático restaurado."
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func maximum() {
        guard !curveActive else { return }
        guard ensureHelper() else { return }
        do {
            try service.setMaximumAll()
            for card in cards {
                prefs.setManualTarget(fan: card.index, rpm: card.maxRPM)
                card.setControls(manual: true, rpm: card.maxRPM)
            }
            statusLabel.stringValue = "Ventoinhas na velocidade máxima."
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    @objc private func curveToggled() {
        guard !isUpdatingCurve else { return }
        let enabled = curveCheckbox.state == .on
        if enabled {
            guard ensureHelper() else {
                curveCheckbox.state = .off
                return
            }
        }
        onCurveToggle?(enabled)
    }

    @objc private func curveSliderChanged() {
        guard !isUpdatingCurve else { return }
        let settings = FanCurve.normalizedSettings(
            start: curveStartSlider.doubleValue,
            full: curveFullSlider.doubleValue
        )
        curveStartSlider.doubleValue = settings.start
        curveFullSlider.doubleValue = settings.full
        updateCurveLabels()
        updateProfileSelection(start: settings.start, full: settings.full)
        onCurveSettingsChanged?(settings.start, settings.full)
    }

    @objc private func curveProfileChanged() {
        guard !isUpdatingCurve else { return }
        let index = profilePopup.indexOfSelectedItem
        guard index >= 0, index < FanProfile.allCases.count else { return }
        let profile = FanProfile.allCases[index]

        isUpdatingCurve = true
        curveStartSlider.doubleValue = profile.start
        curveFullSlider.doubleValue = profile.full
        updateCurveLabels()
        isUpdatingCurve = false

        onCurveSettingsChanged?(profile.start, profile.full)
    }

    @objc private func toggleRestore() {
        prefs.restoreFansOnQuit = restoreCheckbox.state == .on
    }
}

final class FanCardView: NSView {
    let index: Int
    private let nameLabel = NSTextField(labelWithString: "")
    private let rpmLabel = NSTextField(labelWithString: "")
    private let modeLabel = NSTextField(labelWithString: "")
    private let manualSwitch = NSSwitch()
    private let switchLabel = NSTextField(labelWithString: "Manual")
    private let slider = NSSlider()
    private let rangeLabel = NSTextField(labelWithString: "")

    private(set) var currentRPM: Double = 0
    private(set) var maxRPM: Double = 0
    private var debounceWorkItem: DispatchWorkItem?
    private var lastAction = Date.distantPast
    private var curveActive = false

    var onManualChange: ((Bool) -> Void)?
    var onSpeedChange: ((Double) -> Void)?

    var sliderRPM: Double { slider.doubleValue }
    var isManualEnabled: Bool { manualSwitch.state == .on }

    private static let rpmFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.withAlphaComponent(0.65).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func setup() {
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.stringValue = "Ventoinha \(index + 1)"

        rpmLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        rpmLabel.stringValue = "--"

        modeLabel.font = .systemFont(ofSize: 10.5)
        modeLabel.textColor = .secondaryLabelColor

        switchLabel.font = .systemFont(ofSize: 11)
        switchLabel.textColor = .secondaryLabelColor

        manualSwitch.target = self
        manualSwitch.action = #selector(manualToggled)
        manualSwitch.controlSize = .small

        rangeLabel.font = .systemFont(ofSize: 10.5)
        rangeLabel.textColor = .tertiaryLabelColor

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true
        slider.isEnabled = false

        for view in [nameLabel, rpmLabel, modeLabel, manualSwitch, switchLabel, slider, rangeLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 124),

            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: switchLabel.leadingAnchor, constant: -8),

            switchLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            manualSwitch.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            manualSwitch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            switchLabel.trailingAnchor.constraint(equalTo: manualSwitch.leadingAnchor, constant: -6),

            rpmLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rpmLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            modeLabel.leadingAnchor.constraint(equalTo: rpmLabel.trailingAnchor, constant: 8),
            modeLabel.centerYAnchor.constraint(equalTo: rpmLabel.centerYAnchor),
            modeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            slider.topAnchor.constraint(equalTo: rpmLabel.bottomAnchor, constant: 8),

            rangeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rangeLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            rangeLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            rangeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    func setFan(_ fan: FanInfo) {
        currentRPM = fan.actualRPM
        maxRPM = fan.maxRPM

        nameLabel.stringValue = "Ventoinha \(fan.index + 1)"
        rpmLabel.stringValue = Self.rpmText(fan.actualRPM)

        let lower = fan.minRPM > 0 ? fan.minRPM : 1000
        let upper = max(fan.maxRPM, lower + 1)
        slider.minValue = lower
        slider.maxValue = upper
        rangeLabel.stringValue = "Intervalo: \(Self.rpmText(lower)) – \(Self.rpmText(upper))"

        if curveActive {
            manualSwitch.state = .off
            manualSwitch.isEnabled = false
            slider.isEnabled = false
            modeLabel.stringValue = "curva"
            modeLabel.textColor = .systemBlue
            slider.doubleValue = Self.clamp(fan.targetRPM, lower, upper)
            return
        }

        modeLabel.stringValue = fan.manual ? "manual" : "automático"
        modeLabel.textColor = fan.manual ? .systemOrange : .secondaryLabelColor

        guard Date().timeIntervalSince(lastAction) > 3 else { return }

        manualSwitch.state = fan.manual ? .on : .off
        slider.isEnabled = fan.manual
        let value = fan.manual ? fan.targetRPM : fan.actualRPM
        slider.doubleValue = Self.clamp(value, lower, upper)
    }

    func setCurveActive(_ active: Bool) {
        curveActive = active
        manualSwitch.isEnabled = !active
        switchLabel.textColor = active ? .tertiaryLabelColor : .secondaryLabelColor
        if active {
            manualSwitch.state = .off
            slider.isEnabled = false
            modeLabel.stringValue = "curva"
            modeLabel.textColor = .systemBlue
        }
    }

    func setControls(manual: Bool, rpm: Double) {
        lastAction = Date()
        manualSwitch.state = manual ? .on : .off
        slider.isEnabled = manual
        slider.doubleValue = Self.clamp(rpm, slider.minValue, slider.maxValue)
    }

    static func rpmText(_ value: Double) -> String {
        let number = rpmFormatter.string(from: NSNumber(value: value.rounded()))
            ?? String(Int(value.rounded()))
        return "\(number) rpm"
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    @objc private func manualToggled() {
        guard !curveActive else { return }
        lastAction = Date()
        let enabled = manualSwitch.state == .on
        slider.isEnabled = enabled
        onManualChange?(enabled)
    }

    @objc private func sliderChanged() {
        guard !curveActive else { return }
        lastAction = Date()
        rangeLabel.stringValue = "Alvo: \(Self.rpmText(slider.doubleValue))"

        debounceWorkItem?.cancel()
        let value = slider.doubleValue
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onSpeedChange?(value)
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
}
