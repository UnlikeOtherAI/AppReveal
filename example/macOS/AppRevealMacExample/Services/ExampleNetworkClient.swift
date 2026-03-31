import Foundation

#if DEBUG
import AppReveal
#endif

final class ExampleNetworkClient {

    static let shared = ExampleNetworkClient()

    private var observers: [NetworkTrafficObserverBox] = []
    private var capturedRequests: [CapturedRequest] = []

    private init() {}

    func fetchOrders(completion: @escaping (Result<[ExampleOrder], Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/orders", responseSize: 2048) {
            completion(.success(ExampleOrder.samples))
        }
    }

    func fetchOrderDetail(id: String, completion: @escaping (Result<ExampleOrder, Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/orders/\(id)", responseSize: 1024) {
            let order = ExampleOrder.samples.first(where: { $0.id == id }) ?? ExampleOrder.samples[0]
            completion(.success(order))
        }
    }

    func fetchProducts(completion: @escaping (Result<[ExampleProduct], Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/products", responseSize: 4096) {
            completion(.success(ExampleProduct.samples))
        }
    }

    func fetchProfile(completion: @escaping (Result<ExampleUserProfile, Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/profile", responseSize: 512) {
            completion(.success(.sample))
        }
    }

    func saveSettings(endpoint: String, notificationsEnabled: Bool, theme: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let bodySize = endpoint.count + theme.count + 32
        simulateRequest(method: "POST", path: "/api/settings", requestBodySize: bodySize, responseSize: 256) {
            _ = notificationsEnabled
            completion(.success(()))
        }
    }

    private func simulateRequest(
        method: String,
        path: String,
        delay: TimeInterval = 0.25,
        requestBodySize: Int? = nil,
        responseSize: Int,
        work: @escaping () -> Void
    ) {
        let url = "https://api.example.com\(path)"
        let startTime = Date()
        let requestId = UUID().uuidString

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            let request = CapturedRequest(
                id: requestId,
                method: method,
                url: url,
                statusCode: 200,
                startTime: startTime,
                endTime: Date(),
                duration: delay,
                requestHeaders: [
                    "Content-Type": "application/json",
                    "Authorization": "Bearer example-token",
                ],
                responseHeaders: [
                    "Content-Type": "application/json",
                    "X-App-Region": "eu-west-1",
                ],
                requestBodySize: requestBodySize,
                responseBodySize: responseSize,
                redirectCount: 0
            )

            self?.capturedRequests.append(request)
            self?.notifyObservers(request)
            work()
        }
    }

    private func notifyObservers(_ request: CapturedRequest) {
        observers = observers.filter { $0.observer != nil }
        for box in observers {
            box.observer?.didCapture(request)
        }
    }
}

#if DEBUG
private final class NetworkTrafficObserverBox {
    weak var observer: NetworkTrafficObserver?

    init(observer: NetworkTrafficObserver) {
        self.observer = observer
    }
}

extension ExampleNetworkClient: NetworkObservable {
    var recentRequests: [CapturedRequest] {
        capturedRequests
    }

    func addObserver(_ observer: NetworkTrafficObserver) {
        observers.append(NetworkTrafficObserverBox(observer: observer))
    }
}
#endif
