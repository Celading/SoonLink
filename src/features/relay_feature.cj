package soonlnk.features

import soonlnk.api2.*
import soonlnk.commons.*
import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.fs.{Directory, FileInfo, remove}
import std.sync.Mutex
import std.unicode.*

let relayTextRecordMaxBytes: Int64 = 256 * 1024

public class RelayFeature {
    let cacheDir: String
    let retentionHours: Int64
    let limitMode: String
    let limitBytes: Int64
    let limitPercent: Int64
    let diskProbe: DiskProbe
    let whitelistStore: TomlConfigStore
    let fileMgr: FileMgr

    let mutex: Mutex = Mutex()
    var jobs: HashMap<String, RelayJob> = HashMap<String, RelayJob>()
    var whitelist: HashMap<String, WhitelistRule> = HashMap<String, WhitelistRule>()
    var onlineChecker: ?(String) -> Bool = None
    var writeHandler: ?(String, String, Array<UInt8>) -> Bool = None

    public init(
        cacheDir: String,
        retentionHours: Int64,
        limitMode: String,
        limitBytes: Int64,
        limitPercent: Int64,
        diskProbe: DiskProbe,
        whitelistFile: String
    ) {
        this.cacheDir = cacheDir
        this.retentionHours = if (retentionHours > 0) { retentionHours } else { 24 }
        this.limitMode = normalizeLimitMode(limitMode)
        this.limitBytes = if (limitBytes > 0) { limitBytes } else { 20 * 1024 * 1024 * 1024 }
        this.limitPercent = if (limitPercent > 0) { limitPercent } else { 10 }
        this.diskProbe = diskProbe
        this.whitelistStore = TomlConfigStore(whitelistFile)
        this.fileMgr = LocalFileMgr()

        fileMgr.ensureDir(cacheDir)
        loadWhitelist()
    }

    public func setDeviceOnlineChecker(checker: (String) -> Bool): Unit {
        synchronized(mutex) {
            onlineChecker = checker
        }
    }

    public func setWriteHandler(handler: (String, String, Array<UInt8>) -> Bool): Unit {
        synchronized(mutex) {
            writeHandler = handler
        }
    }

    public func createJobFromPayload(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        payload: Array<UInt8>
    ): RelayJob {
        createRelayRecord("file", sourceDevice, targetDevice, targetPath, fileName, payload, true)
    }

    public func createTextRecord(sourceDevice: String, fileName: String, content: String): RelayJob {
        createTextRecord(sourceDevice, fileName, content, "/tmpSL")
    }

    public func createTextRecord(sourceDevice: String, fileName: String, content: String, targetPath: String): RelayJob {
        let payload = stringToBytes(content)
        if (payload.size == 0) {
            throw Exception("文本内容不能为空")
        }
        if (payload.size > relayTextRecordMaxBytes) {
            throw Exception("临时文本缓存最多支持 256 KiB，请改走文件中转")
        }
        createRelayRecord("text", sourceDevice, "", normalizeRelayTextTargetPath(targetPath), normalizeRelayTextRecordName(fileName), payload, false)
    }

    func createRelayRecord(
        recordKind: String,
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        payload: Array<UInt8>,
        attemptDispatch: Bool
    ): RelayJob {
        let job = RelayJob()
        job.id = "relay-" + generateId()
        job.recordKind = recordKind
        job.sourceDevice = if (sourceDevice.size > 0) { sourceDevice } else { "unknown" }
        job.targetDevice = if (attemptDispatch) { targetDevice } else { "" }
        job.targetPath = if (recordKind == "text") {
            normalizeRelayTextTargetPath(targetPath)
        } else if (attemptDispatch) {
            normalizeRelayPath(targetPath)
        } else {
            "/"
        }
        job.fileName = if (recordKind == "text") { normalizeRelayTextRecordName(fileName) } else { normalizeFileName(fileName) }
        job.createdAt = currentTimestamp()
        job.updatedAt = job.createdAt
        job.expiresAt = job.createdAt + retentionHours * 3600
        job.status = "caching"
        job.cachePath = joinPaths(cacheDir, "${job.id}_${job.fileName}")

        try {
            fileMgr.writeBytes(job.cachePath, payload, false)
            job.bytes = payload.size
            job.status = "cached"
            job.cacheAvailable = true
            job.message = if (recordKind == "text") { "text record cached" } else { "cached on relay" }
        } catch (e: Exception) {
            job.status = "failed"
            job.cacheAvailable = false
            job.message = "cache write failed: ${e.message}"
        }

        synchronized(mutex) {
            jobs.add(job.id, job)
        }

        enforceCapacity()
        if (attemptDispatch) {
            tryDispatch(job.id)
        }
        job
    }

