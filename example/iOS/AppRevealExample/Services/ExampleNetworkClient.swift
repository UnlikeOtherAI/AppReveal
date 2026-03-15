import Foundation

#if DEBUG
import AppReveal
#endif

class ExampleNetworkClient {

    static let shared = ExampleNetworkClient()

    private var observers: [NetworkTrafficObserverWrapper] = []

    private init() {}

    // MARK: - Simulated API calls

    func login(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        simulateRequest(method: "POST", path: "/api/auth/login") {
            if email.contains("@") && !password.isEmpty {
                completion(.success(()))
            } else {
                completion(.failure(NSError(domain: "auth", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid email or password"
                ])))
            }
        }
    }

    func fetchOrders(completion: @escaping (Result<[ExampleOrder], Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/orders") {
            completion(.success(ExampleOrder.samples))
        }
    }

    func fetchOrderDetail(id: String, completion: @escaping (Result<ExampleOrder, Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/orders/\(id)") {
            if let order = ExampleOrder.samples.first(where: { $0.id == id }) {
                completion(.success(order))
            } else {
                completion(.success(ExampleOrder.samples[0]))
            }
        }
    }

    func fetchProducts(completion: @escaping (Result<[ExampleProduct], Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/products") {
            completion(.success(ExampleProduct.samples))
        }
    }

    func fetchProfile(completion: @escaping (Result<[String: String], Error>) -> Void) {
        simulateRequest(method: "GET", path: "/api/profile") {
            completion(.success(["name": "Test User", "email": "test@example.com"]))
        }
    }

    // MARK: - Request simulation

    private func simulateRequest(method: String, path: String, delay: TimeInterval = 0.3, work: @escaping () -> Void) {
        let url = "https://api.example.com\(path)"
        let startTime = Date()
        let requestId = UUID().uuidString

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            let captured = CapturedRequest(
                id: requestId,
                method: method,
                url: url,
                statusCode: 200,
                startTime: startTime,
                endTime: Date(),
                duration: delay,
                requestHeaders: ["Content-Type": "application/json", "Authorization": "Bearer token123"],
                responseHeaders: ["Content-Type": "application/json"],
                requestBodySize: method == "POST" ? 128 : nil,
                responseBodySize: 2048,
                redirectCount: 0
            )

            #if DEBUG
            self?.notifyObservers(captured)
            #endif

            work()
        }
    }

    #if DEBUG
    private func notifyObservers(_ request: CapturedRequest) {
        for wrapper in observers {
            wrapper.observer?.didCapture(request)
        }
    }
    #endif
}

// MARK: - NetworkObservable conformance

#if DEBUG
private class NetworkTrafficObserverWrapper {
    weak var observer: NetworkTrafficObserver?
    init(_ observer: NetworkTrafficObserver) { self.observer = observer }
}

extension ExampleNetworkClient: NetworkObservable {
    var recentRequests: [CapturedRequest] { [] }

    func addObserver(_ observer: NetworkTrafficObserver) {
        observers.append(NetworkTrafficObserverWrapper(observer))
    }
}
#endif
