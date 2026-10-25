import Foundation

enum MenuBarMode: String {
    case cpuMax
    case systemMax
    case storage
    case specificSensor
    case iconOnly
}

enum TemperatureUnit: String {
    case celsius
    case fahrenheit

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    func convert(_ celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let mode = "menuBarMode"
        static let sensor = "menuBarSensor"
        static let showIcon = "showMenuBarIcon"
        static let unit = "temperatureUnit"
        static let interval = "refreshInterval"
        static let restoreFans = "restoreFansOnQuit"
        static let manualTargets = "manualFanTargets"
        static let networkBar = "showNetworkInMenuBar"
        static let autoUpdates = "autoUpdates"
        static let diskBar = "showDiskInMenuBar"
        static let diskInternal = "diskIncludeInternal"
        static let showTemperature = "showTemperatureInMenuBar"
        static let compactRates = "compactMenuBarRates"
        static let alertsEnabled = "temperatureAlertsEnabled"
        static let alertThreshold = "temperatureAlertThreshold"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.mode: MenuBarMode.cpuMax.rawValue,
            Key.showIcon: true,
            Key.unit: TemperatureUnit.celsius.rawValue,
            Key.interval: 2.0,
            Key.restoreFans: true,
            Key.networkBar: true,
            Key.autoUpdates: true,
            Key.diskBar: true,
            Key.diskInternal: false,
            Key.showTemperature: true,
            Key.compactRates: false,
            Key.alertsEnabled: false,
            Key.alertThreshold: 92.0
        ])
    }

    var mode: MenuBarMode {
        get { MenuBarMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .cpuMax }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    var sensorName: String? {
        get { defaults.string(forKey: Key.sensor) }
        set { defaults.set(newValue, forKey: Key.sensor) }
    }

    var showIcon: Bool {
        get { defaults.bool(forKey: Key.showIcon) }
        set { defaults.set(newValue, forKey: Key.showIcon) }
    }

    var unit: TemperatureUnit {
        get { TemperatureUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .celsius }
        set { defaults.set(newValue.rawValue, forKey: Key.unit) }
    }

    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.interval)
            return [1.0, 2.0, 5.0, 10.0, 30.0].contains(value) ? value : 2.0
        }
        set { defaults.set(newValue, forKey: Key.interval) }
    }

    var restoreFansOnQuit: Bool {
        get {
            if defaults.object(forKey: Key.restoreFans) == nil { return true }
            return defaults.bool(forKey: Key.restoreFans)
        }
        set { defaults.set(newValue, forKey: Key.restoreFans) }
    }

    var manualFanTargets: [Int: Double] {
        get {
            let stored = defaults.dictionary(forKey: Key.manualTargets) ?? [:]
            var result: [Int: Double] = [:]
            for (key, value) in stored {
                if let index = Int(key), let rpm = value as? Double {
                    result[index] = rpm
                }
            }
            return result
        }
        set {
            let stored = Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })
            defaults.set(stored, forKey: Key.manualTargets)
        }
    }

    func setManualTarget(fan: Int, rpm: Double?) {
        var targets = manualFanTargets
        targets[fan] = rpm
        manualFanTargets = targets
    }

    func clearManualTargets() {
        manualFanTargets = [:]
    }

    var showNetworkInMenuBar: Bool {
        get {
            if defaults.object(forKey: Key.networkBar) == nil { return true }
            return defaults.bool(forKey: Key.networkBar)
        }
        set { defaults.set(newValue, forKey: Key.networkBar) }
    }

    var autoUpdates: Bool {
        get {
            if defaults.object(forKey: Key.autoUpdates) == nil { return true }
            return defaults.bool(forKey: Key.autoUpdates)
        }
        set { defaults.set(newValue, forKey: Key.autoUpdates) }
    }

    var showDiskInMenuBar: Bool {
        get {
            if defaults.object(forKey: Key.diskBar) == nil { return true }
            return defaults.bool(forKey: Key.diskBar)
        }
        set { defaults.set(newValue, forKey: Key.diskBar) }
    }

    var diskIncludeInternal: Bool {
        get { defaults.bool(forKey: Key.diskInternal) }
        set { defaults.set(newValue, forKey: Key.diskInternal) }
    }

    var showTemperatureInMenuBar: Bool {
        get {
            if defaults.object(forKey: Key.showTemperature) == nil { return true }
            return defaults.bool(forKey: Key.showTemperature)
        }
        set { defaults.set(newValue, forKey: Key.showTemperature) }
    }

    var compactRates: Bool {
        get { defaults.bool(forKey: Key.compactRates) }
        set { defaults.set(newValue, forKey: Key.compactRates) }
    }

    var alertsEnabled: Bool {
        get { defaults.bool(forKey: Key.alertsEnabled) }
        set { defaults.set(newValue, forKey: Key.alertsEnabled) }
    }

    var alertThreshold: Double {
        get {
            let value = defaults.double(forKey: Key.alertThreshold)
            return value > 0 ? value : 92.0
        }
        set { defaults.set(newValue, forKey: Key.alertThreshold) }
    }
}
