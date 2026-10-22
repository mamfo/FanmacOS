import Foundation
import IOKit

enum DiskKind: String {
    case internalDisk
    case sdCard
    case usb
    case external

    var label: String {
        switch self {
        case .internalDisk: return "SSD interno"
        case .sdCard: return "Cartão SD"
        case .usb: return "USB"
        case .external: return "Disco externo"
        }
    }
}

struct DiskInfo: Equatable {
    let bsdName: String
    let name: String
    let detail: String
    let kind: DiskKind
    let isInternal: Bool
    let readRate: Double
    let writeRate: Double
    let totalRead: UInt64
    let totalWrite: UInt64
}

struct DiskSnapshot {
    let disks: [DiskInfo]
    let date: Date

    static let empty = DiskSnapshot(disks: [], date: .distantPast)

    var externalDisks: [DiskInfo] { disks.filter { !$0.isInternal } }
    var internalDisks: [DiskInfo] { disks.filter(\.isInternal) }
    var isEmpty: Bool { disks.isEmpty }

    func totals(includeInternal: Bool) -> (read: Double, write: Double) {
        var read = 0.0
        var write = 0.0
        for disk in disks where !disk.isInternal || includeInternal {
            read += disk.readRate
            write += disk.writeRate
        }
        return (read, write)
    }
}

final class DiskMonitor {
    private struct RawDisk {
        let bsdName: String
        let readBytes: UInt64
        let writeBytes: UInt64
        let removable: Bool
        let ejectable: Bool
        let productName: String?
    }

    private struct DiskMetadata {
        let name: String
        let detail: String
        let kind: DiskKind
        let isInternal: Bool
        let isVirtual: Bool
    }

    private var previous: [String: (read: UInt64, write: UInt64)] = [:]
    private var previousDate: Date?
    private var lastSnapshot: DiskSnapshot?
    private var metadata: [String: DiskMetadata] = [:]

    func reset() {
        previous = [:]
        previousDate = nil
        lastSnapshot = nil
        metadata = [:]
    }

