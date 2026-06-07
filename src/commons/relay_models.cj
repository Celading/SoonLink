package soonlnk.commons

import std.collection.ArrayList
import std.convert.*
import std.unicode.*

public class RelayJob {
    public var id: String = ""
    public var recordKind: String = "file"
    public var sessionId: String = ""
    public var sourceDevice: String = ""
    public var targetDevice: String = ""
    public var targetPath: String = "/"
    public var fileName: String = ""
    public var cachePath: String = ""
    public var cacheAvailable: Bool = false
    public var bytes: Int64 = 0
    public var status: String = "queued"
    public var attempts: Int64 = 0
    public var message: String = ""
    public var sourceProtocolId: String = ""
    public var sourcePeerId: String = ""
    public var sourceEndpoint: String = ""
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0
    public var expiresAt: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("id", id)
            .put("recordKind", recordKind)
            .put("sessionId", sessionId)
            .put("sourceDevice", sourceDevice)
            .put("targetDevice", targetDevice)
            .put("targetPath", targetPath)
            .put("fileName", fileName)
            .putBool("cacheAvailable", cacheAvailable)
            .putInt("bytes", bytes)
            .put("bytesText", formatBytes(bytes))
            .put("status", status)
            .putInt("attempts", attempts)
            .put("message", message)
            .put("sourceProtocolId", sourceProtocolId)
            .put("sourcePeerId", sourcePeerId)
            .put("sourceEndpoint", sourceEndpoint)
            .putInt("createdAt", createdAt)
            .putInt("updatedAt", updatedAt)
            .putInt("expiresAt", expiresAt)
    }
}

public class RelayIdentity {
    public var identityId: String = ""
    public var kind: String = "manual"
    public var displayName: String = ""
    public var nodeId: String = ""
    public var deviceId: String = ""
    public var protocolId: String = ""
    public var endpoint: String = ""
    public var trustedState: String = "unknown"
    public var lastSeenAt: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("identityId", identityId)
            .put("kind", kind)
            .put("displayName", displayName)
            .put("nodeId", nodeId)
            .put("deviceId", deviceId)
            .put("protocolId", protocolId)
            .put("endpoint", endpoint)
            .put("trustedState", trustedState)
            .putInt("lastSeenAt", lastSeenAt)
    }
}

public class RelayRoom {
    public var roomId: String = ""
    public var title: String = ""
    public var kind: String = "manual-room"
    public var participantIdentityIds: ArrayList<String> = ArrayList<String>()
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0
    public var retentionPolicy: String = ""
    public var transportHints: String = ""

    public init() {}

    public func toJson(): JsonObject {
        let participants = JsonArray()
        for (id in participantIdentityIds) {
            participants.addStr(id)
        }
        JsonObject()
            .put("roomId", roomId)
            .put("title", title)
            .put("kind", kind)
            .putArr("participantIdentityIds", participants)
            .putInt("createdAt", createdAt)
            .putInt("updatedAt", updatedAt)
            .put("retentionPolicy", retentionPolicy)
            .put("transportHints", transportHints)
    }
}

public class RelayMessage {
    public var messageId: String = ""
    public var roomId: String = ""
    public var senderIdentityId: String = ""
    public var senderKind: String = "manual"
    public var body: String = ""
    public var contentType: String = "text/plain"
    public var fileRefs: ArrayList<String> = ArrayList<String>()
    public var createdAt: Int64 = 0
    public var deliveryState: String = "local"
    public var sourceProtocolId: String = ""
    public var sourceRecordId: String = ""

    public init() {}

    public func toJson(): JsonObject {
        let refs = JsonArray()
        for (ref in fileRefs) {
            refs.addStr(ref)
        }
        JsonObject()
            .put("messageId", messageId)
            .put("roomId", roomId)
            .put("senderIdentityId", senderIdentityId)
            .put("senderKind", senderKind)
            .put("body", body)
            .put("contentType", contentType)
            .putArr("fileRefs", refs)
            .putInt("createdAt", createdAt)
            .put("deliveryState", deliveryState)
            .put("sourceProtocolId", sourceProtocolId)
            .put("sourceRecordId", sourceRecordId)
    }
}

