import Foundation
import IOKit

enum SMCError: LocalizedError {
    case driverNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case smcResult(UInt8)
    case keyNotFound(String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .driverNotFound:
            return "O controlador AppleSMC não foi encontrado."
        case .openFailed(let code):
            return "Não foi possível abrir o AppleSMC (0x\(String(code, radix: 16)))."
        case .callFailed(let code):
            if code == kIOReturnNotPrivileged {
                return "Operação reservada ao administrador."
            }
            return "Comunicação com o SMC falhou (0x\(String(code, radix: 16)))."
        case .smcResult(let result):
            return "O SMC rejeitou o pedido (0x\(String(result, radix: 16)))."
        case .keyNotFound(let key):
            return "A chave SMC \(key) não existe neste Mac."
        case .invalidPayload:
            return "Valor inválido para o SMC."
        }
    }
}

struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var pad0: UInt8 = 0
    var pad1: UInt8 = 0
    var pad2: UInt8 = 0
}

typealias SMCBytes32 = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

enum SMCValue {
    static func number(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "fp2e":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 16384
        case "ui8 ", "ui8", "si8 ", "si8":
            return bytes.first.map(Double.init)
        case "ui16", "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            let value = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            return Double(value)
        default:
            return nil
        }
    }

    static func bytes(type: String, value: Double) -> [UInt8]? {
        switch type {
        case "flt ":
            let bits = Float(value).bitPattern
            return [
                UInt8(bits & 0xFF),
                UInt8((bits >> 8) & 0xFF),
                UInt8((bits >> 16) & 0xFF),
                UInt8((bits >> 24) & 0xFF)
            ]
        case "fpe2":
            let raw = UInt16(clamping: Int((value * 4).rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "fp2e":
            let raw = UInt16(clamping: Int((value * 16384).rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "ui8 ", "ui8":
            return [UInt8(clamping: Int(value.rounded()))]
        case "ui16":
            let raw = UInt16(clamping: Int(value.rounded()))
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            return nil
        }
    }
}

final class SMCConnection {
    private var connection: io_connect_t = 0

    static func fourCC(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    static func typeString(_ code: UInt32) -> String {
        let characters: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        return String(bytes: characters, encoding: .ascii) ?? ""
    }

    init() throws {
        guard MemoryLayout<SMCParamStruct>.stride == 80 else {
            throw SMCError.invalidPayload
        }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    private func perform(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let inputSize = MemoryLayout<SMCParamStruct>.stride

        let result = withUnsafePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPointer,
                    inputSize,
                    outputPointer,
                    &outputSize
                )
            }
        }

        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
        guard output.result == 0 else { throw SMCError.smcResult(output.result) }
        return output
    }

    func keyInfo(_ key: String) throws -> SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.data8 = 9
        return try perform(&input).keyInfo
    }

    func keyExists(_ key: String) -> Bool {
        (try? keyInfo(key)) != nil
    }

    func read(_ key: String) throws -> (type: String, bytes: [UInt8]) {
        let info = try keyInfo(key)
        guard info.dataSize > 0, info.dataSize <= 32 else { throw SMCError.invalidPayload }

        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5

        var output = try perform(&input)
        let bytes: [UInt8] = withUnsafeBytes(of: &output.bytes) { raw in
            Array(raw.prefix(Int(info.dataSize)))
        }
        return (Self.typeString(info.dataType), bytes)
    }

    func readNumber(_ key: String) throws -> Double {
        let result = try read(key)
        guard let value = SMCValue.number(type: result.type, bytes: result.bytes) else {
            throw SMCError.invalidPayload
        }
        return value
    }

    func write(_ key: String, bytes: [UInt8]) throws {
        let info = try keyInfo(key)
        guard info.dataSize > 0, info.dataSize <= 32 else { throw SMCError.invalidPayload }

        var input = SMCParamStruct()
        input.key = Self.fourCC(key)
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 6

        let count = min(Int(info.dataSize), 32, bytes.count)
        withUnsafeMutableBytes(of: &input.bytes) { raw in
            for index in 0..<count {
                raw[index] = bytes[index]
            }
        }
        _ = try perform(&input)
    }
}
