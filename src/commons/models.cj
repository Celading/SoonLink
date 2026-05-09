package soonlnk.commons

import std.collection.ArrayList
import std.time.DateTime
import std.unicode.*

public enum TaskStatus {
    | Pending
    | Running
    | Completed
    | Failed
    | Cancelled
}

public enum DeviceTrustState {
    | Unknown
    | Trusted
    | Blocked
}

public enum TransferRequestStatus {
    | RequestPending
    | RequestAccepted
    | RequestRejected
    | RequestCancelled
}

public func taskStatusToString(status: TaskStatus): String {
    match (status) {
        case Pending => "pending"
        case Running => "running"
        case Completed => "completed"
        case Failed => "failed"
        case Cancelled => "cancelled"
    }
}

public func taskStatusFromString(s: String): TaskStatus {
    match (s) {
        case "running" => Running
        case "completed" => Completed
        case "failed" => Failed
        case "cancelled" => Cancelled
        case _ => Pending
    }
}

public func deviceTrustStateToString(state: DeviceTrustState): String {
    match (state) {
        case Trusted => "trusted"
        case Blocked => "blocked"
        case _ => "unknown"
    }
}

public func deviceTrustStateFromString(raw: String): DeviceTrustState {
    match (raw.trimAscii().toLower()) {
        case "trusted" => Trusted
        case "blocked" => Blocked
        case _ => Unknown
    }
}

public func transferRequestStatusToString(status: TransferRequestStatus): String {
    match (status) {
        case RequestAccepted => "accepted"
        case RequestRejected => "rejected"
        case RequestCancelled => "cancelled"
        case _ => "pending"
    }
}

public func transferRequestStatusFromString(raw: String): TransferRequestStatus {
    match (raw.trimAscii().toLower()) {
        case "accepted" => RequestAccepted
        case "rejected" => RequestRejected
        case "cancelled" => RequestCancelled
        case _ => RequestPending
    }
}

public class Device {
    public var id: String = ""
    public var name: String = ""
    public var deviceType: String = ""
    public var connectorType: String = ""
    public var endpointScheme: String = ""
    public var endpointBasePath: String = ""
    public var ip: String = ""
    public var port: Int64 = 0
    public var lastSeen: Int64 = 0
    public var capability: ArrayList<String> = ArrayList<String>()
    public var online: Bool = false
    public var remembered: Bool = false
    public var trustState: DeviceTrustState = Unknown
    public var trustSource: String = ""
    public var trustUpdatedAt: Int64 = 0

    public init() {}

    public init(
        id!: String = "",
        name!: String = "",
        deviceType!: String = "",
        ip!: String = "",
        port!: Int64 = 0,
        online!: Bool = false
    ) {
        this.id = id
        this.name = name
        this.deviceType = deviceType
        this.ip = ip
        this.port = port
        this.online = online
        this.lastSeen = currentTimestamp()
    }

    public func toJson(): JsonObject {
        let capArr = JsonArray()
        for (c in capability) {
            capArr.addStr(c)
        }
        let endpoint = buildDeviceEndpoint(this)
        JsonObject()
            .put("id", id)
            .put("name", name)
            .put("type", deviceType)
            .put("connectorType", connectorType)
            .put("endpointScheme", endpoint.scheme)
            .put("endpointBasePath", endpoint.basePath)
            .put("ip", ip)
            .putInt("port", port)
            .putInt("lastSeen", lastSeen)
            .putArr("capability", capArr)
            .putBool("online", online)
            .putBool("remembered", remembered)
            .putObj("endpoint", endpoint.toJson())
            .put("trustState", deviceTrustStateToString(trustState))
            .put("trustSource", trustSource)
            .putInt("trustUpdatedAt", trustUpdatedAt)
    }
}

