import Foundation

enum FanControlBuild {
    static let helperVersion = "1"
    static let helperDirectory = "/Library/FanmacOS"
    static let helperPath = "/Library/FanmacOS/fanctl"
    static let sudoersPath = "/etc/sudoers.d/fanmacos"
}

enum FanError: LocalizedError {
    case noFans
    case unsupported
    case controlRejected
    case helperMissing
    case authorizationCancelled
    case installFailed(String)
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFans:
            return "Este Mac não tem ventoinhas controláveis."
        case .unsupported:
            return "Este modelo não expõe as chaves de controlo das ventoinhas."
        case .controlRejected:
            return "O macOS recusou o modo manual. Tente novamente após alguns segundos."
        case .helperMissing:
            return "O assistente de ventoinhas não está instalado."
        case .authorizationCancelled:
            return "Autorização cancelada."
        case .installFailed(let message):
            return "Não foi possível instalar o assistente: \(message)"
        case .helperFailed(let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "O assistente devolveu um erro." : detail
        }
    }
}

struct FanInfo: Equatable {
    let index: Int
    let actualRPM: Double
    let minRPM: Double
    let maxRPM: Double
    let targetRPM: Double
    let manual: Bool

    var isControllable: Bool { maxRPM > minRPM && minRPM > 0 }
}

final class FanController {
    private let smc: SMCConnection

    init() throws {
        smc = try SMCConnection()
    }

    func fanCount() -> Int {
        guard let value = try? smc.readNumber("FNum") else { return 0 }
        return max(0, min(Int(value), 8))
    }

    func modeKey(for index: Int) -> String? {
        for key in ["F\(index)md", "F\(index)Md"] where smc.keyExists(key) {
            return key
        }
        return nil
    }

    func isManual(_ index: Int) -> Bool {
        if let key = modeKey(for: index), let value = try? smc.readNumber(key) {
            return Int(value.rounded()) == 1
        }
        if let raw = try? smc.read("FS! "),
           let value = SMCValue.number(type: raw.type, bytes: raw.bytes) {
            let mask = UInt16(max(0, value))
            return (mask & (UInt16(1) << UInt16(max(0, min(index, 15))))) != 0
        }
        return false
    }

    func fan(at index: Int) -> FanInfo? {
        let count = fanCount()
        guard index >= 0, index < count else { return nil }

        let actual = (try? smc.readNumber("F\(index)Ac")) ?? 0
        let minimum = (try? smc.readNumber("F\(index)Mn")) ?? 0
        let maximum = (try? smc.readNumber("F\(index)Mx")) ?? 0
        guard actual > 0 || maximum > 0 else { return nil }
        let target = (try? smc.readNumber("F\(index)Tg")) ?? 0

        return FanInfo(
            index: index,
            actualRPM: actual,
            minRPM: minimum,
            maxRPM: maximum,
            targetRPM: target,
            manual: isManual(index)
        )
    }

    func fans() -> [FanInfo] {
        let count = fanCount()
        guard count > 0 else { return [] }
        return (0..<count).compactMap { fan(at: $0) }
    }

    func setManual(_ manual: Bool, fan index: Int) throws {
        if let key = modeKey(for: index) {
            let type = ((try? smc.read(key))?.type) ?? "ui8 "
            guard let payload = SMCValue.bytes(type: type, value: manual ? 1 : 0) else {
                throw FanError.unsupported
            }
            try smc.write(key, bytes: payload)
            return
        }

        guard let raw = try? smc.read("FS! "),
              let current = SMCValue.number(type: raw.type, bytes: raw.bytes) else {
            throw FanError.unsupported
        }
        let bit = UInt16(1) << UInt16(max(0, min(index, 15)))
        var mask = UInt16(max(0, current))
        mask = manual ? (mask | bit) : (mask & ~bit)
        guard let payload = SMCValue.bytes(type: raw.type, value: Double(mask)) else {
            throw FanError.unsupported
        }
        try smc.write("FS! ", bytes: payload)
    }

    func setTarget(rpm: Double, fan index: Int) throws {
        guard let info = fan(at: index), info.isControllable else { throw FanError.unsupported }
        let target = min(max(rpm, info.minRPM), info.maxRPM)
        let key = "F\(index)Tg"
        let type = try smc.read(key).type
        guard let payload = SMCValue.bytes(type: type, value: target) else {
            throw FanError.unsupported
        }
        try smc.write(key, bytes: payload)
    }

    func setSpeed(rpm: Double, fan index: Int) throws {
        guard let info = fan(at: index), info.isControllable else { throw FanError.unsupported }

        try setManual(true, fan: index)
        try setTarget(rpm: rpm, fan: index)
        Thread.sleep(forTimeInterval: 0.2)

        if !isManual(index), smc.keyExists("Ftst") {
            try? smc.write("Ftst", bytes: [1])
            Thread.sleep(forTimeInterval: 2.5)
            try setManual(true, fan: index)
            try setTarget(rpm: rpm, fan: index)
            Thread.sleep(forTimeInterval: 0.2)
        }

        guard isManual(index) else { throw FanError.controlRejected }

        let expected = min(max(rpm, info.minRPM), info.maxRPM)
        if let after = fan(at: index), abs(after.targetRPM - expected) > 50 {
            throw FanError.controlRejected
        }
    }

    func setSpeedAll(rpm: Double) throws {
        let list = fans()
        guard !list.isEmpty else { throw FanError.noFans }
        for fan in list {
            try setSpeed(rpm: rpm, fan: fan.index)
        }
    }

    func setAuto(fan index: Int) throws {
        try setManual(false, fan: index)
    }

    func setAutoAll() throws {
        for fan in fans() {
            try setManual(false, fan: fan.index)
        }
    }

    func setMaximumAll() throws {
        for fan in fans() {
            try setSpeed(rpm: fan.maxRPM, fan: fan.index)
        }
    }
}
