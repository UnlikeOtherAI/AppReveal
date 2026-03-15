// Network traffic observation

import Foundation

#if DEBUG

/// Conform your network client to expose traffic to AppReveal.
public protocol NetworkObservable: AnyObject {
    var recentRequests: [CapturedRequest] { get }
    func addObserver(_ observer: NetworkTrafficObserver)
}

/// Receives network traffic events.
public protocol NetworkTrafficObserver: AnyObject {
    func didCapture(_ request: CapturedRequest)
}

@MainActor
final class NetworkObserverService: NetworkTrafficObserver {

    static let shared = NetworkObserverService()

    private let maxBufferSize = 200
    private(set) var capturedRequests: [CapturedRequest] = []
    private weak var observable: NetworkObservable?

    private init() {}

    func register(_ observable: NetworkObservable) {
        self.observable = observable
        observable.addObserver(self)
    }

    nonisolated func didCapture(_ request: CapturedRequest) {
        Task { @MainActor in
            capturedRequests.append(request)
            if capturedRequests.count > maxBufferSize {
                capturedRequests.removeFirst(capturedRequests.count - maxBufferSize)
            }
        }
    }

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

#endif
