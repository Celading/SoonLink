package soonlnk.api2

import std.convert.*
import std.env.getVariable
import std.fs.{Directory, FileInfo}
import std.time.DateTime

public class DiskUsageSnapshot {
    public var totalBytes: Int64 = 0
    public var usedBytes: Int64 = 0
    public var freeBytes: Int64 = 0
    public var mountPoint: String = "/"
    public var timestamp: Int64 = 0

    public init() {}
}

public interface DiskProbe {
    func snapshot(path: String): DiskUsageSnapshot
}

public class DefaultDiskProbe <: DiskProbe {
    let defaultTotalBytes: Int64

    public init() {
        this.defaultTotalBytes = readEnvInt("SOONLINK_DISK_TOTAL_BYTES", 100 * 1024 * 1024 * 1024)
    }

    public init(defaultTotalBytes: Int64) {
        this.defaultTotalBytes = defaultTotalBytes
    }

    public func snapshot(path: String): DiskUsageSnapshot {
        let snap = DiskUsageSnapshot()
        let mount = if (path.size > 0) { path } else { "/" }
        let used = dirSizeBestEffort(mount)
        let total = if (defaultTotalBytes > used) { defaultTotalBytes } else { used + 1 }

        snap.totalBytes = total
        snap.usedBytes = used
        snap.freeBytes = if (total > used) { total - used } else { 0 }
        snap.mountPoint = mount
        snap.timestamp = nowTimestamp()
        snap
    }
}

public class MonitorDiskProbe <: DiskProbe {
    let defaultTotalBytes: Int64
    let entryLimit: Int64

    public init() {
        this.defaultTotalBytes = readEnvInt("SOONLINK_DISK_TOTAL_BYTES", 100 * 1024 * 1024 * 1024)
        this.entryLimit = readEnvInt("SOONLINK_MONITOR_DISK_ENTRY_LIMIT", 256)
    }

    public init(defaultTotalBytes: Int64, entryLimit: Int64) {
        this.defaultTotalBytes = defaultTotalBytes
        this.entryLimit = if (entryLimit > 0) { entryLimit } else { 256 }
    }

    public func snapshot(path: String): DiskUsageSnapshot {
        let snap = DiskUsageSnapshot()
        let mount = if (path.size > 0) { path } else { "/" }
        let used = estimatePathUsage(mount, entryLimit)
        let total = if (defaultTotalBytes > used) { defaultTotalBytes } else { used + 1 }

        snap.totalBytes = total
        snap.usedBytes = used
        snap.freeBytes = if (total > used) { total - used } else { 0 }
        snap.mountPoint = mount
        snap.timestamp = nowTimestamp()
        snap
    }
}

func dirSizeBestEffort(path: String): Int64 {
    try {
        let info = FileInfo(path)
        if (!info.isDirectory()) {
            return info.size
        }
    } catch (_: Exception) {
        return 0
    }

    var total: Int64 = 0
    try {
        let entries = Directory.readFrom(path)
        for (entry in entries) {
            let entryPath = entry.path.toString()
            if (entry.isDirectory()) {
                total += dirSizeBestEffort(entryPath)
            } else {
                total += entry.size
            }
        }
    } catch (_: Exception) {
        return total
    }
    total
}

func estimatePathUsage(path: String, entryLimit: Int64): Int64 {
    try {
        let info = FileInfo(path)
        if (!info.isDirectory()) {
            return info.size
        }
    } catch (_: Exception) {
        return 0
    }

    var total: Int64 = 0
    var seen: Int64 = 0
    try {
        let entries = Directory.readFrom(path)
        for (entry in entries) {
            if (seen >= entryLimit) {
                break
            }
            if (!entry.isDirectory()) {
                total += entry.size
            }
            seen += 1
        }
    } catch (_: Exception) {
        return total
    }
    total
}

func readEnvInt(key: String, fallback: Int64): Int64 {
    if (let Some(raw) <- getVariable(key)) {
        if (raw.size > 0) {
            try {
                return Int64.parse(raw)
            } catch (_: Exception) {
                return fallback
            }
        }
    }
    fallback
}

func nowTimestamp(): Int64 {
    DateTime.now().toUnixTimeStamp().toSeconds()
}
