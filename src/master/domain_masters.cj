package soonlnk.master

import soonlnk.commons.*
import soonlnk.features.*

import std.collection.ArrayList
import std.sync.Mutex

public class DeviceMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func listDevices(): ArrayList<Device> {
        server.listDevices()
    }

    public func getDevice(id: String): ?Device {
        server.getDevice(id)
    }

    public func register(record: DeviceRegistryRecord): Device {
        server.upsertManagedDeviceRecord(record)
    }

    public func upsert(record: DeviceRegistryRecord): Device {
        server.upsertManagedDeviceRecord(record)
    }

    public func remove(deviceId: String): Bool {
        server.removeManagedDeviceRecord(deviceId)
    }

    public func heartbeat(deviceId: String): ?Device {
        server.heartbeatDevice(deviceId)
    }

    public func setTrust(deviceId: String, state: String): Device {
        server.setDeviceTrustState(deviceId, state)
    }

    public func remember(deviceId: String): Device {
        server.rememberDiscoveredDevice(deviceId)
    }

    public func startPinPairing(deviceId: String): DevicePinPairingSession {
        server.startPinPairing(deviceId)
    }

    public func confirmPinPairing(deviceId: String, pin: String): Device {
        server.confirmPinPairing(deviceId, pin)
    }
}

public class FileMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func listDir(deviceId: String, path: String): ArrayList<FileEntry> {
        server.listDir(deviceId, path)
    }

    public func getInfo(deviceId: String, path: String): ?FileMetadata {
        server.getFileInfo(deviceId, path)
    }

    public func read(deviceId: String, path: String, offset: Int64, length: Int64): Array<UInt8> {
        server.readFile(deviceId, path, offset, length)
    }

    public func write(deviceId: String, path: String, data: Array<UInt8>, offset: Int64): Unit {
        server.writeFile(deviceId, path, data, offset)
    }

    public func createDir(deviceId: String, path: String): Bool {
        server.createDir(deviceId, path)
    }

    public func summary(deviceId: String, path: String): JsonObject {
        server.summarizeTransferSource(deviceId, path)
    }
}

public class ChunkTransferMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func createSession(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        fileSize: Int64,
        chunkSize: Int64
    ): ChunkSession {
        server.createChunkSession(sourceDevice, targetDevice, targetPath, fileName, fileSize, chunkSize)
    }

    public func writeChunk(sessionId: String, index: Int64, payload: Array<UInt8>): ChunkWriteResult {
        server.writeChunkSession(sessionId, index, payload)
    }

    public func manifest(sessionId: String): JsonObject {
        server.chunkSessionManifest(sessionId)
    }

    public func complete(sessionId: String): ChunkCompleteResult {
        server.completeChunkSession(sessionId)
    }
}

public class TaskMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func listTasks(): ArrayList<TransferTask> {
        server.listTasks()
    }

    public func getTask(id: String): ?TransferTask {
        server.getTask(id)
    }

    public func createTask(sourceDevice: String, targetDevice: String, filePath: String, targetPath: String): TransferTask {
        server.createTransferTask(sourceDevice, targetDevice, filePath, targetPath)
    }

    public func cancel(id: String): Bool {
        server.cancelTask(id)
    }
}

public class PeerMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func securityMode(): String {
        server.getSecurityMode()
    }

    public func updateSecurityMode(mode: String): String {
        server.setSecurityMode(mode)
    }

    public func beginHandshake(peerId: String): String {
        server.beginPeerHandshake(peerId)
    }

    public func upload(targetPath: String, peerId: String, token: String, payload: Array<UInt8>): PeerTransferResult {
        server.acceptPeerUpload(targetPath, peerId, token, payload)
    }

    public func pull(sourcePath: String, peerId: String, token: String): PeerDownloadPayload {
        server.providePeerDownload(sourcePath, peerId, token)
    }

    public func localPull(sourcePath: String, targetPath: String): PeerTransferResult {
        server.pullPeerLocal(sourcePath, targetPath)
    }
}

public class RelayMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func create(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        payload: Array<UInt8>
    ): RelayJob {
        server.createRelayJob(sourceDevice, targetDevice, targetPath, fileName, payload)
    }

    public func list(): ArrayList<RelayJob> {
        server.listRelayJobs()
    }

    public func get(jobId: String): ?RelayJob {
        server.getRelayJob(jobId)
    }

    public func cacheDescriptor(jobId: String): ?(String, String) {
        server.relayCacheDescriptor(jobId)
    }

    public func retry(jobId: String): ?RelayJob {
        server.retryRelayJob(jobId)
    }

    public func cancel(jobId: String): Bool {
        server.cancelRelayJob(jobId)
    }

    public func cleanup(statusFilter: String, olderThan: Int64): Int64 {
        server.cleanupRelayJobs(statusFilter, olderThan)
    }

    public func stats(): JsonObject {
        server.relayStats()
    }

    public func restore(jobId: String, targetDevice: String, targetPath: String): Bool {
        server.restoreRelayJob(jobId, targetDevice, targetPath)
    }
}

public class WhitelistMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func upsert(sourceDevice: String, targetDevice: String, enabled: Bool): WhitelistRule {
        server.upsertWhitelistRule(sourceDevice, targetDevice, enabled)
    }

    public func list(targetDevice: String): ArrayList<WhitelistRule> {
        server.listWhitelistRules(targetDevice)
    }

    public func setEnabled(sourceDevice: String, targetDevice: String, enabled: Bool): ?WhitelistRule {
        server.setWhitelistRuleEnabled(sourceDevice, targetDevice, enabled)
    }

    public func remove(sourceDevice: String, targetDevice: String): Bool {
        server.removeWhitelistRule(sourceDevice, targetDevice)
    }
}

