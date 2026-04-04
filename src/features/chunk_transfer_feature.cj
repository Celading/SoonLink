package soonlnk.features

import soonlnk.commons.*
import std.collection.{ArrayList, HashMap}
import std.fs.{Directory, FileInfo, remove}
import std.sync.Mutex

public class ChunkSession {
    public var id: String = ""
    public var sourceDevice: String = ""
    public var targetDevice: String = ""
    public var targetPath: String = "/"
    public var fileName: String = ""
    public var fileSize: Int64 = 0
    public var chunkSize: Int64 = 2 * 1024 * 1024
    public var totalChunks: Int64 = 0
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0
    public var status: String = "created"
    public var tempDir: String = ""

    public init() {}

    public func toJson(receivedChunks: Int64): JsonObject {
        JsonObject()
            .put("id", id)
            .put("sourceDevice", sourceDevice)
            .put("targetDevice", targetDevice)
            .put("targetPath", targetPath)
            .put("fileName", fileName)
            .putInt("fileSize", fileSize)
            .putInt("chunkSize", chunkSize)
            .putInt("totalChunks", totalChunks)
            .putInt("receivedChunks", receivedChunks)
            .put("status", status)
            .putInt("createdAt", createdAt)
            .putInt("updatedAt", updatedAt)
    }
}

public class ChunkWriteResult {
    public var success: Bool = false
    public var message: String = ""
    public var receivedChunks: Int64 = 0
    public var totalChunks: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .putBool("success", success)
            .put("message", message)
            .putInt("receivedChunks", receivedChunks)
            .putInt("totalChunks", totalChunks)
    }
}

public class ChunkCompleteResult {
    public var success: Bool = false
    public var message: String = ""
    public var fileId: String = ""
    public var targetPath: String = ""
    public var bytesWritten: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .putBool("success", success)
            .put("message", message)
            .put("fileId", fileId)
            .put("targetPath", targetPath)
            .putInt("bytesWritten", bytesWritten)
    }
}

public class ChunkTransferFeature {
    let tempDir: String
    let fileMgr: FileMgr
    let mutex: Mutex = Mutex()

    var sessions: HashMap<String, ChunkSession> = HashMap<String, ChunkSession>()
    var receivedMap: HashMap<String, HashMap<String, Bool>> = HashMap<String, HashMap<String, Bool>>()
    var writeHandler: ?(String, String, Array<UInt8>, Int64) -> Bool = None

    public init(tempDir: String) {
        this.tempDir = joinPaths(tempDir, "chunk_sessions")
        this.fileMgr = LocalFileMgr()
        fileMgr.ensureDir(this.tempDir)
    }

    public func setWriteHandler(handler: (String, String, Array<UInt8>, Int64) -> Bool): Unit {
        synchronized(mutex) {
            writeHandler = handler
        }
    }

    public func createSession(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        fileSize: Int64,
        chunkSize: Int64
    ): ChunkSession {
        let session = ChunkSession()
        session.id = "chunk-" + generateId()
        session.sourceDevice = sourceDevice
        session.targetDevice = targetDevice
        session.targetPath = normalizeChunkPath(targetPath)
        session.fileName = normalizeChunkFileName(fileName)
        session.fileSize = if (fileSize > 0) { fileSize } else { 0 }
        session.chunkSize = if (chunkSize > 0) { chunkSize } else { 2 * 1024 * 1024 }
        session.totalChunks = if (session.fileSize > 0) {
            (session.fileSize + session.chunkSize - 1) / session.chunkSize
        } else {
            0
        }
        session.createdAt = currentTimestamp()
        session.updatedAt = session.createdAt
        session.status = "created"
        session.tempDir = joinPaths(tempDir, session.id)

        fileMgr.ensureDir(session.tempDir)

        synchronized(mutex) {
            sessions.add(session.id, session)
            receivedMap.add(session.id, HashMap<String, Bool>())
        }
        session
    }

