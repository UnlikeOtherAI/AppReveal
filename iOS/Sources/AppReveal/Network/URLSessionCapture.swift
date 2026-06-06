// Automatic URLSession capture for debug builds.

import Foundation

#if DEBUG && os(iOS)

final class URLSessionCapture {

    static let shared = URLSessionCapture()

    private var isInstalled = false

    private init() {}

    func install() {
        guard !isInstalled else { return }
        URLProtocol.registerClass(AppRevealCaptureProtocol.self)
        isInstalled = true
    }
}

private final class AppRevealCaptureProtocol: URLProtocol, URLSessionDataDelegate {

    private static let handledKey = "AppRevealCaptureHandled"

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var startTime = Date()
    private var response: HTTPURLResponse?
    private var responseBodySize = 0
    private var redirectCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else {
            return false
        }

        guard let scheme = request.url?.scheme?.lowercased() else {
            return false
        }

        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        startTime = Date()

        guard let forwardedRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        URLProtocol.setProperty(true, forKey: Self.handledKey, in: forwardedRequest)

        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = (configuration.protocolClasses ?? []).filter { $0 != AppRevealCaptureProtocol.self }

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        let task = session.dataTask(with: forwardedRequest as URLRequest)
        dataTask = task
        task.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func captureCompletedRequest(error: Error?) {
        let responseHeaders = response?.allHeaderFields.reduce(into: [String: String]()) { partial, item in
            partial[String(describing: item.key)] = String(describing: item.value)
        }

        let captured = CapturedRequest(
            method: request.httpMethod ?? "GET",
            url: request.url?.absoluteString ?? "",
            statusCode: response?.statusCode,
            startTime: startTime,
            endTime: Date(),
            duration: Date().timeIntervalSince(startTime),
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            responseHeaders: responseHeaders,
            requestBodySize: request.httpBody?.count,
            responseBodySize: responseBodySize,
            error: error?.localizedDescription,
            redirectCount: redirectCount
        )

        Task { @MainActor in
            NetworkObserverService.shared.addCall(captured)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseBodySize += data.count
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        self.response = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirectCount += 1
        client?.urlProtocol(self, wasRedirectedTo: request, redirectResponse: response)
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }

        captureCompletedRequest(error: error)
        session.finishTasksAndInvalidate()
    }
}

#endif