    func sample() -> DiskSnapshot {
        let rawDisks = readRawDisks()
        let now = Date()

        if let lastSnapshot, let previousDate, now.timeIntervalSince(previousDate) < 0.4 {
            return lastSnapshot
        }

        let elapsed = previousDate.map { now.timeIntervalSince($0) } ?? 0
        let canMeasure = !previous.isEmpty && elapsed > 0.05 && elapsed < 120

        let activeNames = Set(rawDisks.map(\.bsdName))
        metadata = metadata.filter { activeNames.contains($0.key) }
        for disk in rawDisks where metadata[disk.bsdName] == nil {
            metadata[disk.bsdName] = fetchMetadata(for: disk)
        }

        var disks: [DiskInfo] = []
        for disk in rawDisks {
            guard let info = metadata[disk.bsdName], !info.isVirtual else { continue }

            var readRate = 0.0
            var writeRate = 0.0
            if canMeasure, let before = previous[disk.bsdName] {
                if disk.readBytes >= before.read {
                    readRate = Double(disk.readBytes - before.read) / elapsed
                }
                if disk.writeBytes >= before.write {
                    writeRate = Double(disk.writeBytes - before.write) / elapsed
                }
            }

            disks.append(DiskInfo(
                bsdName: disk.bsdName,
                name: info.name,
                detail: info.detail,
                kind: info.kind,
                isInternal: info.isInternal,
                readRate: readRate,
                writeRate: writeRate,
                totalRead: disk.readBytes,
                totalWrite: disk.writeBytes
            ))
        }

        previous = Dictionary(uniqueKeysWithValues: rawDisks.map {
            ($0.bsdName, (read: $0.readBytes, write: $0.writeBytes))
        })
        previousDate = now

        disks.sort { lhs, rhs in
            if lhs.isInternal != rhs.isInternal {
                return !lhs.isInternal
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let snapshot = DiskSnapshot(disks: disks, date: now)
        lastSnapshot = snapshot
        return snapshot
    }

    private func readRawDisks() -> [RawDisk] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [RawDisk] = []

        while case let driver = IOIteratorNext(iterator), driver != 0 {
            defer { IOObjectRelease(driver) }

            guard let statistics = property(driver, "Statistics") as? [String: Any] else {
                continue
            }
            let readBytes = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let writeBytes = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0

            guard let media = wholeMediaChild(of: driver) else { continue }
            defer { IOObjectRelease(media) }

            guard let bsdName = property(media, "BSD Name") as? String, !bsdName.isEmpty else {
                continue
            }

            let removable = property(media, "Removable") as? Bool ?? false
            let ejectable = property(media, "Ejectable") as? Bool ?? false
            let characteristics = parentProperty(driver, "Device Characteristics") as? [String: Any]
            let productName = characteristics?["Product Name"] as? String

            result.append(RawDisk(
                bsdName: bsdName,
                readBytes: readBytes,
                writeBytes: writeBytes,
                removable: removable,
                ejectable: ejectable,
                productName: productName
            ))
        }

        return result
    }

    private func fetchMetadata(for disk: RawDisk) -> DiskMetadata {
        if let fromDiskutil = diskutilMetadata(for: disk.bsdName) {
            return fromDiskutil
        }

        let isExternal = disk.removable || disk.ejectable
        let kind: DiskKind = isExternal ? .external : .internalDisk
        let fallbackName = disk.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (fallbackName?.isEmpty == false ? fallbackName! : (isExternal ? "Disco externo" : "SSD interno"))

        return DiskMetadata(
            name: name,
            detail: "\(name) · \(disk.bsdName)",
            kind: kind,
            isInternal: !isExternal,
            isVirtual: false
        )
    }

    private func diskutilMetadata(for bsdName: String) -> DiskMetadata? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", bsdName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }

        let isInternal = plist["Internal"] as? Bool ?? false
        let busProtocol = plist["BusProtocol"] as? String ?? ""
        let mediaName = (plist["MediaName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let virtualOrPhysical = plist["VirtualOrPhysical"] as? String ?? ""
        let removable = plist["RemovableMediaOrExternalDevice"] as? Bool ?? false

        let isVirtual = virtualOrPhysical == "Virtual"
            || busProtocol == "Disk Image"
            || mediaName == "Disk Image"

        let kind: DiskKind
        if isInternal {
            kind = .internalDisk
        } else if busProtocol.localizedCaseInsensitiveContains("secure digital")
            || busProtocol.localizedCaseInsensitiveContains("sdxc")
            || busProtocol.localizedCaseInsensitiveContains("sd card") {
            kind = .sdCard
        } else if busProtocol.localizedCaseInsensitiveContains("usb") {
            kind = .usb
        } else {
            kind = .external
        }

        var name: String
        if isInternal {
            name = "SSD interno"
        } else if kind == .sdCard {
            name = "Cartão SD"
        } else if !mediaName.isEmpty, mediaName != "Disk Image" {
            name = mediaName
        } else if kind == .usb {
            name = "Disco USB"
        } else if removable {
            name = "Disco externo"
        } else {
            name = "Disco"
        }

        if name.isEmpty {
            name = bsdName
        }

        let detailParts = [mediaName, busProtocol, bsdName].filter { !$0.isEmpty }
        return DiskMetadata(
            name: name,
            detail: detailParts.joined(separator: " · "),
            kind: kind,
            isInternal: isInternal,
            isVirtual: isVirtual
        )
    }

    private func wholeMediaChild(of driver: io_registry_entry_t) -> io_registry_entry_t? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(driver, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let child = IOIteratorNext(iterator), child != 0 {
            if (property(child, "Whole") as? Bool) == true {
                return child
            }
            IOObjectRelease(child)
        }
        return nil
    }

    private func parentProperty(_ service: io_registry_entry_t, _ key: String) -> Any? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }

        for _ in 0..<6 {
            if let value = property(current, key) {
                return value
            }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                return nil
            }
            IOObjectRelease(current)
            current = parent
        }

        return nil
    }

    private func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            service,
            key as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue()
    }
}
