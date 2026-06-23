// Embedded HTTP server for MCP Streamable HTTP transport.

import Foundation
import Network

@MainActor
final class MCPServer {

    private static let sessionTokenHeaderName = "x-appreveal-session"
    private static let sessionTokenQueryName = "appreveal_session_token"

    private var listener: NWListener?
    private var bonjourService: NetService?
    private var bonjourDelegate: BonjourDelegate?
    private var bonjourStatus = "not_started"
    private let requestedPort: UInt16?
    private let sessionTokenValue: String
    private(set) var actualPort: UInt16 = 0

    var sessionToken: String { sessionTokenValue }

    var url: String? {
        actualPort == 0 ? nil : "http://127.0.0.1:\(actualPort)/"
    }

    var sessionURL: String? {
        guard let url else { return nil }
        return "\(url)?\(Self.sessionTokenQueryName)=\(Self.percentEncode(sessionTokenValue))"
    }

    init(port: UInt16? = nil, sessionToken: String? = nil) {
        self.requestedPort = port
        self.sessionTokenValue = sessionToken?.isEmpty == false ? sessionToken! : Self.makeSessionToken()
    }

    func start() -> Bool {
        do {
            let port: NWEndpoint.Port = requestedPort.flatMap { NWEndpoint.Port(rawValue: $0) } ?? .any
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            print("[AppReveal] Failed to create listener: \(error)")
            return false
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        logBonjourConfigurationHints()

        let nwListener = listener
        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = nwListener?.port?.rawValue {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        actualPort = port
                        print("[AppReveal] MCP server listening on port \(port)")
                        print("[AppReveal] Session URL: http://127.0.0.1:\(port)/?\(Self.sessionTokenQueryName)=\(Self.percentEncode(sessionTokenValue))")
                        print("[AppReveal] Clients must include Authorization: Bearer <token> or X-AppReveal-Session.")
                        publishBonjour(port: port, bundleId: bundleId, version: version)
                    }
                }
            case .failed(let error):
                print("[AppReveal] Server failed: \(error)")
                print("[AppReveal] If loopback works but LAN fails, verify Local Network permission, NSLocalNetworkUsageDescription, NSBonjourServices, and firewall/VPN state.")
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
        return true
    }

    func stop() {
        bonjourService?.stop()
        bonjourService = nil
        bonjourDelegate = nil
        bonjourStatus = "stopped"
        listener?.cancel()
        listener = nil
        actualPort = 0
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveHTTPRequest(on: connection)
    }

    private func receiveHTTPRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
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
        guard let request = Self.parseHTTPRequest(data) else {
            sendHTTPResponse(connection: connection, status: 400, body: Data())
            return
        }

        let corsOrigin: String?
        switch Self.corsOriginPolicy(for: request) {
        case .absent:
            corsOrigin = nil
        case .allowed(let origin):
            corsOrigin = origin
        case .forbidden:
            sendHTTPResponse(connection: connection, status: 403, body: Data(), corsOrigin: nil)
            return
        }

        if request.method == "OPTIONS" {
            sendHTTPResponse(connection: connection, status: 204, body: Data(), corsOrigin: corsOrigin)
            return
        }

        if request.method == "GET", Self.pathWithoutQuery(request.path) == "/health" {
            sendJSONBody(
                [
                    "status": "ok",
                    "port": Int(actualPort),
                    "auth": "session-token",
                    "bonjour": bonjourStatus
                ],
                status: 200,
                connection: connection,
                corsOrigin: corsOrigin
            )
            return
        }

        guard request.method == "POST" else {
            sendHTTPResponse(connection: connection, status: 405, body: Data(), corsOrigin: corsOrigin)
            return
        }

        guard Self.isAuthorized(request, expectedToken: sessionTokenValue) else {
            let response = MCPResponse(id: nil, error: .internalError("Unauthorized"))
            sendJSONResponse(response, status: 401, connection: connection, corsOrigin: corsOrigin)
            return
        }

