// Models for captured network traffic

import Foundation

#if DEBUG

public struct CapturedSSEEvent: Codable {
    public let id: String?
    public let event: String?
    public let data: String
    public let retry: Int?
    public let timestamp: Date

    public init(
        id: String? = nil,
        event: String? = nil,
        data: String,
        retry: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.event = event
        self.data = data
        self.retry = retry
        self.timestamp = timestamp
    }
}

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
    public let requestBody: String?
    public let responseBody: String?
    public let requestBodyTruncated: Bool
    public let responseBodyTruncated: Bool
    public let sseEvents: [CapturedSSEEvent]
    public let isStreaming: Bool
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
        requestBody: String? = nil,
        responseBody: String? = nil,
        requestBodyTruncated: Bool = false,
        responseBodyTruncated: Bool = false,
        sseEvents: [CapturedSSEEvent] = [],
        isStreaming: Bool = false,
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
        self.responseHeaders = responseHeaders.map(CapturedRequest.redactSensitiveHeaders)
        self.requestBodySize = requestBodySize
        self.responseBodySize = responseBodySize
        self.requestBody = requestBody
        self.responseBody = responseBody
        self.requestBodyTruncated = requestBodyTruncated
        self.responseBodyTruncated = responseBodyTruncated
        self.sseEvents = sseEvents
        self.isStreaming = isStreaming
        self.error = error
        self.redirectCount = redirectCount
    }

    // Redact sensitive headers
    private static let sensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie",
        "x-api-key", "x-auth-token", "proxy-authorization"
    ]

    private static func redactSensitiveHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { partial, item in
            partial[item.key] = sensitiveHeaders.contains(item.key.lowercased()) ? "[REDACTED]" : item.value
        }
    }
}

#endif
