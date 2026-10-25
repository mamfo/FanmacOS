import Foundation

enum SensorGroup: String, CaseIterable {
    case cpu
    case storage
    case other

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .storage: return "Armazenamento"
        case .other: return "Outros sensores"
        }
    }

    static func group(for product: String) -> SensorGroup {
        if product.localizedCaseInsensitiveContains("tdie") || product.hasPrefix("PMU TP") {
            return .cpu
        }
        if product.localizedCaseInsensitiveContains("nand") || product.localizedCaseInsensitiveContains("ssd") {
            return .storage
        }
        return .other
    }
}

struct SensorSample: Hashable {
    let name: String
    let celsius: Double
    let group: SensorGroup

    var displayName: String {
        if name.hasPrefix("PMU tdie") {
            return name.replacingOccurrences(of: "PMU tdie", with: "CPU · die ")
        }
        if name.hasPrefix("PMU tdev") {
            return name.replacingOccurrences(of: "PMU tdev", with: "Placa · sensor ")
        }
        if name.hasPrefix("PMU TP") {
            return name.replacingOccurrences(of: "PMU TP", with: "CPU · núcleo ")
        }
        if group == .storage, name.hasPrefix("NAND") {
            let cleaned = name.replacingOccurrences(of: " temp", with: "")
            return cleaned.replacingOccurrences(of: "NAND", with: "SSD · NAND")
        }
        return name
    }
}

struct TemperatureSnapshot {
    let samples: [SensorSample]
    let date: Date

    static let empty = TemperatureSnapshot(samples: [], date: .distantPast)

    var isEmpty: Bool { samples.isEmpty }

    private func values(_ group: SensorGroup) -> [Double] {
        samples.filter { $0.group == group }.map(\.celsius)
    }

    var cpuMax: Double? { values(.cpu).max() }
    var cpuAverage: Double? {
        let cpu = values(.cpu)
        guard !cpu.isEmpty else { return nil }
        return cpu.reduce(0, +) / Double(cpu.count)
    }
    var storageMax: Double? { values(.storage).max() }
    var otherMax: Double? { values(.other).max() }
    var systemMax: Double? { samples.map(\.celsius).max() }

    func sample(named name: String) -> SensorSample? {
        samples.first { $0.name == name }
    }

    var grouped: [(group: SensorGroup, samples: [SensorSample])] {
        SensorGroup.allCases.compactMap { group in
            let list = samples.filter { $0.group == group }
            return list.isEmpty ? nil : (group, list)
        }
    }
}
