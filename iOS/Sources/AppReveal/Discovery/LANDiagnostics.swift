// Runtime LAN interface diagnostics used by Bonjour publishing and /health.

import Foundation

#if DEBUG
#if os(iOS) || os(macOS)

import Darwin

struct AppRevealLANInterface {
    let name: String
    let family: String
    let address: String
    let isLoopback: Bool
    let isPointToPoint: Bool
    let isLinkLocal: Bool

    var isLANReachableCandidate: Bool {
        !isLoopback && !isPointToPoint && !isLinkLocal
    }

    var dictionary: [String: Any] {
        [
            "name": name,
            "family": family,
            "address": address,
            "loopback": isLoopback,
            "pointToPoint": isPointToPoint,
            "linkLocal": isLinkLocal,
            "lanCandidate": isLANReachableCandidate
        ]
    }
}

enum AppRevealLANDiagnostics {
    static func currentInterfaces() -> [AppRevealLANInterface] {
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacesPointer) == 0, let first = interfacesPointer else {
            return []
        }
        defer { freeifaddrs(interfacesPointer) }

        var result: [AppRevealLANInterface] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr else { continue }

            let family = address.pointee.sa_family
            let familyName: String
            let addressLength: socklen_t
            switch Int32(family) {
            case AF_INET:
                familyName = "ipv4"
                addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            case AF_INET6:
                familyName = "ipv6"
                addressLength = socklen_t(MemoryLayout<sockaddr_in6>.size)
            default:
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address,
                addressLength,
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else {
                continue
            }

            let flags = current.pointee.ifa_flags
            let interfaceName = String(cString: current.pointee.ifa_name)
            let hostAddress = String(cString: host)
            let lowercasedAddress = hostAddress.lowercased()

            result.append(
                AppRevealLANInterface(
                    name: interfaceName,
                    family: familyName,
                    address: hostAddress,
                    isLoopback: (flags & UInt32(IFF_LOOPBACK)) != 0,
                    isPointToPoint: (flags & UInt32(IFF_POINTOPOINT)) != 0,
                    isLinkLocal: lowercasedAddress.hasPrefix("169.254.")
                        || lowercasedAddress.hasPrefix("fe80:")
                )
            )
        }

        return result.sorted { lhs, rhs in
            if lhs.name == rhs.name { return lhs.address < rhs.address }
            return lhs.name < rhs.name
        }
    }

    static func hasUsableLANAddress(_ interfaces: [AppRevealLANInterface]) -> Bool {
        interfaces.contains { $0.isLANReachableCandidate }
    }

    static func warnings(
        info: [String: Any],
        interfaces: [AppRevealLANInterface],
        pathStatus: String
    ) -> [String] {
        var warnings: [String] = []

        if info["NSLocalNetworkUsageDescription"] == nil {
            warnings.append("NSLocalNetworkUsageDescription is missing; Local Network permission may not be requested.")
        }

        let bonjourServices = info["NSBonjourServices"] as? [String] ?? []
        let hasAppRevealService = bonjourServices.contains("_appreveal._tcp")
            || bonjourServices.contains("_appreveal._tcp.")
        if !hasAppRevealService {
            warnings.append("NSBonjourServices should include _appreveal._tcp for Bonjour discovery.")
        }

        if !hasUsableLANAddress(interfaces) {
            warnings.append("No active non-loopback LAN address is visible to the process.")
        }

        if pathStatus == "unsatisfied" {
            warnings.append("Network.framework reports an unsatisfied path; LAN clients will not connect until the path is satisfied.")
        }

        #if os(macOS)
        warnings.append("macOS LAN reachability also depends on Local Network permission, firewall/VPN policy, and com.apple.security.network.server when sandboxed.")
        #endif

        return warnings
    }
}

#endif
#endif
