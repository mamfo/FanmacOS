import Foundation
import IOKit.hid

private typealias HIDEventSystemClient = CFTypeRef
private typealias HIDServiceClient = CFTypeRef
private typealias HIDEvent = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> HIDEventSystemClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: HIDEventSystemClient, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: HIDEventSystemClient) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: HIDServiceClient, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: HIDServiceClient, _ type: Int32, _ options: Int32, _ timestamp: Int64) -> HIDEvent?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: HIDEvent, _ field: Int32) -> Double

final class TemperatureMonitor {
    private static let temperatureEventType: Int32 = 15
    private static let temperatureLevelField: Int32 = 0x000F_0000
    private static let sensorMatching: [String: Int] = [
        "PrimaryUsagePage": 0xFF00,
        "PrimaryUsage": 5
    ]
    private static let serviceLifetime: TimeInterval = 60

    private var client: HIDEventSystemClient?
    private var services: [HIDServiceClient] = []
    private var serviceDate = Date.distantPast

    func invalidate() {
        services.removeAll()
        serviceDate = .distantPast
    }

    func snapshot() -> TemperatureSnapshot {
        reloadServicesIfNeeded()

        var readings: [String: Double] = [:]
        for service in services {
            guard let event = IOHIDServiceClientCopyEvent(service, Self.temperatureEventType, 0, 0) else {
                continue
            }
            let value = IOHIDEventGetFloatValue(event, Self.temperatureLevelField)
            guard value.isFinite, value > 0, value < 150 else { continue }

            guard let productRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
                  let product = productRef as? String,
                  !product.isEmpty else { continue }

            if product.localizedCaseInsensitiveContains("tcal") { continue }

            readings[product] = max(readings[product] ?? value, value)
        }

        let samples = readings
            .map { name, celsius in
                SensorSample(name: name, celsius: celsius, group: SensorGroup.group(for: name))
            }
            .sorted { lhs, rhs in
                if lhs.group != rhs.group {
                    return SensorGroup.allCases.firstIndex(of: lhs.group)! < SensorGroup.allCases.firstIndex(of: rhs.group)!
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        return TemperatureSnapshot(samples: samples, date: Date())
    }

    private func reloadServicesIfNeeded() {
        if client != nil, !services.isEmpty, Date().timeIntervalSince(serviceDate) < Self.serviceLifetime {
            return
        }

        services.removeAll()
        if client == nil {
            client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        }
        guard let client else { return }

        IOHIDEventSystemClientSetMatching(client, Self.sensorMatching as CFDictionary)
        if let list = IOHIDEventSystemClientCopyServices(client) as? [HIDServiceClient] {
            services = list
        }
        serviceDate = Date()
    }
}
