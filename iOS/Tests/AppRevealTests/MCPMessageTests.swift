// Tests for MCP message serialization

import XCTest
@testable import AppReveal

#if DEBUG

final class MCPMessageTests: XCTestCase {

    func testDecodeRequestWithIntId() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"tools/list","params":null}
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(MCPRequest.self, from: data)

        XCTAssertEqual(request.method, "tools/list")
        if case .int(let id) = request.id {
            XCTAssertEqual(id, 1)
        } else {
            XCTFail("Expected int ID")
        }
    }

    func testDecodeRequestWithStringId() throws {
        let json = """
        {"jsonrpc":"2.0","id":"abc-123","method":"tools/call","params":{"name":"get_screen"}}
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(MCPRequest.self, from: data)

        XCTAssertEqual(request.method, "tools/call")
        if case .string(let id) = request.id {
            XCTAssertEqual(id, "abc-123")
        } else {
            XCTFail("Expected string ID")
        }
    }

    func testEncodeResponse() throws {
        let response = MCPResponse(id: .int(1), result: AnyCodable(["status": "ok"]))
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("\"jsonrpc\":\"2.0\""))
        XCTAssertTrue(json.contains("\"status\""))
    }

    func testEncodeErrorResponse() throws {
        let response = MCPResponse(id: .int(2), error: .methodNotFound("unknown_tool"))
        let data = try JSONEncoder().encode(response)
        let json = String(data: data, encoding: .utf8)!

        XCTAssertTrue(json.contains("-32601"))
        XCTAssertTrue(json.contains("unknown_tool"))
    }
}

#endif
