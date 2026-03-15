// MCP JSON-RPC message types

import Foundation

#if DEBUG

struct MCPRequest: Codable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: [String: AnyCodable]?

    enum RequestID: Codable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intVal = try? container.decode(Int.self) {
                self = .int(intVal)
            } else {
                self = .string(try container.decode(String.self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            }
        }
    }
}

struct MCPResponse: Codable {
    let jsonrpc: String
    let id: MCPRequest.RequestID?
    let result: AnyCodable?
    let error: MCPError?

    init(id: MCPRequest.RequestID?, result: AnyCodable) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: MCPRequest.RequestID?, error: MCPError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

struct MCPError: Codable {
    let code: Int
    let message: String
    let data: AnyCodable?

    static func methodNotFound(_ method: String) -> MCPError {
        MCPError(code: -32601, message: "Method not found: \(method)", data: nil)
    }

    static func invalidParams(_ detail: String) -> MCPError {
        MCPError(code: -32602, message: "Invalid params: \(detail)", data: nil)
    }

    static func internalError(_ detail: String) -> MCPError {
        MCPError(code: -32603, message: detail, data: nil)
    }
}

#endif
