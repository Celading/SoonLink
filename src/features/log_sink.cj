package soonlnk.features

import std.collection.ArrayList
import std.fs.*
import soonlnk.commons.*

public interface LogSink {
    func append(entry: LogEntry): Unit
    func flush(): Unit
}

public class RollingFileLogSink <: LogSink {
    let logDir: String
    let prefix: String
    let maxFileSize: Int64
    let maxFiles: Int64
    let fileMgr: FileMgr

    var currentLogFile: String = ""

    public init(logDir: String) {
        this.logDir = logDir
        this.prefix = "soonlink"
        this.maxFileSize = 2 * 1024 * 1024
        this.maxFiles = 5
        this.fileMgr = LocalFileMgr()

        fileMgr.ensureDir(logDir)
        this.currentLogFile = joinLogPath(logDir, "${prefix}.log")
    }

    public init(logDir: String, prefix: String, maxFileSize: Int64, maxFiles: Int64, fileMgr: FileMgr) {
        this.logDir = logDir
        this.prefix = prefix
        this.maxFileSize = maxFileSize
        this.maxFiles = maxFiles
        this.fileMgr = fileMgr

        fileMgr.ensureDir(logDir)
        this.currentLogFile = joinLogPath(logDir, "${prefix}.log")
    }

    public func append(entry: LogEntry): Unit {
        let line = formatLogLine(entry)
        fileMgr.writeText(currentLogFile, line + "\n", true)
        rotateIfNeeded()
    }

    public func flush(): Unit {}

    func rotateIfNeeded(): Unit {
        if (!fileMgr.exists(currentLogFile)) {
            return
        }

        try {
            let size = FileInfo(currentLogFile).size
            if (size >= maxFileSize) {
                currentLogFile = joinLogPath(logDir, "${prefix}-${currentTimestamp()}.log")
                fileMgr.writeText(currentLogFile, "", false)
                cleanupOldLogs()
            }
        } catch (_: Exception) {}
    }

    func cleanupOldLogs(): Unit {
        let paths = ArrayList<String>()
        try {
            let files = Directory.readFrom(logDir)
            for (file in files) {
                let name = file.path.fileName.toString()
                if (strStartsWith(name, prefix) && strEndsWith(name, ".log")) {
                    paths.add(file.path.toString())
                }
            }
        } catch (_: Exception) {
            return
        }

        if (paths.size <= maxFiles) {
            return
        }

        sortAsc(paths)
        let removeCount = paths.size - maxFiles
        for (i in 0..removeCount) {
            try {
                remove(paths[i])
            } catch (_: Exception) {}
        }
    }
}

func joinLogPath(base: String, name: String): String {
    if (base.size == 0) {
        return name
    }
    let runes = base.toRuneArray()
    if (runes[runes.size - 1] == r'/') {
        return base + name
    }
    base + "/" + name
}

func formatLogLine(entry: LogEntry): String {
    let level = logLevelToString(entry.level)
    let source = if (entry.source.size > 0) { entry.source } else { "-" }
    let details = if (entry.details.size > 0) { entry.details } else { "-" }
    "${entry.timestamp}\t${level}\t${entry.category}\t${entry.message}\t${details}\t${source}"
}

func sortAsc(paths: ArrayList<String>): Unit {
    if (paths.size <= 1) {
        return
    }
    var i: Int64 = 0
    while (i < paths.size) {
        var j: Int64 = 0
        while (j < paths.size - i - 1) {
            if (paths[j] > paths[j + 1]) {
                let tmp = paths[j]
                paths[j] = paths[j + 1]
                paths[j + 1] = tmp
            }
            j += 1
        }
        i += 1
    }
}
