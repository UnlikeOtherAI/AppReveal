import Foundation

// Run on an Apple verification host with the four library files listed in MAINTENANCE.md.
@main
struct NativeContractChecks {
    @MainActor static func main() throws {
        precondition(appRevealToolResultIsError(AnyCodable(["error": "rejected"])))
        precondition(appRevealToolResultIsError(AnyCodable(["success": false])))
        precondition(!appRevealToolResultIsError(AnyCodable(["error": ""])))
        precondition(!appRevealToolResultIsError(AnyCodable(["error": NSNull()])))
        precondition(appRevealToolResultIsError(AnyCodable(["isError": true])))
        for key in ["dom", "result"] {
            precondition(appRevealToolResultIsError(appRevealWebToolResult("{\"error\":\"missing\"}", key: key)))
            precondition(!appRevealToolResultIsError(appRevealWebToolResult("{\"error\":\"  \"}", key: key)))
        }
        let scalar = try appRevealWebResultString(42)
        let boolean = try appRevealWebResultString(true)
        let empty = try appRevealWebResultString(nil)
        precondition(scalar == "42" && boolean == "true" && empty == "null")
        let observer = NetworkObserverService.shared
        observer.clear()
        observer.addCall([
            "id": "test", "method": "GET", "url": "https://example.test",
            "requestTimestamp": 1000000.0, "responseTimestamp": 1001250.0,
            "requestHeaders": ["Authorization": "private", "Accept": "application/json"],
            "responseHeaders": ["Set-Cookie": "private", "Content-Type": "application/json"]
        ])
        let call = observer.callDetail(id: "test")!
        precondition(call.startTime.timeIntervalSince1970 == 1000)
        precondition(call.endTime!.timeIntervalSince1970 == 1001.25)
        precondition(call.duration == 1.25)
        precondition(call.requestHeaders["Authorization"] == "[REDACTED]")
        precondition(call.requestHeaders["Accept"] == "application/json")
        precondition(call.responseHeaders?["Set-Cookie"] == "[REDACTED]")
        precondition(observer.recentCalls(limit: -1).isEmpty)
        print("RN Swift result and network contracts passed")
    }
}