        let response: MCPResponse
        do {
            let json = try JSONSerialization.jsonObject(with: request.body, options: [])
            guard let object = json as? [String: Any] else {
                response = MCPResponse(id: nil, error: .invalidRequest("JSON-RPC payload must be an object"))
                sendJSONResponse(response, status: 400, connection: connection, corsOrigin: corsOrigin)
                return
            }

            guard object["jsonrpc"] as? String == "2.0" else {
                response = MCPResponse(id: nil, error: .invalidRequest("jsonrpc must be \"2.0\""))
                sendJSONResponse(response, status: 400, connection: connection, corsOrigin: corsOrigin)
                return
            }

            guard object["method"] is String else {
                response = MCPResponse(id: nil, error: .invalidRequest("method is required"))
                sendJSONResponse(response, status: 400, connection: connection, corsOrigin: corsOrigin)
                return
            }

            let request = try JSONDecoder().decode(MCPRequest.self, from: request.body)
            response = await MCPRouter.shared.handle(request)

            if request.id == nil {
                sendHTTPResponse(connection: connection, status: 204, body: Data(), corsOrigin: corsOrigin)
                return
            }
        } catch {
            response = MCPResponse(id: nil, error: .parseError(error.localizedDescription))
            sendJSONResponse(response, status: 400, connection: connection, corsOrigin: corsOrigin)
            return
        }