    public func listJobs(): ArrayList<RelayJob> {
        let out = ArrayList<RelayJob>()
        synchronized(mutex) {
            for ((_, job) in jobs) {
                refreshCacheState(job)
                out.add(job)
            }
        }
        out
    }

    public func getJob(jobId: String): ?RelayJob {
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    Some(job)
                case None => None
            }
        }
    }

    public func retryJob(jobId: String): ?RelayJob {
        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                if (job.recordKind == "text") {
                    refreshCacheState(job)
                    job.status = if (job.cacheAvailable) { "cached" } else { "failed" }
                    job.message = if (job.cacheAvailable) { "text record retained" } else { "text record missing" }
                    job.updatedAt = currentTimestamp()
                    return Some(job)
                }
                if (job.status == "expired") {
                    refreshCacheState(job)
                    return Some(job)
                }
                job.status = "cached"
                job.message = "retry queued"
                job.updatedAt = currentTimestamp()
                refreshCacheState(job)
            }
        }
        tryDispatch(jobId)
        getJob(jobId)
    }

    public func deleteJob(jobId: String): Bool {
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    jobs.remove(jobId)
                    true
                case None => false
            }
        }
    }

    public func cancelJob(jobId: String): Bool {
        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                job.status = "failed"
                job.message = "cancelled by user"
                job.updatedAt = currentTimestamp()
                try {
                    remove(job.cachePath)
                } catch (_: Exception) {}
                job.cacheAvailable = false
                return true
            }
        }
        false
    }

    public func cacheDescriptor(jobId: String): ?(String, String) {
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    if (!canAccessCache(job)) {
                        return None
                    }
                    return Some((job.cachePath, job.fileName))
                case None => ()
            }
        }
        None
    }

    public func restoreJob(jobId: String, targetDevice: String, targetPath: String): Bool {
        var cachePath = ""
        var fileName = ""
        var handler: ?(String, String, Array<UInt8>) -> Bool = None
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    if (!canAccessCache(job)) {
                        job.message = "relay cache unavailable"
                        job.updatedAt = currentTimestamp()
                        return false
                    }
                    cachePath = job.cachePath
                    fileName = job.fileName
                    match (writeHandler) {
                        case Some(h) => handler = Some(h)
                        case None =>
                            job.message = "restore handler unavailable"
                            job.updatedAt = currentTimestamp()
                            return false
                    }
                case None => return false
            }
        }

        try {
            let payload = fileMgr.readBytes(cachePath)
            let finalPath = composeRelayTargetFilePath(targetPath, fileName)
            var restored = false
            if (let Some(h) <- handler) {
                restored = h(targetDevice, finalPath, payload)
            }
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    refreshCacheState(job)
                    job.updatedAt = currentTimestamp()
                    if (restored) {
                        job.message = "cache restored to ${targetDevice}:${finalPath}"
                    } else {
                        job.message = "restore write failed"
                    }
                }
            }
            restored
        } catch (e: Exception) {
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    refreshCacheState(job)
                    job.updatedAt = currentTimestamp()
                    job.message = "restore error: ${e.message}"
                }
            }
            false
        }
    }

    public func tick(): Unit {
        cleanupExpired()
        let ids = ArrayList<String>()
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (job.recordKind != "file") {
                    continue
                }
                if (job.status == "cached" || job.status == "dispatching") {
                    ids.add(id)
                }
            }
        }
        for (id in ids) {
            tryDispatch(id)
        }
    }

    public func cleanupExpired(): Unit {
        let now = currentTimestamp()
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.status == "delivered" || job.status == "expired") {
                    continue
                }
                if (job.expiresAt > 0 && now > job.expiresAt) {
                    job.status = "expired"
                    job.message = "expired by TTL"
                    job.updatedAt = now
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    job.cacheAvailable = false
                }
            }
        }
    }

    public func upsertRule(sourceDevice: String, targetDevice: String, enabled: Bool): WhitelistRule {
        let rule = WhitelistRule()
        rule.sourceDevice = if (sourceDevice.size > 0) { sourceDevice } else { "*" }
        rule.targetDevice = targetDevice
        rule.enabled = enabled
        rule.createdAt = currentTimestamp()
        synchronized(mutex) {
            whitelist.add(rule.key(), rule)
            persistWhitelist()
        }
        rule
    }

    public func listRules(targetDevice: String): ArrayList<WhitelistRule> {
        let out = ArrayList<WhitelistRule>()
        synchronized(mutex) {
            for ((_, rule) in whitelist) {
                if (targetDevice.size > 0 && rule.targetDevice != targetDevice) {
                    continue
                }
                out.add(rule)
            }
        }
        out
    }

    public func removeRule(sourceDevice: String, targetDevice: String): Bool {
        let source = if (sourceDevice.size > 0) { sourceDevice } else { "*" }
        let key = "${source}->${targetDevice}"
        synchronized(mutex) {
            if (let Some(_rule) <- whitelist.get(key)) {
                whitelist.remove(key)
                persistWhitelist()
                return true
            }
        }
        false
    }

    public func setRuleEnabled(sourceDevice: String, targetDevice: String, enabled: Bool): ?WhitelistRule {
        let source = if (sourceDevice.size > 0) { sourceDevice } else { "*" }
        let key = "${source}->${targetDevice}"
        synchronized(mutex) {
            if (let Some(rule) <- whitelist.get(key)) {
                rule.enabled = enabled
                persistWhitelist()
                return Some(rule)
            }
        }
        None
    }

    public func cleanupJobs(statusFilter: String, olderThan: Int64): Int64 {
        let ids = ArrayList<String>()
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (!shouldCleanupStatus(statusFilter, job.status)) {
                    continue
                }
                let ts = if (job.updatedAt > 0) { job.updatedAt } else { job.createdAt }
                if (olderThan > 0 && ts > olderThan) {
                    continue
                }
                ids.add(id)
            }

            for (id in ids) {
                if (let Some(job) <- jobs.get(id)) {
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                }
                jobs.remove(id)
            }
        }
        ids.size
    }

    public func stats(): JsonObject {
        var total: Int64 = 0
        var cached: Int64 = 0
        var pendingApproval: Int64 = 0
        var failed: Int64 = 0
        var delivered: Int64 = 0

        synchronized(mutex) {
            for ((_, job) in jobs) {
                total += 1
                match (job.status) {
                    case "cached" => cached += 1
                    case "dispatching" => cached += 1
                    case "pending_approval" => pendingApproval += 1
                    case "failed" => failed += 1
                    case "expired" => failed += 1
                    case "delivered" => delivered += 1
                    case _ => ()
                }
            }
        }

        JsonObject()
            .putInt("total", total)
            .putInt("cached", cached)
            .putInt("pendingApproval", pendingApproval)
            .putInt("failed", failed)
            .putInt("delivered", delivered)
    }

    func tryDispatch(jobId: String): Unit {
        var targetDevice = ""
        var sourceDevice = ""
        var targetPath = ""
        var cachePath = ""
        var canDispatch = false
        var hasHandler = false
        var handler: ?(String, String, Array<UInt8>) -> Bool = None

        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                if (job.status == "expired" || job.status == "delivered" || job.status == "failed") {
                    return
                }
                if (!isWhitelisted(job.sourceDevice, job.targetDevice)) {
                    job.status = "pending_approval"
                    job.message = "target not in whitelist"
                    job.updatedAt = currentTimestamp()
                    return
                }
                if (!isDeviceOnline(job.targetDevice)) {
                    job.status = "cached"
                    job.message = "target device offline"
                    job.updatedAt = currentTimestamp()
                    return
                }
                job.status = "dispatching"
                job.updatedAt = currentTimestamp()
                job.attempts += 1

                sourceDevice = job.sourceDevice
                targetDevice = job.targetDevice
                targetPath = composeRelayTargetFilePath(job.targetPath, job.fileName)
                cachePath = job.cachePath
                canDispatch = true
                match (writeHandler) {
                    case Some(h) =>
                        handler = Some(h)
                        hasHandler = true
                    case None => ()
                }
            }
        }

        if (!canDispatch) {
            return
        }
        if (!hasHandler) {
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    job.status = "cached"
                    job.message = "dispatch handler unavailable"
                    job.updatedAt = currentTimestamp()
                }
            }
            return
        }

        if (!fileMgr.exists(cachePath)) {
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    job.status = "failed"
                    job.message = "cache file missing"
                    job.updatedAt = currentTimestamp()
                    job.cacheAvailable = false
                }
            }
            return
        }

        var delivered = false
        var message = "delivered"
        try {
            let payload = fileMgr.readBytes(cachePath)
            if (let Some(h) <- handler) {
                delivered = h(targetDevice, targetPath, payload)
            }
            if (!delivered) {
                message = "dispatch write failed"
            }
        } catch (e: Exception) {
            delivered = false
            message = "dispatch error: ${e.message}"
        }

        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                job.updatedAt = currentTimestamp()
                if (delivered) {
                    job.status = "delivered"
                    job.message = "delivered from ${sourceDevice}"
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    job.cacheAvailable = false
                } else {
                    job.status = "cached"
                    job.message = message
                    refreshCacheState(job)
                }
            }
        }
    }

    func isDeviceOnline(deviceId: String): Bool {
        synchronized(mutex) {
            if (let Some(checker) <- onlineChecker) {
                return checker(deviceId)
            }
        }
        false
    }

    func isWhitelisted(sourceDevice: String, targetDevice: String): Bool {
        synchronized(mutex) {
            let exactKey = "${sourceDevice}->${targetDevice}"
            if (let Some(rule) <- whitelist.get(exactKey)) {
                return rule.enabled
            }
            let wildcardKey = "*->${targetDevice}"
            if (let Some(rule) <- whitelist.get(wildcardKey)) {
                return rule.enabled
            }
        }
        false
    }

    func loadWhitelist(): Unit {
        let values = whitelistStore.load()
        synchronized(mutex) {
            whitelist = HashMap<String, WhitelistRule>()
            var idx: Int64 = 0
            while (true) {
                let key = "rule_${idx}"
                if (let Some(raw) <- values.get(key)) {
                    match (parseWhitelistLine(raw)) {
                        case Some(rule) => whitelist.add(rule.key(), rule)
                        case None => ()
                    }
                    idx += 1
                    continue
                }
                break
            }
        }
    }

    func persistWhitelist(): Unit {
        let values = HashMap<String, String>()
        var idx: Int64 = 0
        for ((_, rule) in whitelist) {
            values.add("rule_${idx}", encodeWhitelistLine(rule))
            idx += 1
        }
        whitelistStore.save(values)
    }

    func enforceCapacity(): Unit {
        let used = currentCacheBytes()
        let limit = calcLimitBytes()
        if (limit <= 0 || used <= limit) {
            return
        }

        var remaining = used
        while (remaining > limit) {
            let oldest = findOldestActiveJobId()
            if (oldest.size == 0) {
                break
            }
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(oldest)) {
                    job.status = "expired"
                    job.message = "evicted by cache limit"
                    job.updatedAt = currentTimestamp()
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    job.cacheAvailable = false
                    remaining -= job.bytes
                }
            }
        }
    }

    func currentCacheBytes(): Int64 {
        var total: Int64 = 0
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.status == "delivered" || job.status == "expired") {
                    continue
                }
                if (fileMgr.exists(job.cachePath)) {
                    total += job.bytes
                }
            }
        }
        total
    }

    func findOldestActiveJobId(): String {
        var selectedId = ""
        var selectedAt: Int64 = currentTimestamp() + 86400 * 365
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (job.status == "delivered" || job.status == "expired") {
                    continue
                }
                if (!fileMgr.exists(job.cachePath)) {
                    continue
                }
                if (job.createdAt < selectedAt) {
                    selectedAt = job.createdAt
                    selectedId = id
                }
            }
        }
        selectedId
    }

    func calcLimitBytes(): Int64 {
        if (limitMode == "percent") {
            let snap = diskProbe.snapshot(cacheDir)
            let computed = snap.totalBytes * limitPercent / 100
            if (computed > 0) {
                return computed
            }
        }
        limitBytes
    }
}

