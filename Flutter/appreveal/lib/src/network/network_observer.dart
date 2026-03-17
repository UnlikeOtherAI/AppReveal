// Network traffic capture interfaces and service.

/// A captured HTTP request/response.
class CapturedRequest {
  final String id;
  final String method;
  final String url;
  final int? statusCode;
  final double? duration;
  final String? error;

  const CapturedRequest({
    required this.id,
    required this.method,
    required this.url,
    this.statusCode,
    this.duration,
    this.error,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'method': method,
    'url': url,
    'statusCode': statusCode?.toString() ?? 'nil',
    'duration': duration != null ? '${duration!.toStringAsFixed(3)}s' : 'nil',
    'error': error ?? '',
  };
}

/// Implement on your HTTP client to feed traffic into AppReveal's [get_network_calls] tool.
abstract interface class NetworkObservable {
  List<CapturedRequest> get recentRequests;
  void addObserver(NetworkTrafficObserver observer);
}

/// Callback for your HTTP client to report completed requests.
abstract interface class NetworkTrafficObserver {
  void didCapture(CapturedRequest request);
}

class NetworkObserverService implements NetworkTrafficObserver {
  static final shared = NetworkObserverService._();
  NetworkObserverService._();

  static const _maxCaptures = 200;
  final _requests = <CapturedRequest>[];
  NetworkObservable? _observable;

  void register(NetworkObservable observable) {
    _observable = observable;
    observable.addObserver(this);
  }

  @override
  void didCapture(CapturedRequest request) {
    _requests.add(request);
    if (_requests.length > _maxCaptures) _requests.removeAt(0);
  }

  List<Map<String, dynamic>> recentCalls({int limit = 50}) {
    final calls = _observable?.recentRequests ?? _requests;
    final capped = calls.length > limit ? calls.sublist(calls.length - limit) : calls;
    return capped.reversed.map((r) => r.toMap()).toList();
  }
}
