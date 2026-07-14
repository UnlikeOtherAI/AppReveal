import Darwin
import XCTest
@testable import AppReveal

#if os(macOS) && DEBUG

@MainActor
final class MCPServerNetworkTests: XCTestCase {
    func testHealthAndInitializeAuthenticationOverLoopback() async throws {
        let token = "network-test-session-token"
        let server = MCPServer(sessionToken: token)
        let session = URLSession(configuration: .ephemeral)

        XCTAssertTrue(server.start())
        defer {
            session.invalidateAndCancel()
            server.stop()
        }

        let port = try await waitForReadyPort(on: server)
        let baseURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/"))

        let health = try await send(
            URLRequest(url: baseURL.appendingPathComponent("health")),
            using: session
        )
        XCTAssertEqual(health.response.statusCode, 200)
        XCTAssertEqual(health.body["status"] as? String, "ok")
        XCTAssertEqual(health.body["port"] as? Int, Int(port))
        XCTAssertEqual(health.body["auth"] as? String, "session-token")
        XCTAssertNotNil(health.body["bonjourDiagnostics"] as? [String: Any])
        XCTAssertNotNil(health.body["lan"] as? [String: Any])

        let initializeBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-06-18",
                "capabilities": [:],
                "clientInfo": ["name": "AppRevealTests", "version": "1.0"]
            ]
        ])

        var unauthorizedRequest = URLRequest(url: baseURL)
        unauthorizedRequest.httpMethod = "POST"
        unauthorizedRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        unauthorizedRequest.httpBody = initializeBody

        let unauthorized = try await send(unauthorizedRequest, using: session)
        XCTAssertEqual(unauthorized.response.statusCode, 401)
        let unauthorizedError = try XCTUnwrap(unauthorized.body["error"] as? [String: Any])
        XCTAssertEqual(unauthorizedError["message"] as? String, "Unauthorized")

        var authorizedRequest = unauthorizedRequest
        authorizedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let authorized = try await send(authorizedRequest, using: session)
        XCTAssertEqual(authorized.response.statusCode, 200)
        XCTAssertEqual(authorized.body["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(authorized.body["id"] as? Int, 1)
        let result = try XCTUnwrap(authorized.body["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "AppReveal")
    }

    func testFragmentedInitializeWaitsForDeclaredContentLength() async throws {
        let token = "fragmented-network-test-token"
        let server = MCPServer(sessionToken: token)

        XCTAssertTrue(server.start())
        defer { server.stop() }

        let port = try await waitForReadyPort(on: server)
        let initializeBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "initialize",
            "params": [:]
        ])
        let response = try await sendRawRequest(
            port: port,
            headerFields: [
                "Authorization: Bearer \(token)",
                "Content-Type: application/json",
                "Content-Length: \(initializeBody.count)"
            ],
            body: initializeBody,
            delayBeforeBody: 100_000
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(response.body["id"] as? Int, 2)
        XCTAssertNotNil(response.body["result"] as? [String: Any])
    }

    func testOversizedDeclaredContentLengthReturnsPayloadTooLarge() async throws {
        let server = MCPServer(sessionToken: "oversized-request-test-token")

        XCTAssertTrue(server.start())
        defer { server.stop() }

        let port = try await waitForReadyPort(on: server)
        let response = try await sendRawRequest(
            port: port,
            headerFields: ["Content-Length: 1048577"]
        )

        XCTAssertEqual(response.statusCode, 413)
        XCTAssertTrue(response.body.isEmpty)
    }

    func testRejectsConflictingAndInvalidContentLength() async throws {
        let server = MCPServer(sessionToken: "invalid-length-test-token")

        XCTAssertTrue(server.start())
        defer { server.stop() }

        let port = try await waitForReadyPort(on: server)
        let invalidHeaderSets = [
            ["Content-Length: 1", "Content-Length: 2"],
            ["Content-Length: not-a-number"]
        ]

        for headerFields in invalidHeaderSets {
            let response = try await sendRawRequest(
                port: port,
                headerFields: headerFields
            )
            XCTAssertEqual(
                response.statusCode,
                400,
                "Expected HTTP 400 for headers: \(headerFields)"
            )
            XCTAssertTrue(response.body.isEmpty)
        }
    }

    func testRejectsUnsupportedTransferEncoding() async throws {
        let server = MCPServer(sessionToken: "transfer-encoding-test-token")

        XCTAssertTrue(server.start())
        defer { server.stop() }

        let port = try await waitForReadyPort(on: server)
        let response = try await sendRawRequest(
            port: port,
            headerFields: ["Transfer-Encoding: chunked"]
        )

        XCTAssertEqual(response.statusCode, 400)
        XCTAssertTrue(response.body.isEmpty)
    }

    private func waitForReadyPort(on server: MCPServer) async throws -> UInt16 {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))

        while clock.now < deadline {
            if server.actualPort != 0 {
                return server.actualPort
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTFail("MCPServer did not become ready within five seconds")
        throw ReadinessError.timedOut
    }

    private func send(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> (body: [String: Any], response: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (body, httpResponse)
    }

    private func sendRawRequest(
        port: UInt16,
        headerFields: [String],
        body: Data? = nil,
        delayBeforeBody: useconds_t = 0
    ) async throws -> (statusCode: Int, body: [String: Any]) {
        let rawResponse = try await Task.detached {
            try Self.exchangeRawRequest(
                port: port,
                headerFields: headerFields,
                body: body,
                delayBeforeBody: delayBeforeBody
            )
        }.value
        return try parseRawHTTPResponse(rawResponse)
    }

    private func parseRawHTTPResponse(
        _ data: Data
    ) throws -> (statusCode: Int, body: [String: Any]) {
        let separator = Data("\r\n\r\n".utf8)
        let headerRange = try XCTUnwrap(data.range(of: separator))
        let header = try XCTUnwrap(String(data: data[..<headerRange.lowerBound], encoding: .utf8))
        let statusLine = try XCTUnwrap(header.components(separatedBy: "\r\n").first)
        let statusParts = statusLine.split(separator: " ")
        guard statusParts.count >= 2 else { throw RawHTTPError.invalidStatusLine }
        let statusCode = try XCTUnwrap(Int(statusParts[1]))
        let bodyData = Data(data[headerRange.upperBound...])
        let body = bodyData.isEmpty
            ? [:]
            : try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        return (statusCode, body)
    }

    private nonisolated static func exchangeRawRequest(
        port: UInt16,
        headerFields: [String],
        body: Data?,
        delayBeforeBody: useconds_t
    ) throws -> Data {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw posixError() }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(
                    socketDescriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard connectResult == 0 else { throw posixError() }

        var headerLines = [
            "POST / HTTP/1.1",
            "Host: 127.0.0.1:\(port)"
        ]
        headerLines.append(contentsOf: headerFields)
        headerLines.append(contentsOf: ["Connection: close", "", ""])
        let header = headerLines.joined(separator: "\r\n")

        try sendAll(Data(header.utf8), to: socketDescriptor)
        if let body {
            if delayBeforeBody > 0 {
                usleep(delayBeforeBody)
            }
            try sendAll(body, to: socketDescriptor)
        }
        Darwin.shutdown(socketDescriptor, SHUT_WR)

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let received = Darwin.recv(socketDescriptor, &buffer, buffer.count, 0)
            if received > 0 {
                response.append(contentsOf: buffer.prefix(received))
            } else if received == 0 {
                return response
            } else if errno != EINTR {
                throw posixError()
            }
        }
    }

    private nonisolated static func sendAll(_ data: Data, to socketDescriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let result = Darwin.send(
                    socketDescriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                if result > 0 {
                    sent += result
                } else if result == 0 || errno != EINTR {
                    throw posixError()
                }
            }
        }
    }

    private nonisolated static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private enum ReadinessError: Error {
        case timedOut
    }

    private enum RawHTTPError: Error {
        case invalidStatusLine
    }
}

#endif
