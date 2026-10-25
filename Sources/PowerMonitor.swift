import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo {
    let percentage: Int
    let temperature: Double?
    let health: Double?
    let cycles: Int?
    let charging: Bool
    let externalPower: Bool
    let adapterWatts: Double?
}

struct EnergySnapshot {
    let cpuLoad: Double?
    let gpuLoad: Double?
    let memoryUsage: Double?
    let systemWatts: Double?
    let battery: BatteryInfo?
    let isOnBattery: Bool
    let date: Date

    static let empty = EnergySnapshot(
        cpuLoad: nil,
        gpuLoad: nil,
        memoryUsage: nil,
        systemWatts: nil,
        battery: nil,
        isOnBattery: false,
        date: .distantPast
    )
}

final class PowerMonitor {
    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64

        var busy: UInt64 { user + system + nice }
        var total: UInt64 { busy + idle }
    }

    private var previousTicks: [CPUTicks] = []
    private var hasPreviousTicks = false
    private let smc = try? SMCConnection()

    func sample() -> EnergySnapshot {
        let battery = readBattery()
        return EnergySnapshot(
            cpuLoad: readCPULoad(),
            gpuLoad: readGPULoad(),
            memoryUsage: readMemoryUsage(),
            systemWatts: readSystemWatts(),
            battery: battery,
            isOnBattery: battery.map { !$0.externalPower } ?? false,
            date: Date()
        )
    }

    private func readMemoryUsage() -> Double? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize > 0 ? pageSize : 4096)
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }

        let used = (UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)) * page
        return min(100, max(0, Double(used) / Double(total) * 100))
    }

    private func readSystemWatts() -> Double? {
        guard let smc else { return nil }
        for key in ["PSTR", "PDTR"] {
            if let value = try? smc.readNumber(key), value > 0, value < 2000 {
                return value
            }
        }
        return nil
    }

    private func readCPULoad() -> Double? {
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let loads = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { $0 }
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for index in 0..<Int(cpuCount) {
            let cpu = loads[index].cpu_ticks
            ticks.append(CPUTicks(
                user: UInt64(cpu.0),
                system: UInt64(cpu.1),
                idle: UInt64(cpu.2),
                nice: UInt64(cpu.3)
            ))
        }

        guard !ticks.isEmpty else { return nil }

        var busy: UInt64 = 0
        var total: UInt64 = 0

        if hasPreviousTicks, previousTicks.count == ticks.count {
            for (current, previous) in zip(ticks, previousTicks) {
                busy += current.busy >= previous.busy ? current.busy - previous.busy : 0
                total += current.total >= previous.total ? current.total - previous.total : 0
            }
        } else {
            for current in ticks {
                busy += current.busy
                total += current.total
            }
        }

        previousTicks = ticks
        hasPreviousTicks = true

        guard total > 0 else { return nil }
        return min(100, max(0, Double(busy) / Double(total) * 100))
    }

    private func readGPULoad() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }

            var propertiesRef: Unmanaged<CFMutableDictionary>?
            let result = IORegistryEntryCreateCFProperties(
                service,
                &propertiesRef,
                kCFAllocatorDefault,
                0
            )
            guard result == KERN_SUCCESS,
                  let properties = propertiesRef?.takeRetainedValue() as? [String: Any],
                  let statistics = properties["PerformanceStatistics"] as? [String: Any] else {
                continue
            }

            for key in ["Device Utilization %", "Renderer Utilization %"] {
                if let value = statistics[key] as? NSNumber {
                    return min(100, max(0, value.doubleValue))
                }
            }
        }

        return nil
    }

    private func readBattery() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return readIOPSBattery() }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(
            service,
            &propertiesRef,
            kCFAllocatorDefault,
            0
        )
        guard result == KERN_SUCCESS,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        guard (properties["BatteryInstalled"] as? Bool) == true else {
            return readIOPSBattery()
        }

        let current = (properties["CurrentCapacity"] as? NSNumber)?.doubleValue ?? 0
        let maxCapacity = (properties["MaxCapacity"] as? NSNumber)?.doubleValue ?? 0
        let percentage: Int
        if maxCapacity > 0, maxCapacity <= 100 {
            percentage = Int(current.rounded())
        } else if maxCapacity > 0 {
            percentage = Int((current / maxCapacity * 100).rounded())
        } else {
            percentage = 0
        }

        let rawMax = (properties["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue
        let health: Double?
        if let rawMax, let design, design > 0 {
            health = rawMax / design * 100
        } else if maxCapacity > 100, let design, design > 0 {
            health = maxCapacity / design * 100
        } else {
            health = nil
        }

        var temperature: Double?
        if let value = (properties["Temperature"] as? NSNumber)?.doubleValue, value > 0 {
            var celsius = value / 10
            if celsius > 100 { celsius -= 273.15 }
            if celsius > 0, celsius < 100 { temperature = celsius }
        }

        let cycles = (properties["CycleCount"] as? NSNumber)?.intValue
        let charging = (properties["IsCharging"] as? Bool) ?? false
        let externalPower = (properties["ExternalConnected"] as? Bool) ?? false

        var adapterWatts: Double?
        if externalPower, let adapter = properties["AdapterDetails"] as? [String: Any] {
            if let watts = adapter["Watts"] as? NSNumber {
                adapterWatts = watts.doubleValue
            } else if let wattage = adapter["Wattage"] as? NSNumber {
                adapterWatts = wattage.doubleValue
            } else if let volts = adapter["Voltage"] as? NSNumber,
                      let amps = adapter["Current"] as? NSNumber {
                adapterWatts = volts.doubleValue * amps.doubleValue / 1_000_000
            }
        }

        return BatteryInfo(
            percentage: min(100, max(0, percentage)),
            temperature: temperature,
            health: health.map { min(100, max(0, $0)) },
            cycles: cycles,
            charging: charging,
            externalPower: externalPower,
            adapterWatts: adapterWatts
        )
    }

    private func readIOPSBattery() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any] else {
                continue
            }
            guard (description[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType as String else {
                continue
            }

            let current = description[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let percentage = maximum > 0
                ? Int((Double(current) / Double(maximum) * 100).rounded())
                : current
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            let externalPower = state == kIOPSACPowerValue as String

            return BatteryInfo(
                percentage: min(100, max(0, percentage)),
                temperature: nil,
                health: nil,
                cycles: nil,
                charging: charging,
                externalPower: externalPower,
                adapterWatts: nil
            )
        }

        return nil
    }
}
