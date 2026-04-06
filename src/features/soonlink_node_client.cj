package soonlnk.features

import ignite.client.{MultipartFile, RestClient}
import soonlnk.commons.*
import std.collection.ArrayList
import std.convert.*
import std.unicode.*

public class SoonLinkNodeClient {
    let client: RestClient

    public init(host: String, port: Int64, scheme!: String = "http", basePath!: String = "") {
        let baseUrl = buildSoonLinkNodeBaseUrl(host, port, scheme, basePath)
        this.client = RestClient(
            readTimeout: Duration.second * 15,
            writeTimeout: Duration.second * 15,
            poolSize: 4
        ).withBaseUrl(baseUrl)
    }

    public func close(): Unit {
        client.close()
    }

    public func listDir(path: String): ArrayList<FileEntry> {
        let normalizedPath = normalizeNodePath(path)
        let resp = client.get("/api/fs/list?device=local&path=${urlEncodeNodeQuery(normalizedPath)}")
        if (!resp.isOk()) {
            return ArrayList<FileEntry>()
        }

        let body = resp.body()
        let files = ArrayList<FileEntry>()
        let rawObjects = extractJsonArrayObjectsNode(body, "files")
        for (raw in rawObjects) {
            let entry = FileEntry()
            entry.name = parseJsonString(raw, "name") ?? ""
            entry.path = parseJsonString(raw, "path") ?? ""
            entry.mimeType = parseJsonString(raw, "mimeType") ?? ""
            entry.isDir = parseJsonBoolNode(raw, "isDir")
            entry.size = parseJsonIntNode(raw, "size")
            entry.modified = parseJsonIntNode(raw, "modified")
            files.add(entry)
        }
        files
    }

    public func getFileInfo(path: String): ?FileMetadata {
        let normalizedPath = normalizeNodePath(path)
        let resp = client.get("/api/fs/info?device=local&path=${urlEncodeNodeQuery(normalizedPath)}")
        if (!resp.isOk()) {
            return None
        }

        let body = resp.body()
        if ((parseJsonString(body, "error") ?? "").size > 0) {
            return None
        }

        let info = FileMetadata()
        info.name = parseJsonString(body, "name") ?? extractNodeBaseName(normalizedPath)
        info.path = parseJsonString(body, "path") ?? normalizedPath
        info.mimeType = parseJsonString(body, "mimeType") ?? ""
        info.checksum = parseJsonString(body, "checksum") ?? ""
        info.isDir = parseJsonBoolNode(body, "isDir")
        info.encrypted = parseJsonBoolNode(body, "encrypted")
        info.size = parseJsonIntNode(body, "size")
        info.modified = parseJsonIntNode(body, "modified")
        Some(info)
    }

    public func createDir(path: String): Bool {
        let normalizedPath = normalizeNodePath(path)
        let payload = JsonObject()
            .put("device", "local")
            .put("path", normalizedPath)
            .toString()
        let resp = client.postJson("/api/fs/dirs", payload)
        if (!resp.isOk()) {
            return false
        }
        (parseJsonString(resp.body(), "success") ?? "false") == "true"
    }

    public func readRange(path: String, offset: Int64, length: Int64): Array<UInt8> {
        let normalizedPath = normalizeNodePath(path)
        if (length <= 0) {
            return Array<UInt8>(0, repeat: 0)
        }

        let end = offset + length - 1
        let resp = client.request()
            .method("GET")
            .url("/api/fs/download?device=local&path=${urlEncodeNodeQuery(normalizedPath)}")
            .header("range", "bytes=${offset}-${end}")
            .send()
        if (!resp.isOk() && Int64(resp.status) != 206) {
            throw Exception("remote read failed: ${resp.status}")
        }
        resp.bodyBytes()
    }

