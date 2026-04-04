package soonlnk.features

import soonlnk.commons.*
import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.unicode.*

public class ConnectorDescriptor {
    public var id: String = ""
    public var displayName: String = ""
    public var category: String = ""
    public var supportsListDir: Bool = false
    public var supportsReadRange: Bool = false
    public var supportsCreateDir: Bool = false
    public var supportsChunkUpload: Bool = false

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("id", id)
            .put("displayName", displayName)
            .put("category", category)
            .putBool("supportsListDir", supportsListDir)
            .putBool("supportsReadRange", supportsReadRange)
            .putBool("supportsCreateDir", supportsCreateDir)
            .putBool("supportsChunkUpload", supportsChunkUpload)
    }
}

public interface ConnectorFileClient {
    func listDir(path: String): ArrayList<FileEntry>
    func getFileInfo(path: String): ?FileMetadata
    func readRange(path: String, offset: Int64, length: Int64): Array<UInt8>
    func createDir(path: String): Bool
    func uploadFile(
        sourceDevice: String,
        finalPath: String,
        fileSize: Int64,
        chunkSize: Int64,
        readChunk: (Int64, Int64) -> Array<UInt8>
    ): Bool
    func close(): Unit
}

public interface ConnectorDriver {
    func id(): String
    func displayName(): String
    func category(): String
    func supportsDevice(device: Device): Bool
    func descriptor(): ConnectorDescriptor
    func openFileClient(device: Device): ?ConnectorFileClient
}

public class ConnectorRegistry {
    var drivers: HashMap<String, ConnectorDriver> = HashMap<String, ConnectorDriver>()
    let mutex: Mutex = Mutex()

    public init() {}

    public func registerDriver(driver: ConnectorDriver): Unit {
        let key = normalizeConnectorType(driver.id())
        synchronized(mutex) {
            drivers.add(key, driver)
        }
    }

    public func descriptor(connectorType: String): ?ConnectorDescriptor {
        let normalized = normalizeConnectorType(connectorType)
        var resolved: ?ConnectorDescriptor = None
        synchronized(mutex) {
            match (drivers.get(normalized)) {
                case Some(driver) =>
                    resolved = Some(driver.descriptor())
                case None => ()
            }
        }
        resolved
    }

    public func hasDriver(connectorType: String): Bool {
        let normalized = normalizeConnectorType(connectorType)
        var found = false
        synchronized(mutex) {
            match (drivers.get(normalized)) {
                case Some(_) => found = true
                case None => ()
            }
        }
        found
    }

    public func listDescriptors(): ArrayList<ConnectorDescriptor> {
        let out = ArrayList<ConnectorDescriptor>()
        synchronized(mutex) {
            for ((_, driver) in drivers) {
                out.add(driver.descriptor())
            }
        }
        out
    }

    public func resolveDriver(device: Device): ?ConnectorDriver {
        let preferred = defaultConnectorTypeForDevice(device)
        var resolved: ?ConnectorDriver = None
        synchronized(mutex) {
            match (drivers.get(preferred)) {
                case Some(driver) =>
                    if (driver.supportsDevice(device)) {
                        resolved = Some(driver)
                    }
                case None => ()
            }

            match (resolved) {
                case Some(_) => ()
                case None =>
                    for ((_, candidate) in drivers) {
                        if (candidate.supportsDevice(device)) {
                            resolved = Some(candidate)
                            break
                        }
                    }
            }
        }
        resolved
    }

    public func openFileClient(device: Device): ?ConnectorFileClient {
        match (resolveDriver(device)) {
            case Some(driver) =>
                driver.openFileClient(device)
            case None =>
                None
        }
    }
}

public class LocalFsConnectorDriver <: ConnectorDriver {
    public init() {}

    public func id(): String {
        "local-fs"
    }

    public func displayName(): String {
        "Local FileSystem"
    }

    public func category(): String {
        "local"
    }

    public func supportsDevice(device: Device): Bool {
        defaultConnectorTypeForDevice(device) == "local-fs"
    }

    public func descriptor(): ConnectorDescriptor {
        let out = ConnectorDescriptor()
        out.id = id()
        out.displayName = displayName()
        out.category = category()
        out.supportsListDir = true
        out.supportsReadRange = true
        out.supportsCreateDir = true
        out.supportsChunkUpload = true
        out
    }

    public func openFileClient(_device: Device): ?ConnectorFileClient {
        None
    }
}

class SoonLinkNodeFileClient <: ConnectorFileClient {
    let nodeClient: SoonLinkNodeClient

    init(host: String, port: Int64) {
        this.nodeClient = SoonLinkNodeClient(host, port)
    }

    public func listDir(path: String): ArrayList<FileEntry> {
        nodeClient.listDir(path)
    }

    public func getFileInfo(path: String): ?FileMetadata {
        nodeClient.getFileInfo(path)
    }

    public func readRange(path: String, offset: Int64, length: Int64): Array<UInt8> {
        nodeClient.readRange(path, offset, length)
    }

    public func createDir(path: String): Bool {
        nodeClient.createDir(path)
    }

    public func uploadFile(
        sourceDevice: String,
        finalPath: String,
        fileSize: Int64,
        chunkSize: Int64,
        readChunk: (Int64, Int64) -> Array<UInt8>
    ): Bool {
        nodeClient.uploadFile(sourceDevice, finalPath, fileSize, chunkSize, readChunk)
    }

    public func close(): Unit {
        nodeClient.close()
    }
}

public class SoonLinkNodeConnectorDriver <: ConnectorDriver {
    public init() {}

    public func id(): String {
        "soonlink-http"
    }

    public func displayName(): String {
        "SoonLink Node HTTP"
    }

    public func category(): String {
        "soonlink"
    }

    public func supportsDevice(device: Device): Bool {
        if (defaultConnectorTypeForDevice(device) != "soonlink-http") {
            return false
        }
        device.id != "local" && device.ip.size > 0 && device.port > 0
    }

    public func descriptor(): ConnectorDescriptor {
        let out = ConnectorDescriptor()
        out.id = id()
        out.displayName = displayName()
        out.category = category()
        out.supportsListDir = true
        out.supportsReadRange = true
        out.supportsCreateDir = true
        out.supportsChunkUpload = true
        out
    }

    public func openFileClient(device: Device): ?ConnectorFileClient {
        if (!supportsDevice(device)) {
            return None
        }
        Some(SoonLinkNodeFileClient(device.ip, device.port))
    }
}

public func normalizeConnectorType(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    if (normalized.size == 0) {
        return ""
    }
    match (normalized) {
        case "local" => "local-fs"
        case "local-fs" => "local-fs"
        case "soonlink" => "soonlink-http"
        case "soonlink-node" => "soonlink-http"
        case "soonlink-http" => "soonlink-http"
        case "soonlnk-http" => "soonlink-http"
        case _ => normalized
    }
}

public func defaultConnectorTypeForDevice(device: Device): String {
    let explicit = normalizeConnectorType(device.connectorType)
    if (explicit.size > 0) {
        return explicit
    }
    if (device.id == "local" || device.deviceType == "local") {
        return "local-fs"
    }
    if (device.ip.size > 0 && device.port > 0) {
        return "soonlink-http"
    }
    "manual"
}

public func applyDefaultDeviceConnector(device: Device): Unit {
    device.connectorType = defaultConnectorTypeForDevice(device)
}