func refreshCacheState(job: RelayJob): Unit {
    if (job.status == "delivered" || job.status == "expired") {
        job.cacheAvailable = false
        return
    }
    let fileMgr = LocalFileMgr()
    job.cacheAvailable = fileMgr.exists(job.cachePath)
}

func canAccessCache(job: RelayJob): Bool {
    if (job.status == "delivered" || job.status == "expired") {
        return false
    }
    job.cacheAvailable
}

func normalizeRelayPath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) { out = "/" }
    if (!strStartsWith(out, "/")) {
        out = "/" + out
    }
    while (strContains(out, "//")) {
        out = strReplace(out, "//", "/")
    }
    out
}

func normalizeRelayTextRecordName(raw: String): String {
    let trimmed = raw.trimAscii()
    var base = if (trimmed.size > 0) { normalizeFileName(trimmed) } else { "tmpTXT-${currentTimestamp() * 1000}.txt" }
    let lower = base.toLower()
    if (!strEndsWith(lower, ".txt")) {
        base += ".txt"
    }
    base
}

func normalizeRelayTextTargetPath(path: String): String {
    let normalized = normalizeRelayPath(path)
    if (normalized == "/") {
        return "/tmpSL"
    }
    normalized
}

func normalizeFileName(name: String): String {
    var out = name.trimAscii()
    if (out.size == 0) {
        out = "payload.bin"
    }
    out = strReplace(out, "/", "_")
    out = strReplace(out, "\\", "_")
    out
}