    public func uploadFile(
        sourceDevice: String,
        finalPath: String,
        fileSize: Int64,
        chunkSize: Int64,
        readChunk: (Int64, Int64) -> Array<UInt8>
    ): Bool {
        let normalizedPath = normalizeNodePath(finalPath)
        let fileName = extractNodeBaseName(normalizedPath)
        let effectiveChunkSize = if (chunkSize > 0) { chunkSize } else { 2 * 1024 * 1024 }
        let createPayload = JsonObject()
            .put("sourceDevice", sourceDevice)
            .put("targetDevice", "local")
            .put("targetPath", normalizedPath)
            .put("fileName", fileName)
            .putInt("fileSize", if (fileSize > 0) { fileSize } else { 0 })
            .putInt("chunkSize", effectiveChunkSize)
            .toString()
        let createResp = client.postJson("/api/transfer/chunk/session", createPayload)
        if (!createResp.isOk()) {
            return false
        }

        let sessionBody = createResp.body()
        if ((parseJsonString(sessionBody, "success") ?? "false") != "true") {
            return false
        }
        let sessionId = parseJsonString(sessionBody, "id") ?? ""
        if (sessionId.size == 0) {
            return false
        }

        var offset: Int64 = 0
        var index: Int64 = 0
        let totalSize = if (fileSize > 0) { fileSize } else { 0 }
        while (offset < totalSize) {
            let nextSize = if (totalSize - offset > effectiveChunkSize) {
                effectiveChunkSize
            } else {
                totalSize - offset
            }
            let payload = readChunk(offset, nextSize)
            if (payload.size <= 0 && nextSize > 0) {
                return false
            }

            let fields = ArrayList<(String, String)>()
            let files = ArrayList<MultipartFile>()
            files.add(MultipartFile("chunk", "chunk_${index}.part", "application/octet-stream", payload))
            let chunkResp = client.request()
                .method("PUT")
                .url("/api/transfer/chunk/session/${sessionId}/chunks/${index}")
                .multipart(fields, files)
                .send()
            if (!chunkResp.isOk()) {
                return false
            }
            if ((parseJsonString(chunkResp.body(), "success") ?? "false") != "true") {
                return false
            }

            offset += payload.size
            index += 1
        }

        let completeResp = client.postJson("/api/transfer/chunk/session/${sessionId}/complete", "{}")
        if (!completeResp.isOk()) {
            return false
        }
        (parseJsonString(completeResp.body(), "success") ?? "false") == "true"
    }
}

public func buildSoonLinkNodeBaseUrl(host: String, port: Int64, scheme: String, basePath: String): String {
    let normalizedScheme = normalizeEndpointScheme(scheme)
    let effectiveScheme = if (normalizedScheme.size > 0) { normalizedScheme } else { "http" }
    let normalizedHost = host.trimAscii()
    let normalizedBasePath = normalizeEndpointBasePath(basePath)
    if (port > 0) {
        return "${effectiveScheme}://${normalizedHost}:${port}${normalizedBasePath}"
    }
    "${effectiveScheme}://${normalizedHost}${normalizedBasePath}"
}

func normalizeNodePath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) {
        out = "/"
    }
    if (!strStartsWithNode(out, "/")) {
        out = "/" + out
    }
    while (strContains(out, "//")) {
        out = strReplace(out, "//", "/")
    }
    if (out.size > 1 && strEndsWithNode(out, "/")) {
        out = strSubstring(out, 0, out.size - 1)
    }
    out
}

func extractNodeBaseName(path: String): String {
    let normalized = normalizeNodePath(path)
    if (normalized == "/") {
        return "root"
    }
    let runes = normalized.toRuneArray()
    var slashAt: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'/') {
            slashAt = i
        }
    }
    if (slashAt < 0 || slashAt >= normalized.size - 1) {
        return normalized
    }
    strSubstring(normalized, slashAt + 1, normalized.size)
}

func parseJsonIntNode(json: String, field: String): Int64 {
    let raw = parseJsonString(json, field) ?? "0"
    try {
        Int64.parse(raw.trimAscii())
    } catch (_: Exception) {
        0
    }
}

