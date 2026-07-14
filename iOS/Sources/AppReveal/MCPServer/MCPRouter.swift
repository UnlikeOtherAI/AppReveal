// MCP tool registration and dispatch

import Foundation

#if DEBUG

typealias MCPToolHandler = @MainActor (
    _ params: [String: AnyCodable]?
) async throws -> AnyCodable

enum MCPToolOutputKind {
    case jsonText
    case image
}

struct MCPToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]
    let outputKind: MCPToolOutputKind
    let handler: MCPToolHandler

    init(
        name: String,
        description: String,
        inputSchema: [String: AnyCodable],
        outputKind: MCPToolOutputKind = .jsonText,
        handler: @escaping MCPToolHandler
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputKind = outputKind
        self.handler = handler
    }
}

@MainActor
final class MCPRouter {

    static let shared = MCPRouter()

    private var tools: [String: MCPToolDefinition] = [:]

    private init() {}

    func register(_ tool: MCPToolDefinition) {
        tools[tool.name] = tool
    }

    func tool(named name: String) -> MCPToolDefinition? {
        tools[name]
    }

    func handle(_ request: MCPRequest) async -> MCPResponse {
        switch request.method {
        case "initialize":
            return MCPResponse(id: request.id, result: AnyCodable([
                "protocolVersion": "2025-06-18",
                "capabilities": [
                    "tools": [:]
                ],
                "serverInfo": [
                    "name": "AppReveal",
                    "version": AppRevealVersion.current
                ]
            ] as [String: Any]))

        case "tools/list":
            let toolList: [[String: Any]] = tools.values.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema.mapValues(\.value)
                ]
            }
            return MCPResponse(id: request.id, result: AnyCodable(["tools": toolList]))

        case "tools/call":
            guard let params = request.params,
                  let toolName = params["name"]?.stringValue else {
                return MCPResponse(id: request.id, error: .invalidParams("Missing tool name"))
            }

            guard let tool = tools[toolName] else {
                return MCPResponse(id: request.id, error: .methodNotFound(toolName))
            }

            do {
                let arguments = params["arguments"]?.dictionaryValue
                let result = try await tool.handler(arguments)
                return MCPResponse(
                    id: request.id,
                    result: try makeToolCallResult(result, outputKind: tool.outputKind)
                )
            } catch {
                return MCPResponse(id: request.id, error: .internalError(error.localizedDescription))
            }

        default:
            return MCPResponse(id: request.id, error: .methodNotFound(request.method))
        }
    }

    private func makeToolCallResult(
        _ result: AnyCodable,
        outputKind: MCPToolOutputKind
    ) throws -> AnyCodable {
        switch outputKind {
        case .jsonText:
            return try makeTextToolCallResult(result)
        case .image:
            return try makeImageToolCallResult(result)
        }
    }

    private func makeTextToolCallResult(
        _ result: AnyCodable,
        isError: Bool = false
    ) throws -> AnyCodable {
        var payload: [String: Any] = [
            "content": [
                ["type": "text", "text": try jsonString(for: result)]
            ]
        ]
        if isError {
            payload["isError"] = true
        }
        return AnyCodable(payload)
    }

    private func makeImageToolCallResult(_ result: AnyCodable) throws -> AnyCodable {
        guard let payload = result.dictionaryValue else {
            return try makeTextToolCallResult(
                AnyCodable(["error": "Screenshot returned an invalid result"]),
                isError: true
            )
        }

        if payload["error"] != nil {
            return try makeTextToolCallResult(result, isError: true)
        }

        guard let imageData = payload["image"]?.stringValue,
              !imageData.isEmpty,
              let format = payload["format"]?.stringValue,
              format == "png" || format == "jpeg" else {
            return try makeTextToolCallResult(
                AnyCodable(["error": "Screenshot returned invalid image data or format"]),
                isError: true
            )
        }

        let metadata = payload
            .filter { $0.key != "image" }
            .mapValues(\.value)
        let mimeType = format == "jpeg" ? "image/jpeg" : "image/png"

        return AnyCodable([
            "content": [
                [
                    "type": "image",
                    "data": imageData,
                    "mimeType": mimeType
                ],
                [
                    "type": "text",
                    "text": try jsonString(for: AnyCodable(metadata))
                ]
            ],
            "structuredContent": metadata
        ] as [String: Any])
    }

    private func jsonString(for value: AnyCodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

#endif