public class FavoritesMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func mode(): String {
        server.favoriteStoreMode()
    }

    public func list(): ArrayList<FavoriteEntry> {
        server.listFavorites()
    }

    public func replace(entries: ArrayList<FavoriteEntry>): ArrayList<FavoriteEntry> {
        server.replaceFavorites(entries)
    }
}

public class MonitorMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func system(): JsonObject { server.monitorSystem() }
    public func cpu(): JsonObject { server.monitorCPU() }
    public func memory(): JsonObject { server.monitorMemory() }
    public func disk(path: String): JsonObject { server.monitorDisk(path) }
    public func network(): JsonObject { server.monitorNetwork() }
    public func temperature(): JsonObject { server.monitorTemperature() }
    public func uptime(): JsonObject { server.monitorUptime() }
}

public class LogMaster {
    let server: CoreServer

    public init(server: CoreServer) {
        this.server = server
    }

    public func list(limit: Int64): ArrayList<LogEntry> {
        server.logger.getLogs(limit)
    }

    public func listByLevel(level: LogLevel, limit: Int64): ArrayList<LogEntry> {
        server.logger.getLogsByLevel(level, limit)
    }

    public func listByCategory(category: String, limit: Int64): ArrayList<LogEntry> {
        server.logger.getLogsByCategory(category, limit)
    }

    public func clear(): Unit {
        server.logger.clearLogs()
    }

    public func stats(): JsonObject {
        server.logger.getStats()
    }
}

public class MediaMaster {
    let mutex: Mutex = Mutex()
    var isPlaying: Bool = false
    var currentTrackName: String = "SoonLink 控制台"
    var artistName: String = "SoonLink"
    var albumName: String = "Core Session"
    var durationSeconds: Int64 = 0
    var positionSeconds: Int64 = 0
    var volumeLevel: Int64 = 50
    var muted: Bool = false
    var queueIndex: Int64 = 1
    var updatedAt: Int64 = currentTimestamp()

    public init() {}

    public func status(): JsonObject {
        synchronized(mutex) {
            statusUnsafe()
        }
    }

    public func play(): JsonObject {
        synchronized(mutex) {
            if (currentTrackName.size == 0) {
                currentTrackName = "SoonLink 控制台"
            }
            isPlaying = true
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func pause(): JsonObject {
        synchronized(mutex) {
            isPlaying = false
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func stop(): JsonObject {
        synchronized(mutex) {
            isPlaying = false
            positionSeconds = 0
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func next(): JsonObject {
        synchronized(mutex) {
            queueIndex += 1
            currentTrackName = "SoonLink 会话 ${queueIndex}"
            artistName = "SoonLink"
            albumName = "Core Session"
            isPlaying = true
            positionSeconds = 0
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func previous(): JsonObject {
        synchronized(mutex) {
            if (queueIndex > 1) {
                queueIndex -= 1
            }
            currentTrackName = "SoonLink 会话 ${queueIndex}"
            artistName = "SoonLink"
            albumName = "Core Session"
            isPlaying = true
            positionSeconds = 0
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func setVolume(volume: Int64): JsonObject {
        synchronized(mutex) {
            var normalized = volume
            if (normalized < 0) { normalized = 0 }
            if (normalized > 100) { normalized = 100 }
            volumeLevel = normalized
            if (volumeLevel > 0) {
                muted = false
            }
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func mute(): JsonObject {
        synchronized(mutex) {
            muted = true
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func unmute(): JsonObject {
        synchronized(mutex) {
            muted = false
            updatedAt = currentTimestamp()
            statusUnsafe()
        }
    }

    public func volume(): Int64 {
        synchronized(mutex) {
            volumeLevel
        }
    }

    public func isMuted(): Bool {
        synchronized(mutex) {
            muted
        }
    }

    func statusUnsafe(): JsonObject {
        JsonObject()
            .putBool("isPlaying", isPlaying)
            .put("currentTrack", currentTrackName)
            .put("artist", artistName)
            .put("album", albumName)
            .putInt("duration", durationSeconds)
            .putInt("position", positionSeconds)
            .putInt("volume", volumeLevel)
            .putBool("isMuted", muted)
            .put("provider", "core-session")
            .putBool("supportsSystemMedia", false)
            .putInt("updatedAt", updatedAt)
    }
}

public class MasterBundle {
    public let devices: DeviceMaster
    public let files: FileMaster
    public let chunks: ChunkTransferMaster
    public let tasks: TaskMaster
    public let peers: PeerMaster
    public let relay: RelayMaster
    public let whitelist: WhitelistMaster
    public let favorites: FavoritesMaster
    public let monitor: MonitorMaster
    public let logs: LogMaster
    public let media: MediaMaster

    public init(server: CoreServer) {
        this.devices = DeviceMaster(server)
        this.files = FileMaster(server)
        this.chunks = ChunkTransferMaster(server)
        this.tasks = TaskMaster(server)
        this.peers = PeerMaster(server)
        this.relay = RelayMaster(server)
        this.whitelist = WhitelistMaster(server)
        this.favorites = FavoritesMaster(server)
        this.monitor = MonitorMaster(server)
        this.logs = LogMaster(server)
        this.media = MediaMaster()
    }
}
