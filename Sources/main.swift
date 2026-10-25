import AppKit

if CommandLine.arguments.contains("--dump") {
    let snapshot = TemperatureMonitor().snapshot()
    guard !snapshot.isEmpty else {
        print("Nenhum sensor de temperatura encontrado.")
        exit(1)
    }

    func line(_ label: String, _ value: Double?) {
        print(String(format: "%-22@ %6.1f °C", label as NSString, value ?? .nan))
    }

    line("CPU (máx)", snapshot.cpuMax)
    line("CPU (média)", snapshot.cpuAverage)
    line("SSD (máx)", snapshot.storageMax)
    line("Outros (máx)", snapshot.otherMax)
    line("Sistema (máx)", snapshot.systemMax)
    print("")

    if let fans = try? FanController().fans(), !fans.isEmpty {
        for fan in fans {
            print(String(
                format: "Ventoinha %d: %.0f rpm (min %.0f, max %.0f, alvo %.0f) · %@",
                fan.index + 1,
                fan.actualRPM,
                fan.minRPM,
                fan.maxRPM,
                fan.targetRPM,
                fan.manual ? "manual" : "auto"
            ))
        }
        print("")
    }

    for entry in snapshot.grouped {
        print("[\(entry.group.title)]")
        for sample in entry.samples {
            print(String(format: "  %-20@ %6.1f °C", sample.displayName as NSString, sample.celsius))
        }
    }
    exit(0)
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    FanmacOS — temperaturas do hardware na barra de menus

    Uso:
      FanmacOS           abre o app na barra de menus
      FanmacOS --dump    imprime temperaturas e ventoinhas e encerra
    """)
    exit(0)
}

let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
if !bundleIdentifier.isEmpty {
    let otherInstances = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if !otherInstances.isEmpty {
        exit(0)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
