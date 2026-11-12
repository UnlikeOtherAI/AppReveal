import Foundation

/// Network detail payloads also have an `error` field; an empty value is not failure.
func appRevealToolResultIsError(_ result: AnyCodable) -> Bool {
    guard let payload = result.value as? [String: Any] else { return false }
    if (payload["success"] as? Bool) == false { return true }
    guard let error = payload["error"], !(error is NSNull) else { return false }
    if let message = error as? String {
        return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return true
}
