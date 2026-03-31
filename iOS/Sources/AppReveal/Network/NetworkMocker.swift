// URLProtocol-based network response mocking

import Foundation

#if DEBUG

/// Mock rule for intercepting network requests.
public struct MockRule: Identifiable {
    public let id: String
    public let urlPattern: String
    public let method: String?
    public let statusCode: Int
    public let responseBody: Data?
    public let responseHeaders: [String: String]
    public let delay: TimeInterval

    public init(
        id: String = UUID().uuidString,
        urlPattern: String,
        method: String? = nil,
        statusCode: Int = 200,
        responseBody: Data? = nil,
        responseHeaders: [String: String] = ["Content-Type": "application/json"],
        delay: TimeInterval = 0
    ) {
        self.id = id
        self.urlPattern = urlPattern
        self.method = method
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.responseHeaders = responseHeaders
        self.delay = delay
    }

    func matches(_ request: URLRequest) -> Bool {
        guard let url = request.url?.absoluteString else { return false }
        if let method = method, request.httpMethod != method { return false }
        return url.contains(urlPattern)
    }
}

final class NetworkMocker {

    static let shared = NetworkMocker()

    private(set) var rules: [MockRule] = []
    private(set) var isOffline = false
    private(set) var globalLatency: TimeInterval = 0

    private init() {}

    func addRule(_ rule: MockRule) {
        rules.append(rule)
    }

    func removeRule(id: String) {
        rules.removeAll { $0.id == id }
    }

    func clearRules() {
        rules.removeAll()
    }

    func setOffline(_ offline: Bool) {
        isOffline = offline
    }

    func setGlobalLatency(_ seconds: TimeInterval) {
        globalLatency = seconds
    }

    func matchingRule(for request: URLRequest) -> MockRule? {
        rules.first { $0.matches(request) }
    }
}

/// URLProtocol subclass for intercepting requests.
/// Register on your URLSessionConfiguration.protocolClasses.
public final class AppRevealMockProtocol: URLProtocol {

    public override static func canInit(with request: URLRequest) -> Bool {
        let mocker = NetworkMocker.shared
        return mocker.isOffline || mocker.matchingRule(for: request) != nil
    }

    public override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        let mocker = NetworkMocker.shared

        if mocker.isOffline {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let rule = mocker.matchingRule(for: request) else {
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown)
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let totalDelay = rule.delay + mocker.globalLatency

        let work = { [weak self] in
            guard let self = self, let url = self.request.url else { return }

            let response = HTTPURLResponse(
                url: url,
                statusCode: rule.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: rule.responseHeaders
            )!

            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let body = rule.responseBody {
                self.client?.urlProtocol(self, didLoad: body)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }

        if totalDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + totalDelay, execute: work)
        } else {
            work()
        }
    }

    public override func stopLoading() {}
}

#endif
