// Network traffic ring buffer.
// In the RN module, JS intercepts fetch/XHR and calls captureNetworkCall()
// on the native module, which calls addCall(_:) here.
// There is no NetworkObservable protocol — JS feeds the buffer directly.

import Foundation

@MainActor
final class NetworkObserverService {

    static let shared = NetworkObserverService()

    private let maxBufferSize = 200
    private(set) var capturedRequests: [CapturedRequest] = []

    private init() {}

    // MARK: - JS-driven ingestion

    /// Called from JS via the native module with a dict matching CapturedRequest fields.
    func addCall(_ dict: [String: Any]) {
        let id = dict["id"] as? String ?? UUID().uuidString
        let method = dict["method"] as? String ?? "GET"
        let url = dict["url"] as? String ?? ""
        let statusCode = dict["statusCode"] as? Int
        let duration = dict["duration"] as? TimeInterval
        let requestBodySize = dict["requestBodySize"] as? Int
        let responseBodySize = dict["responseBodySize"] as? Int
        let error = dict["error"] as? String
        let redirectCount = dict["redirectCount"] as? Int ?? 0
        let requestHeaders = dict["requestHeaders"] as? [String: String] ?? [:]
        let responseHeaders = dict["responseHeaders"] as? [String: String]

        // Parse timestamps — accept ISO8601 strings or epoch doubles
        let startTime: Date
        if let ts = dict["startTime"] as? TimeInterval {
            startTime = Date(timeIntervalSince1970: ts)
        } else if let tsStr = dict["startTime"] as? String,
                  let parsed = ISO8601DateFormatter().date(from: tsStr) {
            startTime = parsed
        } else {
            startTime = Date()
        }

        let endTime: Date?
        if let ts = dict["endTime"] as? TimeInterval {
            endTime = Date(timeIntervalSince1970: ts)
        } else if let tsStr = dict["endTime"] as? String,
                  let parsed = ISO8601DateFormatter().date(from: tsStr) {
            endTime = parsed
        } else {
            endTime = nil
        }

        let request = CapturedRequest(
            id: id,
            method: method,
            url: url,
            statusCode: statusCode,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            requestBodySize: requestBodySize,
            responseBodySize: responseBodySize,
            error: error,
            redirectCount: redirectCount
        )

        capturedRequests.append(request)
        if capturedRequests.count > maxBufferSize {
            capturedRequests.removeFirst(capturedRequests.count - maxBufferSize)
        }
    }

    // MARK: - Queries

    func recentCalls(limit: Int = 50) -> [CapturedRequest] {
        Array(capturedRequests.suffix(limit))
    }

    func callDetail(id: String) -> CapturedRequest? {
        capturedRequests.first { $0.id == id }
    }

    func clear() {
        capturedRequests.removeAll()
    }
}