    public func writeChunk(sessionId: String, index: Int64, payload: Array<UInt8>): ChunkWriteResult {
        let result = ChunkWriteResult()
        if (index < 0) {
            result.success = false
            result.message = "invalid chunk index"
            return result
        }

        var chunkPath = ""
        synchronized(mutex) {
            if (let Some(session) <- sessions.get(sessionId)) {
                chunkPath = chunkFilePath(session, index)
            }
        }
        if (chunkPath.size == 0) {
            result.success = false
            result.message = "session not found"
            return result
        }

        try {
            fileMgr.writeBytes(chunkPath, payload, false)
            synchronized(mutex) {
                if (let Some(flags) <- receivedMap.get(sessionId)) {
                    flags.add("${index}", true)
                    result.receivedChunks = flags.size
                }
                if (let Some(session) <- sessions.get(sessionId)) {
                    session.updatedAt = currentTimestamp()
                    session.status = "uploading"
                    result.totalChunks = session.totalChunks
                }
            }
            result.success = true
            result.message = "chunk stored"
        } catch (e: Exception) {
            result.success = false
            result.message = "write chunk failed: ${e.message}"
        }
        result
    }

    public func sessionManifest(sessionId: String): JsonObject {
        synchronized(mutex) {
            if (let Some(session) <- sessions.get(sessionId)) {
                let flags = receivedMap.get(sessionId) ?? HashMap<String, Bool>()
                let received = JsonArray()
                for ((idx, ok) in flags) {
                    if (ok) {
                        received.addStr(idx)
                    }
                }

                let missing = JsonArray()
                if (session.totalChunks > 0) {
                    var i: Int64 = 0
                    while (i < session.totalChunks) {
                        if (!(flags.get("${i}") ?? false)) {
                            missing.addInt(i)
                        }
                        i += 1
                    }
                }

                return JsonObject()
                    .putBool("success", true)
                    .putObj("session", session.toJson(flags.size))
                    .putArr("receivedChunks", received)
                    .putArr("missingChunks", missing)
            }
        }
        JsonObject()
            .putBool("success", false)
            .put("error", "session not found")
    }

    public func completeSession(sessionId: String): ChunkCompleteResult {
        let result = ChunkCompleteResult()
        var session: ?ChunkSession = None
        var flags: HashMap<String, Bool> = HashMap<String, Bool>()
        var handler: ?(String, String, Array<UInt8>, Int64) -> Bool = None
        var hasSession = false
        var hasHandler = false

        synchronized(mutex) {
            match (sessions.get(sessionId)) {
                case Some(s) =>
                    session = Some(s)
                    hasSession = true
                case None => ()
            }
            flags = receivedMap.get(sessionId) ?? HashMap<String, Bool>()
            match (writeHandler) {
                case Some(h) =>
                    handler = Some(h)
                    hasHandler = true
                case None => ()
            }
        }

        if (!hasSession) {
            result.success = false
            result.message = "session not found"
            return result
        }

        if (!hasHandler) {
            result.success = false
            result.message = "write handler unavailable"
            return result
        }

        if (let Some(s) <- session) {
            if (s.totalChunks > 0) {
                var i: Int64 = 0
                while (i < s.totalChunks) {
                    if (!(flags.get("${i}") ?? false)) {
                        result.success = false
                        result.message = "missing chunk ${i}"
                        return result
                    }
                    i += 1
                }
            }

            var offset: Int64 = 0
            var index: Int64 = 0
            if (s.totalChunks == 0) {
                if (let Some(w) <- handler) {
                    let finalPath = composeChunkTargetFilePath(s.targetPath, s.fileName)
                    if (!w(s.targetDevice, finalPath, Array<UInt8>(0, repeat: 0), 0)) {
                        result.success = false
                        result.message = "target write failed at empty file"
                        return result
                    }
                }
            }
            while (true) {
                let chunkPath = chunkFilePath(s, index)
                if (!fileMgr.exists(chunkPath)) {
                    if (s.totalChunks == 0) {
                        break
                    }
                    if (index >= s.totalChunks) {
                        break
                    }
                    result.success = false
                    result.message = "chunk file not found: ${index}"
                    return result
                }

                let payload = fileMgr.readBytes(chunkPath)
                if (payload.size == 0 && index > 0) {
                    if (s.totalChunks == 0) { break }
                }

                var written = false
                if (let Some(w) <- handler) {
                    let finalPath = composeChunkTargetFilePath(s.targetPath, s.fileName)
                    written = w(s.targetDevice, finalPath, payload, offset)
                }
                if (!written) {
                    result.success = false
                    result.message = "target write failed at chunk ${index}"
                    return result
                }

                offset += payload.size
                index += 1
                if (s.totalChunks > 0 && index >= s.totalChunks) {
                    break
                }
            }

            let finalPath = composeChunkTargetFilePath(s.targetPath, s.fileName)
            result.success = true
            result.message = "merge completed"
            result.fileId = encodeChunkFileId(s.targetDevice, finalPath)
            result.targetPath = finalPath
            result.bytesWritten = offset

            synchronized(mutex) {
                if (let Some(inner) <- sessions.get(sessionId)) {
                    inner.status = "completed"
                    inner.updatedAt = currentTimestamp()
                }
                sessions.remove(sessionId)
                receivedMap.remove(sessionId)
            }
            removeDirRecursive(s.tempDir)
        }
        result
    }
}

