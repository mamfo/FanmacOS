import Foundation
import Darwin

struct NetworkAddress: Hashable {
    let interface: String
    let ipv4: String?
    let ipv6: String?

    var primary: String? { ipv4 ?? ipv6 }
}

enum NetworkAddressMonitor {
    static func current() -> [NetworkAddress] {
        var addresses: [String: (ipv4: String?, ipv6: String?)] = [:]
        var interfaces: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            return []
        }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            let interface = entry.pointee
            let name = String(cString: interface.ifa_name)
            let flags = interface.ifa_flags

            let isPhysical = name.hasPrefix("en") || name.hasPrefix("pdp_ip")
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0

            if isPhysical, isUp, !isLoopback, let address = interface.ifa_addr {
                let family = Int32(address.pointee.sa_family)
                if family == AF_INET || family == AF_INET6 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let length = socklen_t(address.pointee.sa_len)
                    if getnameinfo(
                        address,
                        length,
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        let ip = String(cString: host)
                        if family == AF_INET {
                            addresses[name, default: (nil, nil)].ipv4 = ip
                        } else if !ip.lowercased().hasPrefix("fe80") {
                            addresses[name, default: (nil, nil)].ipv6 = ip
                        }
                    }
                }
            }

            pointer = interface.ifa_next
        }

        return addresses
            .map { NetworkAddress(interface: $0.key, ipv4: $0.value.ipv4, ipv6: $0.value.ipv6) }
            .sorted { $0.interface.localizedStandardCompare($1.interface) == .orderedAscending }
    }
}