public class DevicePinPairingSession {
    public var deviceId: String = ""
    public var pin: String = ""
    public var requestedAt: Int64 = 0
    public var expiresAt: Int64 = 0
    public var source: String = "pin"

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("deviceId", deviceId)
            .put("pin", pin)
            .putInt("requestedAt", requestedAt)
            .putInt("expiresAt", expiresAt)
            .put("source", source)
    }
}

public class FileMetadata {
    public var name: String = ""
    public var path: String = ""
    public var size: Int64 = 0
    public var mimeType: String = ""
    public var category: String = ""
    public var modified: Int64 = 0
    public var isDir: Bool = false
    public var checksum: String = ""
    public var encrypted: Bool = false

    public init() {}

    public func toJson(): JsonObject {
        let obj = JsonObject()
            .put("name", name)
            .put("path", path)
            .putInt("size", size)
            .put("sizeText", formatBytes(size))
            .put("mimeType", mimeType)
            .put("category", category)
            .putInt("modified", modified)
            .putBool("isDir", isDir)
            .putBool("encrypted", encrypted)
        if (checksum.size > 0) {
            obj.put("checksum", checksum)
        }
        obj
    }
}

public class FileEntry {
    public var name: String = ""
    public var path: String = ""
    public var size: Int64 = 0
    public var modified: Int64 = 0
    public var isDir: Bool = false
    public var mimeType: String = ""
    public var category: String = ""

    public init() {}

    public init(name!: String, path!: String, size!: Int64, modified!: Int64, isDir!: Bool) {
        this.name = name
        this.path = path
        this.size = size
        this.modified = modified
        this.isDir = isDir
    }

    public func toJson(): JsonObject {
        JsonObject()
            .put("name", name)
            .put("path", path)
            .putInt("size", size)
            .put("sizeText", formatBytes(size))
            .putInt("modified", modified)
            .putBool("isDir", isDir)
            .put("mimeType", mimeType)
            .put("category", category)
    }
}

public class TransferTask {
    public var id: String = ""
    public var sourceDevice: String = ""
    public var targetDevice: String = ""
    public var filePath: String = ""
    public var targetPath: String = ""
    public var metadata: FileMetadata = FileMetadata()
    public var sourceIsDir: Bool = false
    public var totalEntries: Int64 = 0
    public var completedEntries: Int64 = 0
    public var totalBytes: Int64 = 0
    public var transferredBytes: Int64 = 0
    public var currentItem: String = ""
    public var status: TaskStatus = Pending
    public var progress: Float64 = 0.0
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0
    public var completedAt: Int64 = 0
    public var error: String = ""
    public var protocol: String = ""
    public var encrypted: Bool = false
    public var tempPath: String = ""
    public var threads: Int64 = 0
    public var chunkSize: Int64 = 0
    public var chunkProgress: ArrayList<ChunkProgress> = ArrayList<ChunkProgress>()
    public var speed: Int64 = 0
    public var eta: Int64 = 0
    public var fileCategory: String = ""
    public var protocolPreferences: ArrayList<String> = ArrayList<String>()
    public var protocolCandidates: ArrayList<String> = ArrayList<String>()

    public init() {
        this.createdAt = currentTimestamp()
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
            .put("id", id)
            .put("sourceDevice", sourceDevice)
            .put("targetDevice", targetDevice)
            .put("filePath", filePath)
            .put("targetPath", targetPath)
            .putBool("sourceIsDir", sourceIsDir)
            .putInt("totalEntries", totalEntries)
            .putInt("completedEntries", completedEntries)
            .putInt("totalBytes", totalBytes)
            .put("totalBytesText", formatBytes(totalBytes))
            .putInt("transferredBytes", transferredBytes)
            .put("transferredBytesText", formatBytes(transferredBytes))
            .put("status", taskStatusToString(status))
            .putFloat("progress", progress)
            .putInt("createdAt", createdAt)
            .putInt("updatedAt", updatedAt)
            .put("protocol", protocol)
            .put("fileCategory", fileCategory)
            .putArr("protocolPreferences", stringListToJsonArray(protocolPreferences))
            .putArr("protocolCandidates", stringListToJsonArray(protocolCandidates))
            .putBool("encrypted", encrypted)
            .putInt("threads", threads)
            .putInt("speed", speed)
            .putInt("eta", eta)
        if (error.size > 0) {
            obj.put("error", error)
        }
        if (completedAt > 0) {
            obj.putInt("completedAt", completedAt)
        }
        if (currentItem.size > 0) {
            obj.put("currentItem", currentItem)
        }
        if (metadata.path.size > 0 || metadata.name.size > 0) {
            obj.putObj("metadata", metadata.toJson())
        }
        obj
    }
}