public func encodeChunkFileId(deviceId: String, path: String): String {
    "${deviceId}|${strReplace(path, "/", "~")}"
}

public func decodeChunkFileId(fileId: String): ?(String, String) {
    let normalizedFileId = percentDecodeSafe(fileId)
    let runes = normalizedFileId.toRuneArray()
    var splitAt: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'|') {
            splitAt = i
            break
        }
    }
    if (splitAt <= 0 || splitAt >= runes.size - 1) {
        return None
    }
    let deviceId = strSubstring(normalizedFileId, 0, splitAt)
    let rawPath = strSubstring(normalizedFileId, splitAt + 1, runes.size)
    let path = strReplace(rawPath, "~", "/")
    if (deviceId.size == 0 || path.size == 0) {
        return None
    }
    Some((deviceId, path))
}

func percentDecodeSafe(raw: String): String {
    if (!strContains(raw, "%")) {
        return raw
    }
    let runes = raw.toRuneArray()
    let out = ArrayList<UInt8>()
    var i: Int64 = 0
    while (i < runes.size) {
        if (runes[i] == r'%' && i + 2 < runes.size) {
            let hi = hexNibble(runes[i + 1])
            let lo = hexNibble(runes[i + 2])
            if (hi >= 0 && lo >= 0) {
                out.add(UInt8(hi * 16 + lo))
                i += 3
                continue
            }
        }

        let charBytes = runes[i].toString().toArray()
        for (b in charBytes) {
            out.add(UInt8(b))
        }
        i += 1
    }
    String.fromUtf8(out.toArray())
}

func hexNibble(ch: Rune): Int64 {
    match (ch) {
        case r'0' => 0
        case r'1' => 1
        case r'2' => 2
        case r'3' => 3
        case r'4' => 4
        case r'5' => 5
        case r'6' => 6
        case r'7' => 7
        case r'8' => 8
        case r'9' => 9
        case r'a' => 10
        case r'b' => 11
        case r'c' => 12
        case r'd' => 13
        case r'e' => 14
        case r'f' => 15
        case r'A' => 10
        case r'B' => 11
        case r'C' => 12
        case r'D' => 13
        case r'E' => 14
        case r'F' => 15
        case _ => -1
    }
}

func normalizeChunkPath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) { out = "/" }
    if (!strStartsWith(out, "/")) {
        out = "/" + out
    }
    while (strContains(out, "//")) {
        out = strReplace(out, "//", "/")
    }
    if (out.size > 1 && strEndsWith(out, "/")) {
        out = strSubstring(out, 0, out.size - 1)
    }
    out
}

func normalizeChunkFileName(name: String): String {
    var out = name.trimAscii()
    if (out.size == 0) {
        out = "upload.bin"
    }
    out = strReplace(out, "/", "_")
    out = strReplace(out, "\\", "_")
    out
}

func composeChunkTargetFilePath(targetPath: String, fileName: String): String {
    let path = normalizeChunkPath(targetPath)
    let normalizedFileName = normalizeChunkFileName(fileName)
    if (path == "/") {
        return "/" + normalizedFileName
    }
    if (isChunkExplicitFilePath(path, normalizedFileName)) {
        return path
    }
    path + "/" + normalizedFileName
}

func isChunkExplicitFilePath(path: String, fileName: String): Bool {
    if (path.size == 0 || fileName.size == 0) {
        return false
    }
    strEndsWith(path, "/" + fileName)
}

func chunkFilePath(session: ChunkSession, index: Int64): String {
    joinPaths(session.tempDir, "chunk_${index}.part")
}

func removeDirRecursive(dirPath: String): Unit {
    try {
        let entries = Directory.readFrom(dirPath)
        for (entry in entries) {
            let path = entry.path.toString()
            if (entry.isDirectory()) {
                removeDirRecursive(path)
            } else {
                try {
                    remove(path)
                } catch (_: Exception) {}
            }
        }
        remove(dirPath)
    } catch (_: Exception) {}
}