        sendJSONResponse(response, status: 200, connection: connection, corsOrigin: corsOrigin)
    }

    private func sendJSONResponse(_ response: MCPResponse, status: Int, connection: NWConnection, corsOrigin: String?) {
        guard let responseData = try? JSONEncoder().encode(response) else {
            sendHTTPResponse(connection: connection, status: 500, body: Data(), corsOrigin: corsOrigin)
            return
        }

        sendHTTPResponse(connection: connection, status: status, body: responseData, corsOrigin: corsOrigin)
    }

    private func sendJSONBody(_ body: [String: Any], status: Int, connection: NWConnection, corsOrigin: String?) {
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            sendHTTPResponse(connection: connection, status: 500, body: Data(), corsOrigin: corsOrigin)
            return
        }

        sendHTTPResponse(connection: connection, status: status, body: data, corsOrigin: corsOrigin)
    }

    private func sendHTTPResponse(connection: NWConnection, status: Int, body: Data, corsOrigin: String? = nil) {
        let statusText: String
        switch status {
        case 204: statusText = "No Content"
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 401: statusText = "Unauthorized"
        case 403: statusText = "Forbidden"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        var header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if let corsOrigin {
            header += "Access-Control-Allow-Origin: \(corsOrigin)\r\n"
            header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            header += "Access-Control-Allow-Headers: Authorization, Content-Type, X-AppReveal-Session\r\n"
            header += "Vary: Origin\r\n"
        }
        header += "\r\n"
        var responseData = Data(header.utf8)
        responseData.append(body)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: [String]]
        let body: Data
    }

    private enum CorsOrigin {
        case absent
        case allowed(String)
        case forbidden
    }

    private static func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8),
              let headerRange = raw.range(of: "\r\n\r\n") else {
            return nil
        }

        let headerText = String(raw[..<headerRange.lowerBound])
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count == 3, requestParts[2].hasPrefix("HTTP/") else { return nil }

        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            headers[name, default: []].append(value)
        }

        let bodyString = String(raw[headerRange.upperBound...])
        return HTTPRequest(
            method: requestParts[0],
            path: requestParts[1],
            headers: headers,
            body: Data(bodyString.utf8)
        )
    }

    private static func corsOriginPolicy(for request: HTTPRequest) -> CorsOrigin {
        let origins = request.headers["origin"]?.filter { !$0.isEmpty } ?? []
        guard let origin = origins.first else { return .absent }
        guard origins.count == 1 else { return .forbidden }
        return isLoopbackOrigin(origin) ? .allowed(origin) : .forbidden
    }

    private static func isAuthorized(_ request: HTTPRequest, expectedToken: String) -> Bool {
        request.headers[sessionTokenHeaderName]?.contains(where: { constantTimeEquals($0, expectedToken) }) == true
            || request.headers["authorization"]?.compactMap(readBearerToken).contains(where: { constantTimeEquals($0, expectedToken) }) == true
            || queryValue(in: request.path, named: sessionTokenQueryName).map { constantTimeEquals($0, expectedToken) } == true
    }

    private static func readBearerToken(_ value: String) -> String? {
        let prefix = "Bearer "
        guard value.count > prefix.count,
              value.lowercased().hasPrefix(prefix.lowercased()) else {
            return nil
        }

        return String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func queryValue(in path: String, named name: String) -> String? {
        guard let query = path.split(separator: "?", maxSplits: 1).dropFirst().first else {
            return nil
        }

        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = percentDecode(parts[0])
            let value = parts.count > 1 ? percentDecode(parts[1]) : ""
            if key == name {
                return value
            }
        }

        return nil
    }

    private static func pathWithoutQuery(_ path: String) -> String {
        path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
    }

    private static func isLoopbackOrigin(_ origin: String) -> Bool {
        guard origin.rangeOfCharacter(from: .newlines) == nil,
              let url = URL(string: origin),
              let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased(),
              url.scheme == "http" || url.scheme == "https" else {
            return false
        }

        return host == "localhost"
            || host.hasSuffix(".localhost")
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasPrefix("127.")
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        return zip(lhsBytes, rhsBytes).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func makeSessionToken() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: UInt8.min ... UInt8.max, using: &generator) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private static func percentDecode(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    private func publishBonjour(port: UInt16, bundleId: String, version: String) {
        guard bonjourService == nil else { return }

        let service = NetService(domain: "local.", type: "_appreveal._tcp.", name: "AppReveal-\(bundleId)", port: Int32(port))
        let delegate = BonjourDelegate(server: self)
        service.delegate = delegate
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "bundleId": Data(bundleId.utf8),
            "version": Data(version.utf8),
            "transport": Data("streamable-http".utf8),
            "auth": Data("session-token".utf8)
        ]))

        bonjourStatus = "publishing"
        bonjourDelegate = delegate
        bonjourService = service
        service.publish()
    }

    private func logBonjourConfigurationHints() {
        let info = Bundle.main.infoDictionary ?? [:]
        if info["NSLocalNetworkUsageDescription"] == nil {
            print("[AppReveal] Warning: NSLocalNetworkUsageDescription is missing. Physical devices and LAN clients may not see _appreveal._tcp.")
        }

        let bonjourServices = info["NSBonjourServices"] as? [String] ?? []
        let hasAppRevealService = bonjourServices.contains("_appreveal._tcp")
            || bonjourServices.contains("_appreveal._tcp.")
        if !hasAppRevealService {
            print("[AppReveal] Warning: NSBonjourServices should include _appreveal._tcp for Bonjour discovery.")
        }
    }

    private func markBonjourReady() {
        bonjourStatus = "advertising"
        print("[AppReveal] Bonjour advertising as _appreveal._tcp")
    }

    private func markBonjourFailed(_ errorDict: [String: NSNumber]) {
        bonjourStatus = "failed"
        print("[AppReveal] Bonjour advertising failed: \(errorDict)")
        print("[AppReveal] The MCP server remains available on loopback. Check Local Network permission, NSBonjourServices, and firewall/VPN state.")
    }

    private final class BonjourDelegate: NSObject, NetServiceDelegate {
        weak var server: MCPServer?

        init(server: MCPServer) {
            self.server = server
        }

        func netServiceDidPublish(_ sender: NetService) {
            Task { @MainActor [weak server] in
                server?.markBonjourReady()
            }
        }

        func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
            Task { @MainActor [weak server] in
                server?.markBonjourFailed(errorDict)
            }
        }
    }
}