public class ChannelAdapter {
    public var protocolId: String = ""
    public var displayName: String = ""
    public var trustShape: String = "manual"
    public var receiveMode: String = "pull-or-ingress"
    public var roomKind: String = "protocol-room"
    public var capabilities: ArrayList<String> = ArrayList<String>()
    public var contentTypes: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func toJson(): JsonObject {
        let caps = JsonArray()
        for (capability in capabilities) {
            caps.addStr(capability)
        }
        let types = JsonArray()
        for (contentType in contentTypes) {
            types.addStr(contentType)
        }
        JsonObject()
            .put("protocolId", protocolId)
            .put("displayName", displayName)
            .put("trustShape", trustShape)
            .put("receiveMode", receiveMode)
            .put("roomKind", roomKind)
            .putArr("capabilities", caps)
            .putArr("contentTypes", types)
    }
}

public class ChannelAdapterMessage {
    public var protocolId: String = ""
    public var peerId: String = ""
    public var peerDisplayName: String = ""
    public var endpoint: String = ""
    public var body: String = ""
    public var contentType: String = "text/plain"
    public var sourceRecordId: String = ""
    public var createdAt: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("protocolId", protocolId)
            .put("peerId", peerId)
            .put("peerDisplayName", peerDisplayName)
            .put("endpoint", endpoint)
            .put("body", body)
            .put("contentType", contentType)
            .put("sourceRecordId", sourceRecordId)
            .putInt("createdAt", createdAt)
    }
}

public class LocalSendPeerInfo {
    public var peerId: String = ""
    public var alias: String = ""
    public var version: String = ""
    public var deviceModel: String = ""
    public var deviceType: String = ""
    public var fingerprint: String = ""
    public var download: Bool = false
    public var endpoint: String = ""
    public var apiVersion: String = "v2"

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("peerId", peerId)
            .put("alias", alias)
            .put("version", version)
            .put("deviceModel", deviceModel)
            .put("deviceType", deviceType)
            .put("fingerprint", fingerprint)
            .putBool("download", download)
            .put("endpoint", endpoint)
            .put("apiVersion", apiVersion)
    }
}

public class LocalSendFileOffer {
    public var fileId: String = ""
    public var fileName: String = ""
    public var size: Int64 = 0
    public var fileType: String = "application/octet-stream"
    public var sha256: String = ""

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("id", fileId)
            .put("fileName", fileName)
            .putInt("size", size)
            .put("fileType", fileType)
            .put("sha256", sha256)
    }
}

public class LocalSendFileToken {
    public var fileId: String = ""
    public var token: String = ""
    public var fileName: String = ""
    public var size: Int64 = 0
    public var jobId: String = ""

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("fileId", fileId)
            .put("token", token)
            .put("fileName", fileName)
            .putInt("size", size)
            .put("jobId", jobId)
    }
}

public class LocalSendSession {
    public var sessionId: String = ""
    public var peerId: String = ""
    public var peerDisplayName: String = ""
    public var endpoint: String = ""
    public var createdAt: Int64 = 0
    public var acceptPolicy: String = "manual"
    public var defaultSaveDir: String = "/tmpSL"
    public var autoSave: Bool = false
    public var tokens: ArrayList<LocalSendFileToken> = ArrayList<LocalSendFileToken>()

    public init() {}

    public func toPrepareUploadJson(): JsonObject {
        let files = JsonObject()
        for (token in tokens) {
            files.put(token.fileId, token.token)
        }
        JsonObject()
            .put("sessionId", sessionId)
            .putObj("files", files)
    }

    public func toJson(): JsonObject {
        let arr = JsonArray()
        for (token in tokens) {
            arr.addObj(token.toJson())
        }
        JsonObject()
            .put("sessionId", sessionId)
            .put("peerId", peerId)
            .put("peerDisplayName", peerDisplayName)
            .put("endpoint", endpoint)
            .putInt("createdAt", createdAt)
            .put("acceptPolicy", acceptPolicy)
            .put("defaultSaveDir", defaultSaveDir)
            .putBool("autoSave", autoSave)
            .putArr("files", arr)
    }
}

public class LocalSendOutboundResult {
    public var success: Bool = false
    public var remoteEndpoint: String = ""
    public var jobId: String = ""
    public var fileId: String = ""
    public var sessionId: String = ""
    public var token: String = ""
    public var statusCode: Int64 = 0
    public var responseBody: String = ""
    public var message: String = ""

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .putBool("success", success)
            .put("remoteEndpoint", remoteEndpoint)
            .put("jobId", jobId)
            .put("fileId", fileId)
            .put("sessionId", sessionId)
            .put("token", token)
            .putInt("statusCode", statusCode)
            .put("responseBody", responseBody)
            .put("message", message)
    }
}

