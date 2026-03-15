// Bonjour/mDNS service advertising for AppReveal

import Foundation
import Network

#if DEBUG

@MainActor
final class BonjourAdvertiser {

    private var listener: NWListener?
    private let port: UInt16

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        let txtRecord = NWTXTRecord([
            "bundleId": bundleId,
            "version": version,
            "port": "\(port)",
            "transport": "streamable-http"
        ])

        let service = NWListener.Service(
            name: "AppReveal-\(bundleId)",
            type: "_appreveal._tcp",
            txtRecord: txtRecord
        )

        do {
            let nwPort = NWEndpoint.Port(rawValue: port) ?? .any
            listener = try NWListener(using: .tcp, on: nwPort)
            listener?.service = service

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[AppReveal] Bonjour advertising as _appreveal._tcp on port \(self.port)")
                case .failed(let error):
                    print("[AppReveal] Bonjour advertising failed: \(error)")
                default:
                    break
                }
            }

            // We don't need to accept connections on this listener;
            // it exists only for Bonjour advertisement.
            // The MCPServer listener handles actual connections.
            listener?.newConnectionHandler = { connection in
                connection.cancel()
            }

            listener?.start(queue: .main)
        } catch {
            print("[AppReveal] Failed to start Bonjour advertiser: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

#endif
