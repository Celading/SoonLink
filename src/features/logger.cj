package soonlnk.features

import std.collection.ArrayList
import std.sync.Mutex
import lisi.term.ColorConsole
import soonlnk.commons.*

public enum LogLevel <: Equatable<LogLevel> {
    | LevelInfo
    | LevelWarn
    | LevelError
    | LevelDebug

    public operator func ==(right: LogLevel): Bool {
        match ((this, right)) {
            case (LevelInfo, LevelInfo) => true
            case (LevelWarn, LevelWarn) => true
            case (LevelError, LevelError) => true
            case (LevelDebug, LevelDebug) => true
            case _ => false
        }
    }

    public operator func !=(right: LogLevel): Bool {
        !(this == right)
    }
}

public func logLevelToString(level: LogLevel): String {
    match (level) {
        case LevelInfo => "info"
        case LevelWarn => "warn"
        case LevelError => "error"
        case LevelDebug => "debug"
    }
}

public func logLevelFromString(s: String): LogLevel {
    match (s) {
        case "warn" => LevelWarn
        case "error" => LevelError
        case "debug" => LevelDebug
        case _ => LevelInfo
    }
}

public class LogEntry {
    public var id: String = ""
    public var timestamp: Int64 = 0
    public var level: LogLevel = LevelInfo
    public var category: String = ""
    public var message: String = ""
    public var details: String = ""
    public var source: String = ""

    public init() {}

    public func toJson(): JsonObject {
        let obj = JsonObject()
            .put("id", id)
            .putInt("timestamp", timestamp)
            .put("level", logLevelToString(level))
            .put("category", category)
            .put("message", message)
        if (details.size > 0) {
            obj.put("details", details)
        }
        if (source.size > 0) {
            obj.put("source", source)
        }
        obj
    }
}

public class LogManager {
    var logs: ArrayList<LogEntry> = ArrayList<LogEntry>()
    let maxLogs: Int64
    let mutex: Mutex = Mutex()
    var enabled: Bool = true
    var consoleEnabled: Bool = true
    var showInUI: Bool = true
    var logIdCounter: Int64 = 0
    var onLogAdded: ?(LogEntry) -> Unit = None

    public init(maxLogs: Int64) {
        this.maxLogs = maxLogs
    }

    public func addLog(level: LogLevel, category: String, message: String,
                       details: String, source: String): Unit {
        if (!enabled) { return }
        var latest: ?LogEntry = None
        synchronized(mutex) {
            logIdCounter += 1
            let entry = LogEntry()
            entry.id = "log-${logIdCounter}"
            entry.timestamp = currentTimestamp()
            entry.level = level
            entry.category = category
            entry.message = message
            entry.details = details
            entry.source = source
            logs.add(entry)
            while (logs.size > maxLogs) {
                logs.remove(at: 0)
            }
            latest = Some(entry)
        }
        if (isConsoleEnabled()) {
            printColored(level, category, message, details, source)
        }
        if (let Some(entry) <- latest) {
            if (let Some(cb) <- onLogAdded) {
                cb(entry)
            }
        }
    }

    func printColored(level: LogLevel, category: String, message: String,
                      details: String, source: String): Unit {
        let tagPart = if (category.size > 0) { "[${category}] " } else { "" }
        let srcPart = if (source.size > 0) { " (${source})" } else { "" }
        let dtlPart = if (details.size > 0) { " | ${details}" } else { "" }
        let line = "${tagPart}${message}${dtlPart}${srcPart}"
        match (level) {
            case LevelInfo  => println(ColorConsole.green(line))
            case LevelWarn  => println(ColorConsole.yellow(line))
            case LevelError => println(ColorConsole.red(line))
            case LevelDebug => println(ColorConsole.dim(line))
        }
    }

    public func getLogs(limit: Int64): ArrayList<LogEntry> {
        let result = ArrayList<LogEntry>()
        synchronized(mutex) {
            var actualLimit = limit
            if (actualLimit <= 0 || actualLimit > logs.size) {
                actualLimit = logs.size
            }
            let start = logs.size - actualLimit
            var i = logs.size - 1
            while (i >= start && result.size < actualLimit) {
                result.add(logs[i])
                i -= 1
            }
        }
        result
    }

    public func getLogsByLevel(level: LogLevel, limit: Int64): ArrayList<LogEntry> {
        let result = ArrayList<LogEntry>()
        synchronized(mutex) {
            var i = logs.size - 1
            while (i >= 0 && result.size < limit) {
                if (logs[i].level == level) {
                    result.add(logs[i])
                }
                i -= 1
            }
        }
        result
    }

    public func getLogsByCategory(category: String, limit: Int64): ArrayList<LogEntry> {
        let result = ArrayList<LogEntry>()
        synchronized(mutex) {
            var i = logs.size - 1
            while (i >= 0 && result.size < limit) {
                if (logs[i].category == category) {
                    result.add(logs[i])
                }
                i -= 1
            }
        }
        result
    }

    public func clearLogs(): Unit {
        synchronized(mutex) {
            logs = ArrayList<LogEntry>()
        }
    }

    public func setEnabled(value: Bool): Unit {
        synchronized(mutex) { enabled = value }
    }

    public func setOnLogAdded(callback: (LogEntry) -> Unit): Unit {
        synchronized(mutex) {
            onLogAdded = callback
        }
    }

    public func setConsoleEnabled(value: Bool): Unit {
        synchronized(mutex) {
            consoleEnabled = value
        }
    }

    public func isConsoleEnabled(): Bool {
        synchronized(mutex) {
            consoleEnabled
        }
    }

    public func isEnabled(): Bool {
        synchronized(mutex) { enabled }
    }

    public func setShowInUI(value: Bool): Unit {
        synchronized(mutex) { showInUI = value }
    }

    public func shouldShowInUI(): Bool {
        synchronized(mutex) { showInUI && enabled }
    }

    public func getStats(): JsonObject {
        synchronized(mutex) {
            var infoCount: Int64 = 0
            var warnCount: Int64 = 0
            var errorCount: Int64 = 0
            var debugCount: Int64 = 0
            for (log in logs) {
                match (log.level) {
                    case LevelInfo => infoCount += 1
                    case LevelWarn => warnCount += 1
                    case LevelError => errorCount += 1
                    case LevelDebug => debugCount += 1
                }
            }
            JsonObject()
                .putInt("total", logs.size)
                .putBool("enabled", enabled)
                .putBool("showInUI", showInUI)
                .putInt("maxLogs", maxLogs)
                .putObj("levels", JsonObject()
                    .putInt("info", infoCount)
                    .putInt("warn", warnCount)
                    .putInt("error", errorCount)
                    .putInt("debug", debugCount)
                )
        }
    }

    public func logInfo(category: String, message: String, details: String, source: String): Unit {
        addLog(LevelInfo, category, message, details, source)
    }

    public func logWarn(category: String, message: String, details: String, source: String): Unit {
        addLog(LevelWarn, category, message, details, source)
    }

    public func logError(category: String, message: String, details: String, source: String): Unit {
        addLog(LevelError, category, message, details, source)
    }

    public func logDebug(category: String, message: String, details: String, source: String): Unit {
        addLog(LevelDebug, category, message, details, source)
    }
}
