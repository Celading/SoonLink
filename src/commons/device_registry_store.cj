package soonlnk.commons

import std.collection.ArrayList
import std.convert.*

public class DeviceRegistryRecord {
    public var id: String = ""
    public var name: String = ""
    public var deviceType: String = ""
    public var connectorType: String = ""
    public var endpointScheme: String = ""
    public var endpointBasePath: String = ""
    public var ip: String = ""
    public var port: Int64 = 0
    public var online: Bool = false
    public var remembered: Bool = true
    public var lastSeen: Int64 = 0
    public var trustState: DeviceTrustState = Unknown
    public var trustSource: String = ""
    public var trustUpdatedAt: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        let device = registryRecordToDevice(this)
        let endpoint = buildDeviceEndpoint(device)
        JsonObject()
            .put("id", id)
            .put("name", name)
            .put("deviceType", deviceType)
            .put("connectorType", connectorType)
            .put("endpointScheme", endpoint.scheme)
            .put("endpointBasePath", endpoint.basePath)
            .put("ip", ip)
            .putInt("port", port)
            .putBool("online", online)
            .putBool("remembered", remembered)
            .putInt("lastSeen", lastSeen)
            .putObj("endpoint", endpoint.toJson())
            .put("trustState", deviceTrustStateToString(trustState))
            .put("trustSource", trustSource)
            .putInt("trustUpdatedAt", trustUpdatedAt)
    }
}

public interface DeviceRegistryStore {
    func load(): ArrayList<DeviceRegistryRecord>
    func save(records: ArrayList<DeviceRegistryRecord>): Unit
}

public class JsonDeviceRegistryStore <: DeviceRegistryStore {
    public let path: String
    let fileMgr: FileMgr

    public init(path: String) {
        this.path = path
        this.fileMgr = LocalFileMgr()
    }

    public init(path: String, fileMgr: FileMgr) {
        this.path = path
        this.fileMgr = fileMgr
    }

    public func load(): ArrayList<DeviceRegistryRecord> {
        let records = ArrayList<DeviceRegistryRecord>()
        if (!fileMgr.exists(path)) {
            return records
        }

        let raw = fileMgr.readText(path).trimAscii()
        if (raw.size == 0) {
            return records
        }

        let objects = splitJsonObjects(raw)
        for (objRaw in objects) {
            let id = parseJsonString(objRaw, "id") ?? ""
            if (id.size == 0) {
                continue
            }

            let record = DeviceRegistryRecord()
            record.id = id
            record.name = parseJsonString(objRaw, "name") ?? ""
            record.deviceType = parseJsonString(objRaw, "deviceType") ?? ""
            record.connectorType = parseJsonString(objRaw, "connectorType") ?? ""
            record.endpointScheme = parseJsonString(objRaw, "endpointScheme") ?? (parseJsonString(objRaw, "scheme") ?? "")
            record.endpointBasePath = parseJsonString(objRaw, "endpointBasePath") ?? (parseJsonString(objRaw, "basePath") ?? "")
            record.ip = parseJsonString(objRaw, "ip") ?? ""

            let portStr = parseJsonString(objRaw, "port") ?? "0"
            try {
                record.port = Int64.parse(portStr)
            } catch (_: Exception) {
                record.port = 0
            }

            let onlineStr = parseJsonString(objRaw, "online") ?? "false"
            record.online = onlineStr == "true"
            let rememberedStr = parseJsonString(objRaw, "remembered") ?? "true"
            record.remembered = rememberedStr == "true"

            let lastSeenStr = parseJsonString(objRaw, "lastSeen") ?? "0"
            try {
                record.lastSeen = Int64.parse(lastSeenStr)
            } catch (_: Exception) {
                record.lastSeen = 0
            }

            record.trustState = deviceTrustStateFromString(parseJsonString(objRaw, "trustState") ?? "")
            record.trustSource = parseJsonString(objRaw, "trustSource") ?? ""
            let trustUpdatedAtStr = parseJsonString(objRaw, "trustUpdatedAt") ?? "0"
            try {
                record.trustUpdatedAt = Int64.parse(trustUpdatedAtStr)
            } catch (_: Exception) {
                record.trustUpdatedAt = 0
            }

            records.add(record)
        }

        records
    }

    public func save(records: ArrayList<DeviceRegistryRecord>): Unit {
        let arr = JsonArray()
        for (record in records) {
            arr.addObj(record.toJson())
        }
        fileMgr.writeText(path, arr.toString(), false)
    }
}

func splitJsonObjects(raw: String): ArrayList<String> {
    let result = ArrayList<String>()

    var depth: Int64 = 0
    var start: Int64 = -1
    var inString = false
    var escaped = false

    let runes = raw.toRuneArray()
    for (i in 0..runes.size) {
        let ch = runes[i]

        if (inString) {
            if (escaped) {
                escaped = false
                continue
            }
            if (ch == r'\\') {
                escaped = true
                continue
            }
            if (ch == r'"') {
                inString = false
            }
            continue
        }

        if (ch == r'"') {
            inString = true
            continue
        }

        if (ch == r'{') {
            if (depth == 0) {
                start = i
            }
            depth += 1
            continue
        }

        if (ch == r'}') {
            depth -= 1
            if (depth == 0 && start >= 0) {
                result.add(strSubstring(raw, start, i + 1))
                start = -1
            }
            continue
        }
    }

    result
}

public func deviceToRegistryRecord(device: Device): DeviceRegistryRecord {
    let record = DeviceRegistryRecord()
    record.id = device.id
    record.name = device.name
    record.deviceType = device.deviceType
    record.connectorType = device.connectorType
    record.endpointScheme = device.endpointScheme
    record.endpointBasePath = device.endpointBasePath
    record.ip = device.ip
    record.port = device.port
    record.online = device.online
    record.remembered = device.remembered
    record.lastSeen = device.lastSeen
    record.trustState = device.trustState
    record.trustSource = device.trustSource
    record.trustUpdatedAt = device.trustUpdatedAt
    record
}

public func registryRecordToDevice(record: DeviceRegistryRecord): Device {
    let device = Device(id: record.id)
    device.id = record.id
    device.name = record.name
    device.deviceType = record.deviceType
    device.connectorType = record.connectorType
    device.endpointScheme = record.endpointScheme
    device.endpointBasePath = record.endpointBasePath
    device.ip = record.ip
    device.port = record.port
    device.online = record.online
    device.remembered = record.remembered
    device.lastSeen = record.lastSeen
    device.trustState = record.trustState
    device.trustSource = record.trustSource
    device.trustUpdatedAt = record.trustUpdatedAt
    device
}
