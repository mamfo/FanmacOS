import Foundation
import Darwin

struct NetworkRate {
    let name: String
    let download: Double
    let upload: Double
}

struct NetworkSnapshot {
    let download: Double
    let upload: Double
    let interfaces: [NetworkRate]
    let date: Date

    static let empty = NetworkSnapshot(download: 0, upload: 0, interfaces: [], date: .distantPast)

    var isEmpty: Bool { interfaces.isEmpty }

    func rate(named name: String) -> NetworkRate? {
        interfaces.first { $0.name == name }
    }
}

final class NetworkMonitor {
    private struct Counters {
        let received: UInt64
        let sent: UInt64
    }

    private var previous: [String: Counters] = [:]
    private var previousDate: Date?

    func reset() {
        previous = [:]
        previousDate = nil
    }

    func sample() -> NetworkSnapshot {
        let counters = readCounters()
        let now = Date()
        defer {
            previous = counters
            previousDate = now
        }

        let elapsed = previousDate.map { now.timeIntervalSince($0) } ?? 0
        let canMeasure = !previous.isEmpty && elapsed > 0.05 && elapsed < 120

        var rates: [NetworkRate] = []
        for (name, current) in counters {
            var download = 0.0
            var upload = 0.0

            if canMeasure, let before = previous[name] {
                if current.received >= before.received {
                    download = Double(current.received - before.received) / elapsed
                }
                if current.sent >= before.sent {
                    upload = Double(current.sent - before.sent) / elapsed
                }
            }

            if download > 0 || upload > 0 || current.received + current.sent > 0 {
                rates.append(NetworkRate(name: name, download: download, upload: upload))
            }
        }

        rates.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return NetworkSnapshot(
            download: rates.reduce(0) { $0 + $1.download },
            upload: rates.reduce(0) { $0 + $1.upload },
            interfaces: rates,
            date: now
        )
    }

    private func readCounters() -> [String: Counters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0

        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [:] }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return [:] }

        var counters: [String: Counters] = [:]
        var offset = 0

        buffer.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0 else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2 {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let flags = message.ifm_flags
                    var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                    if let namePointer = if_indextoname(UInt32(message.ifm_index), &nameBuffer) {
                        let name = String(cString: namePointer)
                        let isUp = (flags & Int32(IFF_UP)) != 0
                        let isLoopback = (flags & Int32(IFF_LOOPBACK)) != 0
                        let isPhysical = name.hasPrefix("en") || name.hasPrefix("pdp_ip")

                        if isUp, !isLoopback, isPhysical {
                            counters[name] = Counters(
                                received: message.ifm_data.ifi_ibytes,
                                sent: message.ifm_data.ifi_obytes
                            )
                        }
                    }
                }

                offset += size
            }
        }

        return counters
    }
}
