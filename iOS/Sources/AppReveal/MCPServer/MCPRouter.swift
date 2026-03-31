// MCP tool registration and dispatch

import Foundation

#if DEBUG

typealias MCPToolHandler = @MainActor (
    _ params: [String: AnyCodable]?
) async throws -> AnyCodable

struct MCPToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: AnyCodable]
    let handler: MCPToolHandler
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
                    "version": "0.6.0"
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
                let resultData = try JSONEncoder().encode(result)
                let resultString = String(data: resultData, encoding: .utf8) ?? "{}"
                return MCPResponse(id: request.id, result: AnyCodable([
                    "content": [
                        ["type": "text", "text": resultString]
                    ]
                ] as [String: Any]))
            } catch {
                return MCPResponse(id: request.id, error: .internalError(error.localizedDescription))
            }

        default:
            return MCPResponse(id: request.id, error: .methodNotFound(request.method))
        }
    }
}

#endif
