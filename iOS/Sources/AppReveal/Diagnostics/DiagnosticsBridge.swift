// Diagnostics: logs, errors, metrics

import Foundation
import OSLog

#if DEBUG

@MainActor
final class DiagnosticsBridge {

    static let shared = DiagnosticsBridge()

    private var recentErrors: [AppError] = []
    private let maxErrors = 100

    private init() {}

    // MARK: - Errors

    struct AppError: Codable {
        let timestamp: Date
        let domain: String
        let message: String
        let stackTrace: String?
    }

    func captureError(domain: String, message: String, stackTrace: String? = nil) {
        let error = AppError(
            timestamp: Date(),
            domain: domain,
            message: message,
            stackTrace: stackTrace
        )
        recentErrors.append(error)
        if recentErrors.count > maxErrors {
            recentErrors.removeFirst(recentErrors.count - maxErrors)
        }
    }

    func getRecentErrors(limit: Int = 20) -> [AppError] {
        Array(recentErrors.suffix(limit))
    }

    // MARK: - Logs

    struct LogEntry: Codable {
        let timestamp: Date
        let subsystem: String
        let category: String
        let level: String
        let message: String
    }

    func getRecentLogs(subsystem: String? = nil, limit: Int = 50) -> [LogEntry] {
        // OSLogStore requires iOS 15+ and entitlements for full access.
        // This provides a best-effort query of recent logs.
        guard #available(iOS 15.0, *) else { return [] }

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-300)) // last 5 min
            var predicate: NSPredicate?
            if let subsystem = subsystem {
                predicate = NSPredicate(format: "subsystem == %@", subsystem)
            }

            let entries = try store.getEntries(at: position, matching: predicate)
            var logs: [LogEntry] = []

            for entry in entries {
                guard let logEntry = entry as? OSLogEntryLog else { continue }
                logs.append(LogEntry(
                    timestamp: logEntry.date,
                    subsystem: logEntry.subsystem,
                    category: logEntry.category,
                    level: logEntry.level.description,
                    message: logEntry.composedMessage
                ))
                if logs.count >= limit { break }
            }

            return logs
        } catch {
            return []
        }
    }
}

// Extension to make OSLogEntryLog.Level printable
extension OSLogEntryLog.Level: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}

#endif
