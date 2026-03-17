// Models for captured network traffic

import Foundation

public struct CapturedRequest: Codable {
    public let id: String
    public let method: String
    public let url: String
    public let statusCode: Int?
    public let startTime: Date
    public let endTime: Date?
    public let duration: TimeInterval?
    public let requestHeaders: [String: String]
    public let responseHeaders: [String: String]?
    public let requestBodySize: Int?
    public let responseBodySize: Int?
    public let error: String?
    public let redirectCount: Int

    public init(
        id: String = UUID().uuidString,
        method: String,
        url: String,
        statusCode: Int? = nil,
        startTime: Date = Date(),
        endTime: Date? = nil,
        duration: TimeInterval? = nil,
        requestHeaders: [String: String] = [:],
        responseHeaders: [String: String]? = nil,
        requestBodySize: Int? = nil,
        responseBodySize: Int? = nil,
        error: String? = nil,
        redirectCount: Int = 0
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.requestHeaders = CapturedRequest.redactSensitiveHeaders(requestHeaders)
        self.responseHeaders = responseHeaders
        self.requestBodySize = requestBodySize
        self.responseBodySize = responseBodySize
        self.error = error
        self.redirectCount = redirectCount
    }

    // Redact sensitive headers
    private static let sensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie",
        "x-api-key", "x-auth-token", "proxy-authorization"
    ]

    private static func redactSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        headers.mapValues { value in
            headers.keys.contains(where: { sensitiveHeaders.contains($0.lowercased()) })
                ? "[REDACTED]"
                : value
        }
    }
}
