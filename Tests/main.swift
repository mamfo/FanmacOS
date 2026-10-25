import AppKit
import Foundation

var failures = 0

func check(_ condition: Bool, _ name: String) {
    print(condition ? "ok   \(name)" : "FAIL \(name)")
    if !condition { failures += 1 }
}

// Version comparison
check(UpdateService.isNewer("1.3", than: "1.2"), "versão 1.3 > 1.2")
check(UpdateService.isNewer("1.10", than: "1.9"), "versão 1.10 > 1.9")
check(!UpdateService.isNewer("2.0.0", than: "2.0"), "versão 2.0.0 == 2.0")
check(UpdateService.isNewer("v2.1", than: "2.0"), "tag v2.1 > 2.0")

// Rate formatting
check(RateFormatting.rate(0) == "0 B/s", "formato 0 B/s")
check(RateFormatting.rate(999).hasSuffix("B/s"), "formato B/s")
check(RateFormatting.rate(1_500).hasSuffix("KB/s"), "formato KB/s")
check(RateFormatting.rate(1_500_000).hasSuffix("MB/s"), "formato MB/s")
check(RateFormatting.rate(2_500_000_000).hasSuffix("GB/s"), "formato GB/s")
check(RateFormatting.compact(0) == "0B", "compacto 0B")
check(RateFormatting.compact(15_000).hasSuffix("K"), "compacto K")
check(RateFormatting.compact(1_500_000).hasSuffix("M"), "compacto M")

// Sensor names and aggregation
let cpu1 = SensorSample(name: "PMU tdie3", celsius: 42, group: .cpu)
let cpu2 = SensorSample(name: "PMU tdie4", celsius: 48, group: .cpu)
let nand = SensorSample(name: "NAND CH0 temp", celsius: 25, group: .storage)
let dev = SensorSample(name: "PMU tdev1", celsius: 38, group: .other)
check(cpu1.displayName == "CPU · die 3", "nome humano CPU")
check(nand.displayName == "SSD · NAND CH0", "nome humano SSD")
check(dev.displayName == "Placa · sensor 1", "nome humano placa")

let snapshot = TemperatureSnapshot(samples: [cpu1, cpu2, nand, dev], date: Date())
check(snapshot.cpuMax == 48, "CPU máxima")
check(snapshot.storageMax == 25, "SSD máxima")
check(snapshot.otherMax == 38, "Outros máxima")
check(snapshot.systemMax == 48, "Sistema máxima")
check(snapshot.cpuAverage == 45, "CPU média")

// Sensor grouping
check(SensorGroup.group(for: "PMU tdie0") == .cpu, "grupo tdie → CPU")
check(SensorGroup.group(for: "PMU TP0s") == .cpu, "grupo TP → CPU")
check(SensorGroup.group(for: "NAND CH0 temp") == .storage, "grupo NAND → SSD")
check(SensorGroup.group(for: "PMU tdev1") == .other, "grupo tdev → outros")

// Fixed capsule widths
check(StatusCapsuleImage.networkTextWidth > 0, "largura rede fixa")
check(StatusCapsuleImage.diskTextWidth > 0, "largura discos fixa")
check(StatusCapsuleImage.temperatureTextWidth > 0, "largura temperatura fixa")
check(StatusCapsuleImage.networkCompactTextWidth > 0, "largura rede compacta")
check(StatusCapsuleImage.diskCompactTextWidth > 0, "largura discos compacta")
check(StatusCapsuleImage.networkCompactTextWidth < StatusCapsuleImage.networkTextWidth, "compacto mais estreito")

// Window placement
let windowSize = NSSize(width: 460, height: 572)
let notched = NSRect(x: 0, y: 0, width: 3456, height: 2192)
let notchedOrigin = FanWindowController.windowOrigin(
    visibleFrame: notched,
    notchLeft: 1628,
    isBuiltIn: true,
    windowSize: windowSize
)
check(notchedOrigin.x == 1156, "janela 12 px à esquerda do notch")
check(notchedOrigin.y == 1608, "janela 12 px abaixo do topo")

let external = NSRect(x: 0, y: 0, width: 2560, height: 1410)
let externalOrigin = FanWindowController.windowOrigin(
    visibleFrame: external,
    notchLeft: nil,
    isBuiltIn: false,
    windowSize: windowSize
)
check(externalOrigin.x == 1050, "janela centrada em ecrã externo")

// Disk labels
check(DiskKind.sdCard.label == "Cartão SD", "etiqueta cartão SD")
check(DiskKind.usb.label == "USB", "etiqueta USB")
check(DiskKind.internalDisk.label == "SSD interno", "etiqueta SSD interno")

print("")
if failures == 0 {
    print("Todos os testes passaram.")
    exit(0)
} else {
    print("\(failures) teste(s) falharam.")
    exit(1)
}