func parseJsonBoolNode(json: String, field: String): Bool {
    (parseJsonString(json, field) ?? "false").trimAscii().toLower() == "true"
}

func strStartsWithNode(text: String, prefix: String): Bool {
    if (text.size < prefix.size) {
        return false
    }
    let textRunes = text.toRuneArray()
    let prefixRunes = prefix.toRuneArray()
    for (i in 0..prefixRunes.size) {
        if (textRunes[i] != prefixRunes[i]) {
            return false
        }
    }
    true
}

func strEndsWithNode(text: String, suffix: String): Bool {
    if (text.size < suffix.size) {
        return false
    }
    let textRunes = text.toRuneArray()
    let suffixRunes = suffix.toRuneArray()
    let start = textRunes.size - suffixRunes.size
    for (i in 0..suffixRunes.size) {
        if (textRunes[start + i] != suffixRunes[i]) {
            return false
        }
    }
    true
}

func urlEncodeNodeQuery(input: String): String {
    let out = ArrayList<UInt8>()
    for (b in input.toArray()) {
        if (isNodeSafeQueryByte(UInt8(b))) {
            out.add(UInt8(b))
            continue
        }
        if (b == 32) {
            out.add(UInt8(43))
            continue
        }
        let byteValue = Int64(b)
        let high = UInt8(byteValue / 16)
        let low = UInt8(byteValue % 16)
        let encoded = "%${hexNodeDigit(high)}${hexNodeDigit(low)}".toArray()
        for (c in encoded) {
            out.add(UInt8(c))
        }
    }
    String.fromUtf8(out.toArray())
}

func isNodeSafeQueryByte(b: UInt8): Bool {
    (b >= 48 && b <= 57) ||
    (b >= 65 && b <= 90) ||
    (b >= 97 && b <= 122) ||
    b == 45 || b == 46 || b == 95 || b == 126 || b == 47
}

func hexNodeDigit(v: UInt8): String {
    match (v) {
        case 0 => "0"
        case 1 => "1"
        case 2 => "2"
        case 3 => "3"
        case 4 => "4"
        case 5 => "5"
        case 6 => "6"
        case 7 => "7"
        case 8 => "8"
        case 9 => "9"
        case 10 => "A"
        case 11 => "B"
        case 12 => "C"
        case 13 => "D"
        case 14 => "E"
        case _ => "F"
    }
}

func extractJsonArrayObjectsNode(json: String, field: String): ArrayList<String> {
    let out = ArrayList<String>()
    let fieldKey = "\"${field}\""
    let runes = json.toRuneArray()
    let keyRunes = fieldKey.toRuneArray()
    var startAt: Int64 = -1
    var i: Int64 = 0
    while (i <= runes.size - keyRunes.size) {
        var matched = true
        var j: Int64 = 0
        while (j < keyRunes.size) {
            if (runes[i + j] != keyRunes[j]) {
                matched = false
                break
            }
            j += 1
        }
        if (matched) {
            startAt = i + keyRunes.size
            break
        }
        i += 1
    }
    if (startAt < 0) {
        return out
    }

    var cursor = startAt
    while (cursor < runes.size && runes[cursor] != r'[') {
        cursor += 1
    }
    if (cursor >= runes.size) {
        return out
    }
    cursor += 1

    var depth: Int64 = 0
    var objectStart: Int64 = -1
    while (cursor < runes.size) {
        if (runes[cursor] == r'{') {
            if (depth == 0) {
                objectStart = cursor
            }
            depth += 1
        } else if (runes[cursor] == r'}') {
            depth -= 1
            if (depth == 0 && objectStart >= 0) {
                out.add(strSubstring(json, objectStart, cursor + 1))
                objectStart = -1
            }
        } else if (runes[cursor] == r']' && depth == 0) {
            break
        }
        cursor += 1
    }
    out
}
