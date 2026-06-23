// Embedded HTTP server for MCP Streamable HTTP transport

import Foundation
import Network

#if DEBUG

@MainActor
final class MCPServer {

    private static let sessionTokenHeaderName = "x-appreveal-session"
    private static let sessionTokenQueryName = "appreveal_session_token"
    private static let maxBonjourRetryAttempts = 5

    private var listener: NWListener?
    private var bonjourService: NetService?
    private var bonjourDelegate: BonjourDelegate?
    private var bonjourRetryTask: Task<Void, Never>?
    private var bonjourStatus = "not_started"
    private var bonjourRetryAttempt = 0
    private var bonjourSuppressionReason: String?
    private var bonjourRetryDelaySeconds: Int?
    private var lastBonjourError: [String: NSNumber]?
    private var pendingBonjourPublication: BonjourPublication?
    private var networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "ai.unlikeother.appreveal.network-monitor")
    private var networkPathStatus = "unknown"
    private var networkPathInterfaces: [String] = []
    private var lanInterfaces: [AppRevealLANInterface] = []
    private var lanWarnings: [String] = []
    private let requestedPort: UInt16?
    private let sessionTokenValue: String
    private(set) var actualPort: UInt16 = 0

    private struct BonjourPublication {
        let port: UInt16
        let bundleId: String
        let version: String
    }

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
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            listener = try NWListener(using: parameters, on: port)
        } catch {
            print("[AppReveal] Failed to create listener: \(error)")
            return false
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        refreshLANDiagnostics()
        startNetworkPathMonitor()
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
                        print("[AppReveal] LAN clients must include the session token with Authorization: Bearer <token> or X-AppReveal-Session.")
                        publishBonjour(port: port, bundleId: bundleId, version: version)
                    }
                }
            case .failed(let error):
                print("[AppReveal] Server failed: \(error)")
                print("[AppReveal] If loopback works but LAN fails, verify Local Network permission, NSLocalNetworkUsageDescription, NSBonjourServices, firewall, and sandbox network.server entitlement where applicable.")
                Task { @MainActor [weak self] in
                    self?.actualPort = 0
                }
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
        bonjourRetryTask?.cancel()
        bonjourRetryTask = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        bonjourService?.stop()
        bonjourService = nil
        bonjourDelegate = nil
        bonjourStatus = "stopped"
        bonjourSuppressionReason = nil
        bonjourRetryDelaySeconds = nil
        pendingBonjourPublication = nil
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
            refreshLANDiagnostics()
            sendJSONBody(
                [
                    "status": "ok",
                    "port": Int(actualPort),
                    "auth": "session-token",
                    "bonjour": bonjourStatus,
                    "bonjourDiagnostics": bonjourDiagnosticsPayload(),
                    "lan": lanDiagnosticsPayload()
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
            sendJSONResponse(
                MCPResponse(id: nil, error: .internalError("Unauthorized")),
                status: 401,
                connection: connection,
                corsOrigin: corsOrigin
            )
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
        pendingBonjourPublication = BonjourPublication(port: port, bundleId: bundleId, version: version)
        guard bonjourService == nil else { return }

        refreshLANDiagnostics()
        guard AppRevealLANDiagnostics.hasUsableLANAddress(lanInterfaces) else {
            suppressBonjour(reason: "no_lan_interface")
            return
        }

        if networkPathStatus == "unsatisfied" {
            suppressBonjour(reason: "network_path_unsatisfied")
            return
        }

        let name = "AppReveal-\(bundleId)"
        let service = NetService(domain: "local.", type: "_appreveal._tcp.", name: name, port: Int32(port))
        let delegate = BonjourDelegate(server: self)
        service.delegate = delegate
        service.includesPeerToPeer = true
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "bundleId": Data(bundleId.utf8),
            "version": Data(version.utf8),
            "transport": Data("streamable-http".utf8),
            "auth": Data("session-token".utf8),
            "lan": Data("available".utf8)
        ]))

        bonjourSuppressionReason = nil
        bonjourRetryDelaySeconds = nil
        bonjourStatus = "publishing"
        bonjourDelegate = delegate
        bonjourService = service
        service.publish()
    }

    private func logBonjourConfigurationHints() {
        for warning in lanWarnings {
            print("[AppReveal] Warning: \(warning)")
        }
    }

    private func markBonjourReady() {
        bonjourStatus = "advertising"
        bonjourRetryAttempt = 0
        bonjourRetryDelaySeconds = nil
        bonjourSuppressionReason = nil
        lastBonjourError = nil
        print("[AppReveal] Bonjour advertising as _appreveal._tcp")
    }

    private func markBonjourFailed(_ errorDict: [String: NSNumber]) {
        lastBonjourError = errorDict
        bonjourService?.stop()
        bonjourService = nil
        bonjourDelegate = nil
        print("[AppReveal] Bonjour advertising failed: \(errorDict)")
        if Self.isBonjourNoAuth(errorDict) {
            print("[AppReveal] Bonjour failed with NoAuth. Check Local Network permission and NSBonjourServices for _appreveal._tcp.")
        }
        print("[AppReveal] The MCP server remains available on loopback. Check /health for LAN diagnostics.")
        scheduleBonjourRetry(reason: "publish_failed")
    }

    private func suppressBonjour(reason: String) {
        bonjourService?.stop()
        bonjourService = nil
        bonjourDelegate = nil
        bonjourStatus = "suppressed"
        bonjourSuppressionReason = reason
        print("[AppReveal] Bonjour suppressed (\(reason)); MCP loopback remains available at \(sessionURL ?? url ?? "starting").")
        scheduleBonjourRetry(reason: reason)
    }

    private func scheduleBonjourRetry(reason: String) {
        guard let publication = pendingBonjourPublication else { return }
        guard bonjourRetryAttempt < Self.maxBonjourRetryAttempts else {
            bonjourStatus = reason == "publish_failed" ? "failed" : "suppressed"
            bonjourRetryDelaySeconds = nil
            print("[AppReveal] Bonjour retry limit reached. Check /health before trying LAN discovery again.")
            return
        }

        bonjourRetryTask?.cancel()
        bonjourRetryAttempt += 1
        let delay = Self.retryDelaySeconds(for: bonjourRetryAttempt)
        bonjourRetryDelaySeconds = delay
        if reason == "publish_failed" {
            bonjourStatus = "retrying"
        }
        print("[AppReveal] Bonjour retry \(bonjourRetryAttempt)/\(Self.maxBonjourRetryAttempts) scheduled in \(delay)s (\(reason)).")

        bonjourRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            } catch {
                return
            }
            guard let self, self.listener != nil else { return }
            self.bonjourRetryTask = nil
            self.bonjourRetryDelaySeconds = nil
            self.publishBonjour(port: publication.port, bundleId: publication.bundleId, version: publication.version)
        }
    }

    private func retryBonjourNow(reason: String) {
        guard let publication = pendingBonjourPublication, bonjourService == nil else { return }
        bonjourRetryTask?.cancel()
        bonjourRetryTask = nil
        bonjourRetryDelaySeconds = nil
        print("[AppReveal] Retrying Bonjour now (\(reason)).")
        publishBonjour(port: publication.port, bundleId: publication.bundleId, version: publication.version)
    }

    private func refreshLANDiagnostics() {
        lanInterfaces = AppRevealLANDiagnostics.currentInterfaces()
        lanWarnings = AppRevealLANDiagnostics.warnings(
            info: Bundle.main.infoDictionary ?? [:],
            interfaces: lanInterfaces,
            pathStatus: networkPathStatus
        )
    }

    private func startNetworkPathMonitor() {
        guard networkMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let status = Self.describePathStatus(path.status)
            let interfaces = Self.describeInterfaceTypes(path.availableInterfaces.map(\.type))
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.networkPathStatus = status
                self.networkPathInterfaces = interfaces
                self.refreshLANDiagnostics()
                if status == "satisfied",
                   self.bonjourService == nil,
                   self.pendingBonjourPublication != nil,
                   self.bonjourStatus == "suppressed" || self.bonjourStatus == "retrying" {
                    self.retryBonjourNow(reason: "network_path_satisfied")
                }
            }
        }
        networkMonitor = monitor
        monitor.start(queue: networkMonitorQueue)
    }

    private func bonjourDiagnosticsPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "status": bonjourStatus,
            "retryAttempt": bonjourRetryAttempt,
            "maxRetryAttempts": Self.maxBonjourRetryAttempts
        ]
        if let bonjourRetryDelaySeconds {
            payload["nextRetrySeconds"] = bonjourRetryDelaySeconds
        }
        if let bonjourSuppressionReason {
            payload["suppressionReason"] = bonjourSuppressionReason
        }
        if let lastBonjourError {
            payload["lastError"] = Dictionary(
                uniqueKeysWithValues: lastBonjourError.map { ($0.key, $0.value.intValue) }
            )
            payload["lastErrorHint"] = Self.isBonjourNoAuth(lastBonjourError)
                ? "NoAuth: grant Local Network permission and declare _appreveal._tcp in NSBonjourServices."
                : "Bonjour publish failed; check Local Network, firewall/VPN, and sandbox network.server policy."
        }
        return payload
    }

    private func lanDiagnosticsPayload() -> [String: Any] {
        [
            "pathStatus": networkPathStatus,
            "pathInterfaces": networkPathInterfaces,
            "hasUsableLANAddress": AppRevealLANDiagnostics.hasUsableLANAddress(lanInterfaces),
            "interfaces": lanInterfaces.map(\.dictionary),
            "warnings": lanWarnings
        ]
    }

    private nonisolated static func retryDelaySeconds(for attempt: Int) -> Int {
        let delays = [2, 5, 10, 30, 60]
        return delays[min(max(attempt - 1, 0), delays.count - 1)]
    }

    private nonisolated static func isBonjourNoAuth(_ errorDict: [String: NSNumber]) -> Bool {
        errorDict.values.contains { $0.intValue == -65555 }
    }

    private nonisolated static func describePathStatus(_ status: NWPath.Status) -> String {
        switch status {
        case .satisfied: return "satisfied"
        case .unsatisfied: return "unsatisfied"
        case .requiresConnection: return "requires_connection"
        @unknown default: return "unknown"
        }
    }

    private nonisolated static func describeInterfaceTypes(_ types: [NWInterface.InterfaceType]) -> [String] {
        var result: [String] = []
        for type in types {
            let name: String
            switch type {
            case .wifi: name = "wifi"
            case .cellular: name = "cellular"
            case .wiredEthernet: name = "wired_ethernet"
            case .loopback: name = "loopback"
            case .other: name = "other"
            @unknown default: name = "unknown"
            }
            if !result.contains(name) {
                result.append(name)
            }
        }
        return result
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

#endif
