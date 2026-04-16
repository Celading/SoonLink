package soonlnk.commons

import std.collection.ArrayList

public class RelayJob {
    public var id: String = ""
    public var recordKind: String = "file"
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
    public var createdAt: Int64 = 0
    public var updatedAt: Int64 = 0
    public var expiresAt: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("id", id)
            .put("recordKind", recordKind)
            .put("sourceDevice", sourceDevice)
            .put("targetDevice", targetDevice)
            .put("targetPath", targetPath)
            .put("fileName", fileName)
            .putBool("cacheAvailable", cacheAvailable)
            .putInt("bytes", bytes)
            .put("status", status)
            .putInt("attempts", attempts)
            .put("message", message)
            .putInt("createdAt", createdAt)
            .putInt("updatedAt", updatedAt)
            .putInt("expiresAt", expiresAt)
    }
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
