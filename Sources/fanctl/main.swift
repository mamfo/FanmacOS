import Foundation

var stopRequested: sig_atomic_t = 0

func handleStopSignal(_ signalNumber: Int32) {
    stopRequested = 1
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    print("""
    fanctl — controlo das ventoinhas do FanmacOS

    Uso:
      fanctl version
      fanctl status
      fanctl set <rpm> [--fan N]
      fanctl max
      fanctl auto [--fan N]
      fanctl watch <pasta-de-controlo>

    As operações de escrita são executadas como root.
    """)
    exit(0)
}

func argument(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func requireRoot() {
    guard geteuid() == 0 else {
        fail("fanctl: esta operação tem de ser executada como root.", code: 3)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "status"

do {
    switch command {
    case "version":
        print(FanControlBuild.helperVersion)

    case "status":
        let controller = try FanController()
        let fans = controller.fans()
        if fans.isEmpty {
            print("sem ventoinhas")
        } else {
            for fan in fans {
                print(String(
                    format: "%d\t%.0f\t%.0f\t%.0f\t%.0f\t%@",
                    fan.index,
                    fan.actualRPM,
                    fan.targetRPM,
                    fan.minRPM,
                    fan.maxRPM,
                    fan.manual ? "manual" : "auto"
                ))
            }
        }

    case "set":
        guard arguments.count >= 2, let rpm = Double(arguments[1]), rpm.isFinite, rpm > 0 else {
            usage()
        }
        requireRoot()
        let controller = try FanController()
        if let rawFan = argument("--fan", in: arguments) {
            guard let index = Int(rawFan) else { fail("fanctl: índice de ventoinha inválido.") }
            try controller.setSpeed(rpm: rpm, fan: index)
            print("ventoinha \(index) em manual a \(Int(rpm)) rpm")
        } else {
            try controller.setSpeedAll(rpm: rpm)
            print("ventoinhas em manual a \(Int(rpm)) rpm")
        }

    case "max":
        requireRoot()
        try FanController().setMaximumAll()
        print("ventoinhas no máximo")

    case "auto":
        requireRoot()
        let controller = try FanController()
        if let rawFan = argument("--fan", in: arguments) {
            guard let index = Int(rawFan) else { fail("fanctl: índice de ventoinha inválido.") }
            try controller.setAuto(fan: index)
            print("ventoinha \(index) em automático")
        } else {
            try controller.setAutoAll()
            print("ventoinhas em automático")
        }

    case "watch":
        requireRoot()
        guard let directory = arguments.dropFirst().first else {
            fail("fanctl: uso: fanctl watch <pasta-de-controlo>")
        }

        signal(SIGTERM, handleStopSignal)
        signal(SIGINT, handleStopSignal)

        let targetPath = directory + "/target"
        let heartbeatPath = directory + "/heartbeat"
        let stopPath = directory + "/stop"
        let controller = try FanController()

        func restoreAutomatic() {
            try? controller.setAutoAll()
        }
        defer { restoreAutomatic() }

        var lastTarget = 0.0
        var lastApply = Date.distantPast
        var failures = 0

        while stopRequested == 0 {
            if FileManager.default.fileExists(atPath: stopPath) {
                break
            }

            guard let attributes = try? FileManager.default.attributesOfItem(atPath: heartbeatPath),
                  let heartbeat = attributes[.modificationDate] as? Date else {
                Thread.sleep(forTimeInterval: 0.25)
                continue
            }

            if Date().timeIntervalSince(heartbeat) > 20 {
                break
            }

            if let data = FileManager.default.contents(atPath: targetPath),
               let text = String(data: data, encoding: .utf8),
               let target = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
               target > 0 {
                let elapsed = Date().timeIntervalSince(lastApply)
                if abs(target - lastTarget) > 25 || elapsed > 2 {
                    do {
                        try controller.setSpeedAll(rpm: target)
                        lastTarget = target
                        lastApply = Date()
                        failures = 0
                    } catch {
                        failures += 1
                        if failures >= 3 {
                            break
                        }
                    }
                }
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        print("fanctl watch: a restaurar automático")

    case "help", "--help", "-h":
        usage()

    default:
        fail("fanctl: comando desconhecido '\(command)'.")
    }
} catch {
    fail("fanctl: \(error.localizedDescription)")
}
