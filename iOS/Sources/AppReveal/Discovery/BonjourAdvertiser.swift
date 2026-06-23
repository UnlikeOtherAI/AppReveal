// Bonjour/mDNS service advertising for AppReveal.

import Foundation

#if DEBUG

@MainActor
final class BonjourAdvertiser {

    private var service: NetService?
    private var delegate: Delegate?
    private let port: UInt16

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        guard service == nil else { return }

        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let nextService = NetService(
            domain: "local.",
            type: "_appreveal._tcp.",
            name: "AppReveal-\(bundleId)",
            port: Int32(port)
        )
        let nextDelegate = Delegate(port: port)
        nextService.delegate = nextDelegate
        nextService.setTXTRecord(NetService.data(fromTXTRecord: [
            "bundleId": Data(bundleId.utf8),
            "version": Data(version.utf8),
            "transport": Data("streamable-http".utf8),
            "auth": Data("session-token".utf8)
        ]))

        service = nextService
        delegate = nextDelegate
        nextService.publish()
    }

    func stop() {
        service?.stop()
        service = nil
        delegate = nil
    }

    private final class Delegate: NSObject, NetServiceDelegate {
        private let port: UInt16

        init(port: UInt16) {
            self.port = port
        }

        func netServiceDidPublish(_ sender: NetService) {
            print("[AppReveal] Bonjour advertising as _appreveal._tcp on port \(port)")
        }

        func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
            print("[AppReveal] Bonjour advertising failed: \(errorDict)")
            print("[AppReveal] The MCP server can still be reached by direct host/port if the listener is running.")
        }
    }
}

#endif