public class LocalSendDiscoveryPeer {
    public var alias: String = ""
    public var version: String = ""
    public var deviceModel: String = ""
    public var deviceType: String = ""
    public var fingerprint: String = ""
    public var protocol: String = "http"
    public var port: Int64 = 53317
    public var download: Bool = false
    public var announcement: Bool = false
    public var sourceIp: String = ""
    public var endpoint: String = ""

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("alias", alias)
            .put("version", version)
            .put("deviceModel", deviceModel)
            .put("deviceType", deviceType)
            .put("fingerprint", fingerprint)
            .put("protocol", protocol)
            .putInt("port", port)
            .putBool("download", download)
            .putBool("announcement", announcement)
            .put("sourceIp", sourceIp)
            .put("endpoint", endpoint)
    }
}

public func parseLocalSendPeerInfoPayload(raw: String, endpoint: String, apiVersion: String): ?LocalSendPeerInfo {
    let payload = raw.trimAscii()
    if (payload.size == 0) {
        return None
    }
    let alias = parseJsonString(payload, "alias") ?? ""
    let fingerprint = parseJsonString(payload, "fingerprint") ?? ""
    if (alias.trimAscii().size == 0 && fingerprint.trimAscii().size == 0) {
        return None
    }

    let info = LocalSendPeerInfo()
    info.alias = alias.trimAscii()
    info.version = (parseJsonString(payload, "version") ?? "").trimAscii()
    info.deviceModel = (parseJsonString(payload, "deviceModel") ?? "").trimAscii()
    info.deviceType = (parseJsonString(payload, "deviceType") ?? "").trimAscii()
    info.fingerprint = fingerprint.trimAscii()
    info.download = (parseJsonString(payload, "download") ?? "false").trimAscii().toLower() == "true"
    info.endpoint = endpoint.trimAscii()
    info.apiVersion = normalizeLocalSendApiVersion(apiVersion)
    info.peerId = normalizeLocalSendPeerId(if (info.fingerprint.size > 0) { info.fingerprint } else { info.alias })
    Some(info)
}

public func parseLocalSendPeerInfoFromEnvelope(raw: String, endpoint: String, apiVersion: String): ?LocalSendPeerInfo {
    let infoObj = extractJsonObjectFieldLocalSend(raw, "info")
    if (infoObj.size > 0) {
        return parseLocalSendPeerInfoPayload(infoObj, endpoint, apiVersion)
    }
    parseLocalSendPeerInfoPayload(raw, endpoint, apiVersion)
}

public func resolveLocalSendPeerEndpointFromEnvelope(raw: String, sourceIp: String, fallbackEndpoint: String): String {
    let infoObj = extractJsonObjectFieldLocalSend(raw, "info")
    let payload = if (infoObj.size > 0) { infoObj } else { raw.trimAscii() }
    let endpoint = parseJsonString(payload, "endpoint") ?? ""
    if (endpoint.trimAscii().size > 0) {
        return endpoint.trimAscii()
    }

    let host = sourceIp.trimAscii()
    if (host.size == 0) {
        return fallbackEndpoint.trimAscii()
    }

    let protocol = normalizeLocalSendProtocol(parseJsonString(payload, "protocol") ?? "")
    let port = parseLocalSendIntField(payload, "port")
    buildLocalSendEndpoint(protocol, host, if (port > 0) { port } else { 53317 })
}

public func parseLocalSendFileOffers(raw: String): ArrayList<LocalSendFileOffer> {
    let out = ArrayList<LocalSendFileOffer>()
    let filesObj = extractJsonObjectFieldLocalSend(raw, "files")
    if (filesObj.size == 0) {
        return out
    }
    let entries = extractJsonObjectMapEntriesLocalSend(filesObj)
    for (entry in entries) {
        let entryId = entry[0]
        let entryRaw = entry[1]
        let file = LocalSendFileOffer()
        file.fileId = firstNonEmptyLocalSend([
            parseJsonString(entryRaw, "id") ?? "",
            entryId,
        ])
        file.fileName = firstNonEmptyLocalSend([
            parseJsonString(entryRaw, "fileName") ?? "",
            parseJsonString(entryRaw, "name") ?? "",
            file.fileId,
            "payload.bin",
        ])
        file.size = parseLocalSendIntField(entryRaw, "size")
        file.fileType = firstNonEmptyLocalSend([
            parseJsonString(entryRaw, "fileType") ?? "",
            parseJsonString(entryRaw, "mime") ?? "",
            "application/octet-stream",
        ])
        file.sha256 = parseJsonString(entryRaw, "sha256") ?? ""
        if (file.fileId.size > 0) {
            out.add(file)
        }
    }
    out
}

