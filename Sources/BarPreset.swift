import Foundation

struct BarPresetFlags {
    let temperature: Bool
    let battery: Bool
    let power: Bool
    let network: Bool
    let disk: Bool
    let cpu: Bool
    let ram: Bool
}

enum BarPreset: String, CaseIterable {
    case minimum
    case temperatures
    case network
    case energy
    case all

    var title: String {
        switch self {
        case .minimum: return "Mínimo (temperatura)"
        case .temperatures: return "Temperaturas"
        case .network: return "Rede"
        case .energy: return "Energia"
        case .all: return "Tudo"
        }
    }

    var flags: BarPresetFlags {
        switch self {
        case .minimum:
            return BarPresetFlags(temperature: true, battery: false, power: false, network: false, disk: false, cpu: false, ram: false)
        case .temperatures:
            return BarPresetFlags(temperature: true, battery: true, power: true, network: false, disk: false, cpu: false, ram: false)
        case .network:
            return BarPresetFlags(temperature: false, battery: false, power: false, network: true, disk: false, cpu: false, ram: false)
        case .energy:
            return BarPresetFlags(temperature: false, battery: true, power: true, network: false, disk: false, cpu: true, ram: true)
        case .all:
            return BarPresetFlags(temperature: true, battery: true, power: true, network: true, disk: true, cpu: true, ram: true)
        }
    }

    func apply(to prefs: Preferences) {
        let flags = flags
        prefs.showTemperatureInMenuBar = flags.temperature
        prefs.showBatteryInMenuBar = flags.battery
        prefs.showPowerInMenuBar = flags.power
        prefs.showNetworkInMenuBar = flags.network
        prefs.showDiskInMenuBar = flags.disk
        prefs.showCPUInMenuBar = flags.cpu
        prefs.showRAMInMenuBar = flags.ram
    }

    static func matching(_ prefs: Preferences) -> BarPreset? {
        allCases.first { preset in
            let flags = preset.flags
            return prefs.showTemperatureInMenuBar == flags.temperature
                && prefs.showBatteryInMenuBar == flags.battery
                && prefs.showPowerInMenuBar == flags.power
                && prefs.showNetworkInMenuBar == flags.network
                && prefs.showDiskInMenuBar == flags.disk
                && prefs.showCPUInMenuBar == flags.cpu
                && prefs.showRAMInMenuBar == flags.ram
        }
    }
}