func composeRelayTargetFilePath(targetPath: String, fileName: String): String {
    let normalizedPath = normalizeRelayPath(targetPath)
    let normalizedFileName = normalizeFileName(fileName)
    if (normalizedPath == "/") {
        return "/" + normalizedFileName
    }
    if (strEndsWith(normalizedPath, "/" + normalizedFileName)) {
        return normalizedPath
    }
    normalizedPath + "/" + normalizedFileName
}

func normalizeLimitMode(raw: String): String {
    if (raw.toLower() == "percent") {
        return "percent"
    }
    "fixed"
}

func encodeWhitelistLine(rule: WhitelistRule): String {
    let source = strReplace(rule.sourceDevice, "|", "_")
    let target = strReplace(rule.targetDevice, "|", "_")
    let enabled = if (rule.enabled) { "true" } else { "false" }
    "${source}|${target}|${enabled}|${rule.createdAt}"
}

func parseWhitelistLine(raw: String): ?WhitelistRule {
    let parts = splitWhitelist(raw)
    if (parts.size < 3) {
        return None
    }
    let rule = WhitelistRule()
    rule.sourceDevice = if (parts[0].size > 0) { parts[0] } else { "*" }
    rule.targetDevice = parts[1]
    rule.enabled = parts[2] == "true"
    if (parts.size > 3) {
        try {
            rule.createdAt = Int64.parse(parts[3])
        } catch (_: Exception) {
            rule.createdAt = currentTimestamp()
        }
    } else {
        rule.createdAt = currentTimestamp()
    }
    if (rule.targetDevice.size == 0) {
        return None
    }
    Some(rule)
}

func splitWhitelist(raw: String): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    for (ch in raw.toRuneArray()) {
        if (ch == r'|') {
            out.add(current)
            current = ""
            continue
        }
        current += ch.toString()
    }
    out.add(current)
    out
}

func shouldCleanupStatus(statusFilter: String, status: String): Bool {
    if (statusFilter.size > 0 && statusFilter != "all") {
        return status == statusFilter
    }
    status == "delivered" || status == "expired" || status == "failed"
}
