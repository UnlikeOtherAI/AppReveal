import Foundation

/// Network detail payloads also have an `error` field; an empty value is not failure.
func appRevealToolResultIsError(_ result: AnyCodable) -> Bool {
    guard let payload = result.value as? [String: Any] else { return false }
    if (payload["success"] as? Bool) == false || (payload["isError"] as? Bool) == true { return true }
    guard let error = payload["error"], !(error is NSNull) else { return false }
    if let message = error as? String {
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return true
}

func appRevealWebToolResult(_ result: String, key: String = "result") -> AnyCodable {
    var payload: [String: Any] = [key: result]
    if let data = result.data(using: .utf8),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       appRevealToolResultIsError(AnyCodable(object)) {
        payload["error"] = object["error"] ?? "WebView action did not complete"
        payload["success"] = false
    }
    return AnyCodable(payload)
}

func appRevealWebResultString(_ result: Any?) throws -> String {
    if let string = result as? String { return string }
    let data = try JSONSerialization.data(withJSONObject: result ?? NSNull(), options: [.fragmentsAllowed])
    return String(data: data, encoding: .utf8) ?? "null"
}
