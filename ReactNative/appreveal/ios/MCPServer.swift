// Embedded HTTP server for MCP Streamable HTTP transport

import Foundation
import Network

@MainActor
final class MCPServer {

    private var listener: NWListener?
    private let requestedPort: UInt16?
    private(set) var actualPort: UInt16 = 0

    init(port: UInt16? = nil) {
        self.requestedPort = port
    }

    func start() {
        do {
            let port: NWEndpoint.Port = requestedPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            print("[AppReveal] Failed to create listener: \(error)")
            return
        }

        // Attach Bonjour service directly to this listener so the
        // advertised port matches the actual MCP server port.
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        listener?.service = NWListener.Service(
            name: "AppReveal-\(bundleId)",
            type: "_appreveal._tcp",
            txtRecord: NWTXTRecord([
                "bundleId": bundleId,
                "version": version,
                "transport": "streamable-http"
            ])
        )

        let nwListener = listener
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = nwListener?.port?.rawValue {
                    Task { @MainActor in
                        self?.actualPort = port
                    }
                    print("[AppReveal] MCP server listening on port \(port)")
                    print("[AppReveal] Bonjour advertising as _appreveal._tcp")
                }
            case .failed(let error):
                print("[AppReveal] Server failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let data = data, !data.isEmpty else {
                    connection.cancel()
                    return
                }

                await self?.processHTTPData(data, on: connection)

                if !isComplete {
                    self?.receiveHTTPRequest(on: connection)
                }
            }
        }
    }

    private func processHTTPData(_ data: Data, on connection: NWConnection) async {
        // Parse HTTP request body (simplified: extract JSON body after headers)
        guard let raw = String(data: data, encoding: .utf8),
              let bodyRange = raw.range(of: "\r\n\r\n") else {
            sendHTTPResponse(connection: connection, status: 400, body: Data())
            return
        }

        let bodyString = String(raw[bodyRange.upperBound...])
        guard let bodyData = bodyString.data(using: .utf8),
              let request = try? JSONDecoder().decode(MCPRequest.self, from: bodyData) else {
            sendHTTPResponse(connection: connection, status: 400, body: Data())
            return
        }

        let response = await MCPRouter.shared.handle(request)

        guard let responseData = try? JSONEncoder().encode(response) else {
            sendHTTPResponse(connection: connection, status: 500, body: Data())
            return
        }

        sendHTTPResponse(connection: connection, status: 200, body: responseData)
    }

    private func sendHTTPResponse(connection: NWConnection, status: Int, body: Data) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