public class TransferRequest {
    public var id: String = ""
    public var requesterDeviceId: String = ""
    public var requesterName: String = ""
    public var requesterHost: String = ""
    public var requesterPort: Int64 = 0
    public var sourceDevice: String = ""
    public var sourceName: String = ""
    public var targetDevice: String = "local"
    public var filePath: String = ""
    public var targetPath: String = "/"
    public var metadata: FileMetadata = FileMetadata()
    public var sourceIsDir: Bool = false
    public var totalEntries: Int64 = 0
    public var totalBytes: Int64 = 0
    public var status: TransferRequestStatus = RequestPending
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0
    public var resolvedAt: Int64 = 0
    public var note: String = ""
    public var responseMessage: String = ""
    public var acceptedTaskId: String = ""
    public var fileCategory: String = ""
    public var protocolPreferences: ArrayList<String> = ArrayList<String>()
    public var protocolCandidates: ArrayList<String> = ArrayList<String>()

    public init() {
        let now = currentTimestamp()
        this.createdAt = now
        this.updatedAt = now
    }

    public func toJson(): JsonObject {
        let obj = JsonObject()
            .put("id", id)
            .put("requesterDeviceId", requesterDeviceId)
            .put("requesterName", requesterName)
            .put("requesterHost", requesterHost)
            .putInt("requesterPort", requesterPort)
            .put("sourceDevice", sourceDevice)
            .put("sourceName", sourceName)
            .put("targetDevice", targetDevice)
            .put("filePath", filePath)
            .put("targetPath", targetPath)
            .putBool("sourceIsDir", sourceIsDir)
            .putInt("totalEntries", totalEntries)
            .putInt("totalBytes", totalBytes)
            .put("totalBytesText", formatBytes(totalBytes))
            .put("fileCategory", fileCategory)
            .putArr("protocolPreferences", stringListToJsonArray(protocolPreferences))
            .putArr("protocolCandidates", stringListToJsonArray(protocolCandidates))
            .put("status", transferRequestStatusToString(status))
            .putInt("createdAt", createdAt)
            .putInt("updatedAt", updatedAt)
        if (resolvedAt > 0) {
            obj.putInt("resolvedAt", resolvedAt)
        }
        if (note.size > 0) {
            obj.put("note", note)
        }
        if (responseMessage.size > 0) {
            obj.put("responseMessage", responseMessage)
        }
        if (acceptedTaskId.size > 0) {
            obj.put("acceptedTaskId", acceptedTaskId)
        }
        if (metadata.path.size > 0 || metadata.name.size > 0) {
            obj.putObj("metadata", metadata.toJson())
        }
        obj
    }
}

public class ChunkProgress {
    public var index: Int64 = 0
    public var start: Int64 = 0
    public var end: Int64 = 0
    public var downloaded: Int64 = 0
    public var progress: Float64 = 0.0
    public var status: String = "pending"

    public init() {}
}

public class AccessLog {
    public var timestamp: Int64 = 0
    public var deviceId: String = ""
    public var filePath: String = ""
    public var action: String = ""

    public init() {}
}

public func currentTimestamp(): Int64 {
    DateTime.now().toUnixTimeStamp().toSeconds()
}

func stringListToJsonArray(values: ArrayList<String>): JsonArray {
    let arr = JsonArray()
    for (value in values) {
        arr.addStr(value)
    }
    arr
}
