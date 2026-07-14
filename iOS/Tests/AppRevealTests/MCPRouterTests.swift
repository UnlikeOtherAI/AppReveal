import XCTest
@testable import AppReveal

#if DEBUG

@MainActor
final class MCPRouterTests: XCTestCase {

    func testImageToolReturnsMCPImageBlockAndMetadata() async throws {
        let imageData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"
        let toolName = "test_image_result"
        MCPRouter.shared.register(MCPToolDefinition(
            name: toolName,
            description: "Test image",
            inputSchema: emptySchema,
            outputKind: .image,
            handler: { _ in
                AnyCodable([
                    "image": imageData,
                    "width": 120,
                    "height": 240,
                    "scale": 2.0,
                    "format": "png"
                ] as [String: Any])
            }
        ))

        let response = await MCPRouter.shared.handle(toolRequest(name: toolName))
        let result = try resultObject(from: response)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])

        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "image")
        XCTAssertEqual(content[0]["data"] as? String, imageData)
        XCTAssertEqual(content[0]["mimeType"] as? String, "image/png")
        XCTAssertEqual(content[1]["type"] as? String, "text")

        let metadataText = try XCTUnwrap(content[1]["text"] as? String)
        XCTAssertFalse(metadataText.contains(imageData))
        let metadataData = try XCTUnwrap(metadataText.data(using: .utf8))
        let metadataFromText = try XCTUnwrap(
            JSONSerialization.jsonObject(with: metadataData) as? [String: Any]
        )
        XCTAssertEqual(metadataFromText["width"] as? Int, 120)
        XCTAssertEqual(metadataFromText["format"] as? String, "png")
        XCTAssertNil(metadataFromText["image"])

        let structuredContent = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual(structuredContent["height"] as? Int, 240)
        XCTAssertEqual(structuredContent["scale"] as? Double, 2.0)
        XCTAssertNil(structuredContent["image"])
        XCTAssertNil(result["isError"])
    }

    func testImageToolMapsJPEGMimeType() async throws {
        let toolName = "test_jpeg_result"
        MCPRouter.shared.register(MCPToolDefinition(
            name: toolName,
            description: "Test JPEG",
            inputSchema: emptySchema,
            outputKind: .image,
            handler: { _ in
                AnyCodable([
                    "image": "/9j/4AAQSkZJRgABAQAAAQABAAD",
                    "width": 20,
                    "height": 10,
                    "scale": 1.0,
                    "format": "jpeg"
                ] as [String: Any])
            }
        ))

        let response = await MCPRouter.shared.handle(toolRequest(name: toolName))
        let result = try resultObject(from: response)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])

        XCTAssertEqual(content[0]["mimeType"] as? String, "image/jpeg")
    }

    func testImageToolFailureReturnsTextError() async throws {
        let toolName = "test_image_failure"
        MCPRouter.shared.register(MCPToolDefinition(
            name: toolName,
            description: "Test image failure",
            inputSchema: emptySchema,
            outputKind: .image,
            handler: { _ in
                AnyCodable(["error": "Capture failed"])
            }
        ))

        let response = await MCPRouter.shared.handle(toolRequest(name: toolName))
        let result = try resultObject(from: response)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])

        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertTrue((content[0]["text"] as? String)?.contains("Capture failed") == true)
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertNil(result["structuredContent"])
    }

    func testJSONToolKeepsTextResultShape() async throws {
        let toolName = "test_json_result"
        MCPRouter.shared.register(MCPToolDefinition(
            name: toolName,
            description: "Test JSON",
            inputSchema: emptySchema,
            handler: { _ in
                AnyCodable(["value": "ok"])
            }
        ))

        let response = await MCPRouter.shared.handle(toolRequest(name: toolName))
        let result = try resultObject(from: response)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])

        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "{\"value\":\"ok\"}")
        XCTAssertNil(result["structuredContent"])
    }

    private var emptySchema: [String: AnyCodable] {
        [
            "type": AnyCodable("object"),
            "properties": AnyCodable([String: Any]())
        ]
    }

    private func toolRequest(name: String) -> MCPRequest {
        MCPRequest(
            jsonrpc: "2.0",
            id: .int(1),
            method: "tools/call",
            params: [
                "name": AnyCodable(name),
                "arguments": AnyCodable([String: Any]())
            ]
        )
    }

    private func resultObject(from response: MCPResponse) throws -> [String: Any] {
        let data = try JSONEncoder().encode(response)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["result"] as? [String: Any])
    }
}

#endif