public func parseLocalSendDiscoveryPayload(raw: String, sourceIp: String): ?LocalSendDiscoveryPeer {
    let alias = parseJsonString(raw, "alias") ?? ""
    let fingerprint = parseJsonString(raw, "fingerprint") ?? ""
    let port = parseLocalSendIntField(raw, "port")
    if (alias.trimAscii().size == 0 && fingerprint.trimAscii().size == 0) {
        return None
    }
    let peer = LocalSendDiscoveryPeer()
    peer.alias = alias.trimAscii()
    peer.version = (parseJsonString(raw, "version") ?? "").trimAscii()
    peer.deviceModel = (parseJsonString(raw, "deviceModel") ?? "").trimAscii()
    peer.deviceType = (parseJsonString(raw, "deviceType") ?? "").trimAscii()
    peer.fingerprint = fingerprint.trimAscii()
    peer.protocol = normalizeLocalSendProtocol(parseJsonString(raw, "protocol") ?? "")
    peer.port = if (port > 0) { port } else { 53317 }
    peer.download = (parseJsonString(raw, "download") ?? "false").trimAscii().toLower() == "true"
    peer.announcement = (parseJsonString(raw, "announcement") ?? "false").trimAscii().toLower() == "true"
    peer.sourceIp = sourceIp.trimAscii()
    peer.endpoint = buildLocalSendEndpoint(peer.protocol, peer.sourceIp, peer.port)
    Some(peer)
}

public func buildLocalSendEndpoint(protocol: String, host: String, port: Int64): String {
    let proto = normalizeLocalSendProtocol(protocol)
    let normalizedHost = host.trimAscii()
    if (normalizedHost.size == 0) {
        return ""
    }
    "${proto}://${normalizedHost}:${if (port > 0) { port } else { 53317 }}"
}

public func buildLocalSendInfoChannelAdapterMessage(info: LocalSendPeerInfo, body: String): ChannelAdapterMessage {
    let message = ChannelAdapterMessage()
    message.protocolId = "localsend"
    message.peerId = if (info.peerId.size > 0) { info.peerId } else { normalizeLocalSendPeerId(info.fingerprint) }
    message.peerDisplayName = if (info.alias.size > 0) { info.alias } else { message.peerId }
    message.endpoint = info.endpoint
    message.body = body
    message.contentType = "text/plain"
    message.sourceRecordId = "localsend-info-${info.apiVersion}-${message.peerId}"
    message
}

func normalizeLocalSendApiVersion(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    if (normalized == "v1" || normalized == "1") {
        return "v1"
    }
    "v2"
}

func normalizeLocalSendProtocol(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    if (normalized == "https") {
        return "https"
    }
    "http"
}

func parseLocalSendIntField(raw: String, field: String): Int64 {
    let value = parseJsonString(raw, field) ?? "0"
    try {
        return Int64.parse(value.trimAscii())
    } catch (_: Exception) {
        return 0
    }
}

func firstNonEmptyLocalSend(values: Array<String>): String {
    for (value in values) {
        let trimmed = value.trimAscii()
        if (trimmed.size > 0) {
            return trimmed
        }
    }
    ""
}

func extractJsonObjectFieldLocalSend(raw: String, field: String): String {
    let searchKey = "\"${field}\""
    let runes = raw.toRuneArray()
    let keyRunes = searchKey.toRuneArray()
    var i: Int64 = 0
    while (i <= runes.size - keyRunes.size) {
        var found = true
        for (j in 0..keyRunes.size) {
            if (runes[i + j] != keyRunes[j]) {
                found = false
                break
            }
        }
        if (found) {
            var k = i + keyRunes.size
            while (k < runes.size && (runes[k] == r' ' || runes[k] == r':' || runes[k] == r'\n' || runes[k] == r'\r' || runes[k] == r'\t')) {
                k += 1
            }
            if (k < runes.size && runes[k] == r'{') {
                let end = findMatchingBraceLocalSend(runes, k)
                if (end > k) {
                    return strSubstring(raw, k, end + 1)
                }
            }
        }
        i += 1
    }
    ""
}

