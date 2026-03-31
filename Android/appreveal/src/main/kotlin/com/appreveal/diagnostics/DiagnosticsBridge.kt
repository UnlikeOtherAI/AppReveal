package com.appreveal.diagnostics

import java.io.BufferedReader
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Log entry from logcat.
 */
data class LogEntry(
    val timestamp: String,
    val subsystem: String,
    val category: String,
    val level: String,
    val message: String,
)

/**
 * Captured application error.
 */
data class AppError(
    val timestamp: String,
    val domain: String,
    val message: String,
    val stackTrace: String?,
)

/**
 * Diagnostics bridge: provides recent logs (via logcat) and error capture.
 */
internal object DiagnosticsBridge {
    private const val MAX_ERRORS = 100
    private val recentErrors = mutableListOf<AppError>()
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)

    /**
     * Get recent logs by reading logcat for the current process.
     */
    fun getRecentLogs(
        subsystem: String? = null,
        limit: Int = 50,
    ): List<LogEntry> =
        try {
            val pid = android.os.Process.myPid()
            val args = arrayOf("logcat", "-d", "-t", limit.toString(), "--pid=$pid")
            val proc = ProcessBuilder(*args).redirectErrorStream(true).start()
            val reader = BufferedReader(InputStreamReader(proc.inputStream))
            val logs = mutableListOf<LogEntry>()

            reader.useLines { lines ->
                for (line in lines) {
                    val entry = parseLogcatLine(line) ?: continue
                    if (subsystem != null && entry.subsystem != subsystem) continue
                    logs.add(entry)
                    if (logs.size >= limit) break
                }
            }
            proc.waitFor()
            logs
        } catch (_: Exception) {
            emptyList()
        }

    /**
     * Parse a logcat line into a LogEntry.
     * Standard logcat format: "MM-DD HH:MM:SS.mmm PID TID LEVEL TAG: MESSAGE"
     */
    private fun parseLogcatLine(line: String): LogEntry? {
        if (line.isBlank() || line.startsWith("-----")) return null

        val regex = Regex("""^(\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s+\d+\s+\d+\s+([VDIWEF])\s+(\S+)\s*:\s*(.*)$""")
        val match = regex.matchEntire(line) ?: return null

        val timestamp = match.groupValues[1]
        val levelChar = match.groupValues[2]
        val tag = match.groupValues[3]
        val message = match.groupValues[4]

        val level =
            when (levelChar) {
                "V" -> "verbose"
                "D" -> "debug"
                "I" -> "info"
                "W" -> "warning"
                "E" -> "error"
                "F" -> "fault"
                else -> "unknown"
            }

        return LogEntry(
            timestamp = timestamp,
            subsystem = tag,
            category = "",
            level = level,
            message = message,
        )
    }

    /**
     * Get recent captured errors from the in-memory ring buffer.
     */
    @Synchronized
    fun getRecentErrors(limit: Int = 20): List<AppError> {
        val size = recentErrors.size
        val fromIndex = maxOf(0, size - limit)
        return recentErrors.subList(fromIndex, size).toList()
    }

    /**
     * Capture an error to the in-memory ring buffer.
     */
    @Synchronized
    fun captureError(
        domain: String,
        message: String,
        stackTrace: String? = null,
    ) {
        val error =
            AppError(
                timestamp = dateFormat.format(Date()),
                domain = domain,
                message = message,
                stackTrace = stackTrace,
            )
        recentErrors.add(error)
        if (recentErrors.size > MAX_ERRORS) {
            recentErrors.removeAt(0)
        }
    }
}
