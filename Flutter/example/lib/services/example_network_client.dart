import 'dart:math';
import 'package:appreveal/appreveal.dart';

class ExampleNetworkClient implements NetworkObservable {
  static final instance = ExampleNetworkClient._();
  ExampleNetworkClient._();

  final _requests = <CapturedRequest>[];
  final _observers = <NetworkTrafficObserver>[];
  final _rng = Random();

  @override
  List<CapturedRequest> get recentRequests => List.unmodifiable(_requests);

  @override
  void addObserver(NetworkTrafficObserver observer) {
    _observers.add(observer);
  }

  /// Call this to simulate a captured API request (e.g. from your HTTP client).
  void capture({
    required String method,
    required String url,
    int? statusCode,
    double? duration,
    String? error,
  }) {
    final req = CapturedRequest(
      id: _rng.nextInt(999999).toString(),
      method: method,
      url: url,
      statusCode: statusCode,
      duration: duration,
      error: error,
    );
    _requests.add(req);
    if (_requests.length > 200) _requests.removeAt(0);
    for (final obs in _observers) {
      obs.didCapture(req);
    }
  }

  /// Simulate a burst of API calls on app launch.
  void simulateLaunchCalls() {
    capture(method: 'GET', url: 'https://api.example.com/catalog', statusCode: 200, duration: 0.342);
    capture(method: 'GET', url: 'https://api.example.com/user/profile', statusCode: 200, duration: 0.198);
    capture(method: 'GET', url: 'https://api.example.com/cart', statusCode: 200, duration: 0.156);
    capture(method: 'GET', url: 'https://api.example.com/feature-flags', statusCode: 200, duration: 0.089);
  }
}