func extractJsonObjectMapEntriesLocalSend(raw: String): ArrayList<(String, String)> {
    let out = ArrayList<(String, String)>()
    let runes = raw.toRuneArray()
    var i: Int64 = 0
    while (i < runes.size) {
        while (i < runes.size && runes[i] != r'"') {
            i += 1
        }
        if (i >= runes.size) {
            break
        }
        let keyStart = i + 1
        i = keyStart
        var key = ""
        while (i < runes.size && runes[i] != r'"') {
            if (runes[i] == r'\\' && i + 1 < runes.size) {
                key += runes[i + 1].toString()
                i += 2
                continue
            }
            key += runes[i].toString()
            i += 1
        }
        i += 1
        while (i < runes.size && (runes[i] == r' ' || runes[i] == r':' || runes[i] == r'\n' || runes[i] == r'\r' || runes[i] == r'\t')) {
            i += 1
        }
        if (i < runes.size && runes[i] == r'{') {
            let end = findMatchingBraceLocalSend(runes, i)
            if (end > i) {
                out.add((key, strSubstring(raw, i, end + 1)))
                i = end + 1
                continue
            }
        }
        i += 1
    }
    out
}

func findMatchingBraceLocalSend(runes: Array<Rune>, start: Int64): Int64 {
    var depth: Int64 = 0
    var inString = false
    var escaped = false
    for (i in start..runes.size) {
        let ch = runes[i]
        if (inString) {
            if (escaped) {
                escaped = false
            } else if (ch == r'\\') {
                escaped = true
            } else if (ch == r'"') {
                inString = false
            }
            continue
        }
        if (ch == r'"') {
            inString = true
            continue
        }
        if (ch == r'{') {
            depth += 1
        } else if (ch == r'}') {
            depth -= 1
            if (depth == 0) {
                return i
            }
        }
    }
    -1
}

func normalizeLocalSendPeerId(raw: String): String {
    var out = raw.trimAscii().toLower()
    out = strReplace(out, " ", "-")
    out = strReplace(out, "/", "-")
    out = strReplace(out, "\\", "-")
    while (strContainsLocalSendPeerId(out, "..")) {
        out = strReplace(out, "..", "-")
    }
    if (out.size > 80) {
        out = strSubstring(out, 0, 80)
    }
    if (out.size == 0) {
        return "unknown-localsend-peer"
    }
    out
}

func strContainsLocalSendPeerId(haystack: String, needle: String): Bool {
    let h = haystack.toRuneArray()
    let n = needle.toRuneArray()
    if (n.size == 0) { return true }
    if (h.size < n.size) { return false }
    for (i in 0..=(h.size - n.size)) {
        var ok = true
        for (j in 0..n.size) {
            if (h[i + j] != n[j]) {
                ok = false
                break
            }
        }
        if (ok) { return true }
    }
    false
}

public class WhitelistRule {
    public var sourceDevice: String = "*"
    public var targetDevice: String = ""
    public var enabled: Bool = true
    public var createdAt: Int64 = 0

    public init() {}

    public func key(): String {
        "${sourceDevice}->${targetDevice}"
    }

    public func toJson(): JsonObject {
        JsonObject()
            .put("sourceDevice", sourceDevice)
            .put("targetDevice", targetDevice)
            .putBool("enabled", enabled)
            .putInt("createdAt", createdAt)
    }
}

public class FavoriteEntry {
    public var deviceId: String = ""
    public var path: String = "/"
    public var name: String = ""
    public var createdAt: Int64 = 0

    public init() {}

    public func key(): String {
        "${deviceId}::${path}"
    }

    public func toJson(): JsonObject {
        JsonObject()
            .put("deviceId", deviceId)
            .put("path", path)
            .put("name", name)
            .putInt("createdAt", createdAt)
    }
}

public interface FavoriteStore {
    func mode(): String
    func load(): ArrayList<FavoriteEntry>
    func save(entries: ArrayList<FavoriteEntry>): Unit
}
