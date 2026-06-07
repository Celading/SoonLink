package soonlnk.master

import soonlnk.api2.*
import soonlnk.commons.*
import soonlnk.features.*
import lisi.getNetworkInfo
import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.fs.Directory
import std.env.{getHomeDirectory, getVariable}
import std.random.Random
import std.unicode.*

public func getLocalIP(): String {
    if (let Some(explicitIP) <- getVariable("SOONLINK_LOCAL_IP")) {
        let resolved = selectDiscoveryAdvertiseIp(explicitIP, Array<String>())
        if (resolved.size > 0) {
            return resolved
        }
    }
    try {
        let network = getNetworkInfo()
        let resolved = selectDiscoveryAdvertiseIp("", network.ips)
        if (resolved.size > 0) {
            return resolved
        }
    } catch (_: Exception) {}
    ""
}

public class CoreServer {
    public let profile: RuntimeProfile
    public let config: AppConfig
    public let cryptoManager: CryptoManager
    public let fileManager: FileSystemManager
    public let connectorRegistry: ConnectorRegistry
    public let transferEngine: TransferEngine
    public let logger: LogManager
    public let authProvider: AuthProvider
    public let cryptoProvider: CryptoProvider

    public let securityChannel: SecurityChannel
    public let discoveryFeature: DiscoveryFeature
    public let peerTransferFeature: PeerTransferFeature
    public let monitorFeature: MonitorFeature
    public let logPersistFeature: LogPersistFeature
    public let relayFeature: RelayFeature
    public let favoritesFeature: FavoritesFeature
    public let chunkTransferFeature: ChunkTransferFeature
    public var localRootDir: String = ""

    var devices: HashMap<String, Device> = HashMap<String, Device>()
    let devicesMutex: Mutex = Mutex()

    var tasks: HashMap<String, TransferTask> = HashMap<String, TransferTask>()
    let tasksMutex: Mutex = Mutex()

    var transferRequests: HashMap<String, TransferRequest> = HashMap<String, TransferRequest>()
    let transferRequestsMutex: Mutex = Mutex()

    var pinPairingSessions: HashMap<String, DevicePinPairingSession> = HashMap<String, DevicePinPairingSession>()
    let pinPairingMutex: Mutex = Mutex()

    let startTime: Int64
    var runtimePrepared: Bool = false
    var consoleOutputEnabled: Bool = true

    public init(config: AppConfig, profile!: RuntimeProfile = defaultRuntimeProfile()) {
        this.profile = profile
        this.config = normalizeAppConfigForRuntime(config, profile)
        this.startTime = currentTimestamp()

        this.logger = LogManager(1000)
        this.cryptoManager = CryptoManager(this.config.encryptionKey)
        this.fileManager = FileSystemManager()
        this.connectorRegistry = ConnectorRegistry()
        this.transferEngine = TransferEngine(this.config.tempDir, this.config.maxConnections)
        this.authProvider = CorePlaceholderAuthProvider(profile)
        this.cryptoProvider = CorePlaceholderCryptoProvider(profile)

        this.securityChannel = SecurityChannel(securityModeFromString(this.config.securityMode))

        let registryStore = JsonDeviceRegistryStore(this.config.deviceRegistryFile)
        let udpTransport = UdpDiscoveryTransport(this.config.discoveryUdpPort)
        let mdnsTransport: DiscoveryTransport = if (this.config.enableMdns) {
            MdnsDiscoveryTransport()
        } else {
            NoopDiscoveryTransport("mdns-disabled")
        }

        this.discoveryFeature = DiscoveryFeature(registryStore, udpTransport, mdnsTransport)
        this.peerTransferFeature = PeerTransferFeature(LocalFileMgr(), securityChannel)
        let monitorRoot = if (this.config.localRootDir.size > 0) { this.config.localRootDir } else { getVariable("HOME") ?? "/" }
        this.monitorFeature = MonitorFeature(defaultPath: monitorRoot, diskProbe: MonitorDiskProbe())
        this.logPersistFeature = LogPersistFeature(RollingFileLogSink(this.config.logDir))
        this.relayFeature = RelayFeature(
            this.config.relayCacheDir,
            this.config.relayRetentionHours,
            this.config.relayLimitMode,
            this.config.relayLimitBytes,
            this.config.relayLimitPercent,
            DefaultDiskProbe(),
            this.config.whitelistTomlFile
        )

        let favoriteStore: FavoriteStore = if (this.config.favoritesStoreMode == "toml") {
            TomlFavoriteStore(this.config.favoritesTomlFile)
        } else {
            MemoryFavoriteStore()
        }
        this.favoritesFeature = FavoritesFeature(favoriteStore)
        this.chunkTransferFeature = ChunkTransferFeature(this.config.tempDir)
        monitorFeature.setPrimaryIpProvider({ =>
            this.currentPrimaryIp()
        })

        relayFeature.setDeviceOnlineChecker({ deviceId: String =>
            this.isDeviceOnline(deviceId)
        })
        relayFeature.setWriteHandler({ deviceId: String, path: String, payload: Array<UInt8> =>
            this.writeRelayTarget(deviceId, path, payload)
        })
        chunkTransferFeature.setWriteHandler({ deviceId: String, path: String, payload: Array<UInt8>, offset: Int64 =>
            this.writeChunkTarget(deviceId, path, payload, offset)
        })

        connectorRegistry.registerDriver(LocalFsConnectorDriver())
        connectorRegistry.registerDriver(SoonLinkNodeConnectorDriver())
    }

    public func setConsoleOutputEnabled(value: Bool): Unit {
        consoleOutputEnabled = value
        logger.setConsoleEnabled(value)
        transferEngine.setConsoleEnabled(value)
        fileManager.setConsoleEnabled(value)
    }

    public func start(): Unit {
        prepareRuntime(true, true, true, true)
    }

    public func startAutomationRuntime(): Unit {
        prepareRuntime(false, false, false, false)
    }

    public func stop(): Unit {
        if (!runtimePrepared) {
            return
        }
        logger.logInfo("system", "SoonLink服务正在关闭", "开始停止所有服务", "core/server")
        discoveryFeature.stop()
        logPersistFeature.flush()
        logger.logWarn("system", "核心服务已停止", "", "")
        runtimePrepared = false
    }

    public func uptimeSeconds(): Int64 {
        currentTimestamp() - startTime
    }

    func initRuntimeDirs(): Unit {
        try {
            Directory.create(config.tempDir, recursive: true)
        } catch (_: Exception) {}

        try {
            Directory.create(config.logDir, recursive: true)
        } catch (_: Exception) {}
        if (profile.supportsRelay) {
            try {
                Directory.create(config.relayCacheDir, recursive: true)
            } catch (_: Exception) {}
        }
        if (config.localRootDir.size > 0) {
            try {
                Directory.create(config.localRootDir, recursive: true)
            } catch (_: Exception) {}
        }

        ensureParentDir(config.deviceRegistryFile)
        ensureParentDir(config.configFile)
        if (profile.supportsFavorites) {
            ensureParentDir(config.favoritesTomlFile)
        }
        if (profile.supportsWhitelist) {
            ensureParentDir(config.whitelistTomlFile)
        }
    }

    func initLocalDevice(): Unit {
        let displayIP = resolveDiscoveryAdvertiseIp()

        let localDevice = Device(
            id: "local",
            name: resolveLocalDeviceDisplayName(),
            deviceType: "local",
            ip: displayIP,
            port: Int64(config.webPort),
            online: true
        )
        applyDefaultDeviceCapabilities(localDevice, profile)
        applyDefaultDeviceConnector(localDevice)
        applyDeviceTrustState(localDevice, Trusted, "runtime")
        registerDevice(localDevice)

        localRootDir = resolveLocalRootDir()
        fileManager.registerProvider("local", LocalFileSystem(localRootDir, consoleEnabled: consoleOutputEnabled))
        logger.logInfo("system", "本地设备已初始化", localDevice.name, "core/server")
    }

    func resolveNodeDisplayName(): String {
        let explicit = (getVariable("SOONLINK_NODE_NAME") ?? "").trimAscii()
        if (explicit.size > 0) {
            return explicit
        }

        let hostname = (getVariable("HOSTNAME") ?? getVariable("HOST") ?? "").trimAscii()
        if (hostname.size > 0 && hostname.toLower() != "unknown") {
            return hostname
        }

        let fallback = config.nodeId.trimAscii()
        if (fallback.size > 0) {
            return fallback
        }
        "SoonLink Node"
    }

    func resolveLocalDeviceDisplayName(): String {
        let base = resolveNodeDisplayName()
        if (strContains(base, "(本机)")) {
            return base
        }
        "${base}(本机)"
    }

    func buildDiscoverySelfRecord(): DeviceRegistryRecord {
        let record = DeviceRegistryRecord()
        record.id = config.nodeId
        record.name = resolveNodeDisplayName()
        record.deviceType = "node"
        record.connectorType = "soonlink-http"
        record.endpointScheme = "http"
        record.endpointBasePath = ""
        record.ip = resolveDiscoveryAdvertiseIp()
        record.port = Int64(config.webPort)
        record.online = true
        record.lastSeen = currentTimestamp()
        record.trustState = Trusted
        record.trustSource = "runtime"
        record.trustUpdatedAt = record.lastSeen
        record
    }

    func resolveLocalRootDir(): String {
        if (config.localRootDir.size > 0) {
            return config.localRootDir
        }
        try {
            return getHomeDirectory().toString()
        } catch (_: Exception) {
            getVariable("HOME") ?? "/tmp"
        }
    }

    func prepareRuntime(
        bindLogSink: Bool,
        enableDiscoveryTransport: Bool,
        enableBackgroundLoops: Bool,
        logLifecycle: Bool
    ): Unit {
        if (runtimePrepared) {
            return
        }

        if (logLifecycle) {
            logger.logInfo("system", "SoonLink服务启动", "开始初始化核心服务", "core/server")
        }

        initRuntimeDirs()
        if (bindLogSink) {
            logPersistFeature.bind(logger)
        }

        cryptoManager.start()
        if (logLifecycle) {
            logger.logInfo("crypto", "加密服务已启动", "", "core/server")
        }

        transferEngine.start()
        registerTransferProtocols()
        transferEngine.setTaskUpdateCallback({ taskId: String, status: TaskStatus, progress: Float64 =>
            updateTaskStatus(taskId, status, progress)
        })

        initLocalDevice()
        if (enableDiscoveryTransport) {
            startDiscovery()
        } else {
            loadPersistedDiscoveryRegistry()
        }

        if (enableBackgroundLoops) {
            if (profile.supportsActiveDiscovery && config.discoveryBroadcastEnabled) {
                spawn { startHeartbeatLoop() }
            }
            if (profile.supportsRelay) {
                spawn { startCleanupTask() }
                spawn { startRelayDispatchLoop() }
            }
        }

        runtimePrepared = true
        if (logLifecycle) {
            logger.logInfo("system", "SoonLink服务启动完成", "所有核心服务已成功启动", "core/server")
        }
    }

    func registerTransferProtocols(): Unit {
        transferEngine.registerProtocol(CoreServerTransferProtocol(this, "http"))
        transferEngine.registerProtocol(CoreServerTransferProtocol(this, "multi-thread-http"))
        transferEngine.registerProtocol(QUICProtocol())
        transferEngine.registerProtocol(RSyncProtocol())
        transferEngine.registerProtocol(P2PProtocol())
        logger.logInfo("system", "传输协议注册完成", "SoonLink HTTP coordinator, MultiThread-HTTP, QUIC, RSync, P2P", "core/server")
    }

    func startDiscovery(): Unit {
        discoveryFeature.setDeviceFoundCallback({ record: DeviceRegistryRecord =>
            upsertDiscoveredDevice(record, loadPersistedTrust: false)
        })
        if (profile.supportsPassiveDiscovery || profile.supportsActiveDiscovery) {
            discoveryFeature.start()
        }

        loadPersistedDiscoveryRegistry()
    }

    func loadPersistedDiscoveryRegistry(): Unit {
        let persisted = discoveryFeature.listRegistry()
        for (record in persisted) {
            upsertDiscoveredDevice(record, loadPersistedTrust: true)
        }
    }

    func startHeartbeatLoop(): Unit {
        publishDiscoveryHeartbeat()
        while (true) {
            sleep(Duration.second * config.discoveryHeartbeatSeconds)
            publishDiscoveryHeartbeat()
        }
    }

    func publishDiscoveryHeartbeat(): Unit {
        if (!profile.supportsActiveDiscovery || !config.discoveryBroadcastEnabled) {
            return
        }
        if (config.nodeId.trimAscii().size == 0) {
            return
        }
        discoveryFeature.publishHeartbeat(buildDiscoverySelfRecord())
    }

    func startCleanupTask(): Unit {
        while (true) {
            sleep(Duration.minute * 30)
            logger.logDebug("tasker", "cleanup", "执行临时文件清理", "core/server")
            relayFeature.cleanupExpired()
        }
    }

    func startRelayDispatchLoop(): Unit {
        while (true) {
            sleep(Duration.second * 15)
            if (!config.relayEnabled) {
                continue
            }
            relayFeature.tick()
        }
    }

    func upsertDiscoveredDevice(record: DeviceRegistryRecord, loadPersistedTrust!: Bool = false): Unit {
        if (record.id.size == 0 || record.id == "local" || record.id == config.nodeId) {
            return
        }

        let device = registryRecordToDevice(record)
        if (device.name.size == 0) {
            device.name = record.id
        }
        if (device.deviceType.size == 0) {
            device.deviceType = "node"
        }
        if (device.port == 0) {
            device.port = Int64(config.webPort)
        }
        device.online = true
        device.lastSeen = currentTimestamp()
        if (device.capability.size == 0) {
            applyDiscoveredDeviceCapabilities(device)
        }
        applyDefaultDeviceEndpoint(device)
        applyDefaultDeviceConnector(device)
        preserveDiscoveredState(device, loadPersistedTrust)

        registerDevice(device)
    }

    func applyDiscoveredDeviceCapabilities(device: Device): Unit {
        if (device.capability.size > 0) {
            return
        }
        device.capability.add("fs")
        device.capability.add("transfer")
    }

    // CFM/P Master boundary: device domain
    public func registerDevice(device: Device): Unit {
        if (device.id == "local") {
            applyDeviceTrustState(device, Trusted, "runtime")
        }
        applyDefaultDeviceEndpoint(device)
        applyDefaultDeviceConnector(device)
        synchronized(devicesMutex) {
            devices.add(device.id, device)
        }
    }

    public func registerDeviceRecord(record: DeviceRegistryRecord): Device {
        upsertManagedDeviceRecord(record)
    }

    public func validateManagedDeviceRecord(record: DeviceRegistryRecord): String {
        let id = record.id.trimAscii()
        if (id.size == 0) {
            return "设备ID不能为空"
        }
        if (id.toLower() == "local") {
            return "local 设备由运行时保留，不能手动维护"
        }

        let connectorType = normalizeConnectorType(record.connectorType)
        var effectiveConnectorType = connectorType
        if (effectiveConnectorType.size == 0) {
            effectiveConnectorType = defaultConnectorTypeForDevice(registryRecordToDevice(record))
        }
        if (effectiveConnectorType == "local-fs") {
            return "local-fs 仅保留给本机设备"
        }
        let endpointScheme = normalizeEndpointScheme(record.endpointScheme)
        if (
            effectiveConnectorType == "soonlink-http" &&
            endpointScheme.size > 0 &&
            endpointScheme != "http" &&
            endpointScheme != "https"
        ) {
            return "soonlink-http 仅支持 http 或 https endpointScheme"
        }

        let ip = record.ip.trimAscii()
        if (ip.size == 0) {
            return "设备地址不能为空"
        }

        let port = if (record.port > 0) { record.port } else { Int64(config.webPort) }
        if (port <= 0) {
            return "设备端口不能为空"
        }
        ""
    }

    public func upsertManagedDeviceRecord(record: DeviceRegistryRecord): Device {
        let normalizedId = record.id.trimAscii()
        var existing: ?Device = None
        if (normalizedId.size > 0) {
            existing = getDevice(normalizedId)
        }

        let validationError = normalizeManagedDeviceRecord(record, existing)
        if (validationError.size > 0) {
            throw Exception(validationError)
        }

        let device = registryRecordToDevice(record)
        if (device.capability.size == 0) {
            applyDefaultDeviceCapabilities(device, profile)
        }
        applyDefaultDeviceEndpoint(device)
        applyDefaultDeviceConnector(device)
        registerDevice(device)
        persistDeviceRecord(device)
        device
    }

    public func removeManagedDeviceRecord(deviceId: String): Bool {
        let normalized = deviceId.trimAscii()
        if (normalized.size == 0 || normalized.toLower() == "local") {
            return false
        }

        var removed = discoveryFeature.removeRecord(normalized)
        synchronized(devicesMutex) {
            match (devices.get(normalized)) {
                case Some(_) =>
                    devices.remove(normalized)
                    removed = true
                case None => ()
            }
        }
        synchronized(pinPairingMutex) {
            pinPairingSessions.remove(normalized)
        }
        removed
    }

    public func heartbeatDevice(deviceId: String): ?Device {
        synchronized(devicesMutex) {
            if (let Some(device) <- devices.get(deviceId)) {
                device.online = true
                device.lastSeen = currentTimestamp()

                if (device.remembered) {
                    persistDeviceRecord(device)
                }
                return Some(device)
            }
        }
        None
    }

    public func rememberDiscoveredDevice(deviceId: String): Device {
        let normalized = deviceId.trimAscii()
        if (normalized.size == 0) {
            throw Exception("设备ID不能为空")
        }
        if (normalized.toLower() == "local") {
            throw Exception("local 设备由运行时保留，无需重复记住")
        }

        match (getDevice(normalized)) {
            case Some(device) =>
                persistDeviceRecord(device)
                device
            case None =>
                throw Exception("设备不存在: ${normalized}")
        }
    }

    public func getDevice(deviceId: String): ?Device {
        synchronized(devicesMutex) {
            devices.get(deviceId)
        }
    }

    public func listDevices(): ArrayList<Device> {
        let result = ArrayList<Device>()
        synchronized(devicesMutex) {
            for ((_, device) in devices) {
                result.add(device)
            }
        }
        result
    }

    public func setDeviceTrustState(deviceId: String, rawState: String, source!: String = "admin"): Device {
        cleanupExpiredPinPairingSessions()
        let normalized = deviceId.trimAscii()
        if (normalized.size == 0) {
            throw Exception("设备ID不能为空")
        }
        let state = deviceTrustStateFromString(rawState)
        synchronized(devicesMutex) {
            match (devices.get(normalized)) {
                case Some(device) =>
                    if (device.id == "local") {
                        match (state) {
                            case Trusted => ()
                            case _ => throw Exception("local 设备始终保持 trusted")
                        }
                    }
                    applyDeviceTrustState(device, if (device.id == "local") { Trusted } else { state }, source)
                    persistDeviceRecord(device)
                    return device
                case None =>
                    throw Exception("设备不存在: ${normalized}")
            }
        }
    }

    public func startPinPairing(deviceId: String): DevicePinPairingSession {
        cleanupExpiredPinPairingSessions()
        let normalized = deviceId.trimAscii()
        if (normalized.size == 0 || normalized == "local") {
            throw Exception("仅支持远端设备 PIN 配对")
        }

        match (getDevice(normalized)) {
            case Some(_device) => ()
            case None => throw Exception("设备不存在: ${normalized}")
        }

        let session = DevicePinPairingSession()
        session.deviceId = normalized
        session.pin = randomNumericPin(6)
        session.requestedAt = currentTimestamp()
        session.expiresAt = session.requestedAt + 300
        session.source = "pin"
        synchronized(pinPairingMutex) {
            pinPairingSessions.add(normalized, session)
        }
        session
    }

    public func confirmPinPairing(deviceId: String, pin: String): Device {
        cleanupExpiredPinPairingSessions()
        let normalized = deviceId.trimAscii()
        let normalizedPin = pin.trimAscii()
        if (normalized.size == 0 || normalizedPin.size == 0) {
            throw Exception("设备ID 与 PIN 不能为空")
        }

        var matched = false
        synchronized(pinPairingMutex) {
            match (pinPairingSessions.get(normalized)) {
                case Some(session) =>
                    if (session.pin == normalizedPin && session.expiresAt >= currentTimestamp()) {
                        matched = true
                    }
                    if (matched || session.expiresAt < currentTimestamp()) {
                        pinPairingSessions.remove(normalized)
                    }
                case None => ()
            }
        }

        if (!matched) {
            throw Exception("PIN 无效或已过期")
        }

        setDeviceTrustState(normalized, "trusted", source: "pin")
    }

    public func listConnectors(): ArrayList<ConnectorDescriptor> {
        connectorRegistry.listDescriptors()
    }

    public func describeConnector(connectorType: String): ?ConnectorDescriptor {
        connectorRegistry.descriptor(connectorType)
    }

    func persistDeviceRecord(device: Device): Unit {
        device.remembered = true
        discoveryFeature.manualRegister(deviceToRegistryRecord(device))
    }

    func applyDeviceTrustState(device: Device, state: DeviceTrustState, source: String): Unit {
        device.trustState = state
        device.trustSource = source.trimAscii()
        device.trustUpdatedAt = currentTimestamp()
    }

    func preserveDiscoveredState(device: Device, loadPersistedTrust: Bool): Unit {
        var existing: ?Device = None
        synchronized(devicesMutex) {
            existing = devices.get(device.id)
        }

        match (existing) {
            case Some(current) =>
                device.remembered = current.remembered
                device.trustState = current.trustState
                device.trustSource = current.trustSource
                device.trustUpdatedAt = current.trustUpdatedAt
            case None =>
                if (loadPersistedTrust || device.remembered) {
                    device.remembered = true
                } else {
                    device.remembered = false
                }
                if (!loadPersistedTrust) {
                    device.trustState = Unknown
                    device.trustSource = "discovery"
                    device.trustUpdatedAt = currentTimestamp()
                } else if (device.trustUpdatedAt <= 0) {
                    device.trustUpdatedAt = currentTimestamp()
                }
        }
    }

    func cleanupExpiredPinPairingSessions(): Unit {
        let now = currentTimestamp()
        synchronized(pinPairingMutex) {
            let expired = ArrayList<String>()
            for ((deviceId, session) in pinPairingSessions) {
                if (session.expiresAt < now) {
                    expired.add(deviceId)
                }
            }
            for (deviceId in expired) {
                pinPairingSessions.remove(deviceId)
            }
        }
    }

    func ensureRemoteDeviceTrusted(deviceId: String, action: String): Unit {
        if (deviceId.size == 0 || deviceId == "local") {
            return
        }
        match (getDevice(deviceId)) {
            case Some(device) =>
                match (device.trustState) {
                    case Trusted => ()
                    case Blocked => throw Exception("设备已拉黑，拒绝 ${action}: ${deviceId}")
                    case _ => throw Exception("设备尚未授信，拒绝 ${action}: ${deviceId}")
                }
            case None => throw Exception("设备不存在: ${deviceId}")
        }
    }

    func ensureDeviceUsableForTransfer(deviceId: String, action: String): Unit {
        if (deviceId.size == 0 || deviceId == "local") {
            return
        }
        ensureRemoteDeviceTrusted(deviceId, action)
    }

    public func refreshLocalDeviceAddress(): String {
        let displayIP = resolveDiscoveryAdvertiseIp()
        var changed = false
        var deviceSnapshot: ?Device = None

        synchronized(devicesMutex) {
            if (let Some(device) <- devices.get("local")) {
                changed = device.ip != displayIP
                device.ip = displayIP
                device.online = true
                device.lastSeen = currentTimestamp()
                deviceSnapshot = Some(device)
            }
        }

        match (deviceSnapshot) {
            case Some(device) =>
                persistDeviceRecord(device)
                if (changed) {
                    logger.logWarn("system", "本机IP已更新", displayIP, "core/server")
                }
            case None => ()
        }

        displayIP
    }

    func resolveDiscoveryAdvertiseIp(): String {
        let candidates = Array<String>(2, repeat: "")
        candidates[0] = currentPrimaryIp()
        candidates[1] = getLocalIP()
        let resolved = selectDiscoveryAdvertiseIp(config.discoveryAdvertiseIp, candidates)
        if (resolved.size > 0) {
            return resolved
        }
        "127.0.0.1"
    }

    // CFM/P Master boundary: task domain
    public func createTransferTask(
        sourceDevice: String,
        targetDevice: String,
        filePath: String,
        targetPath: String,
        fileCategory!: String = "",
        protocolPreferences!: ArrayList<String> = ArrayList<String>(),
        threads!: Int64 = 0
    ): TransferTask {
        ensureDeviceUsableForTransfer(sourceDevice, "transfer source")
        ensureDeviceUsableForTransfer(targetDevice, "transfer target")

        let task = TransferTask()
        task.id = generateId()
        task.sourceDevice = sourceDevice
        task.targetDevice = targetDevice
        task.filePath = filePath
        task.targetPath = targetPath
        task.status = Pending
        task.createdAt = currentTimestamp()
        task.protocolPreferences = sanitizeTransferProtocolPreferences(protocolPreferences)
        task.threads = if (threads > 0) { threads } else { 0 }

        match (getFileInfo(sourceDevice, filePath)) {
            case Some(meta) =>
                if (meta.category.trimAscii().size == 0) {
                    meta.category = resolveTransferFileCategory(filePath, meta.mimeType, meta.isDir)
                }
                task.metadata = meta
                task.sourceIsDir = meta.isDir
                if (!meta.isDir) {
                    task.totalEntries = 1
                    task.totalBytes = meta.size
                }
            case None => ()
        }

        task.fileCategory = resolveTransferTaskCategory(task, fileCategory)
        if (task.metadata.category.trimAscii().size == 0) {
            task.metadata.category = task.fileCategory
        }
        task.protocolCandidates = buildTransferProtocolCandidates(
            task.fileCategory,
            task.totalBytes,
            task.protocolPreferences,
            task.sourceIsDir || task.metadata.isDir,
            task.threads
        )

        synchronized(tasksMutex) {
            tasks.add(task.id, task)
        }

        spawn { transferEngine.startTransfer(task) }
        task
    }

    public func getTask(taskId: String): ?TransferTask {
        synchronized(tasksMutex) {
            tasks.get(taskId)
        }
    }

    public func listTasks(): ArrayList<TransferTask> {
        let result = ArrayList<TransferTask>()
        synchronized(tasksMutex) {
            for ((_, task) in tasks) {
                result.add(task)
            }
        }
        result
    }

    public func cancelTask(taskId: String): Bool {
        transferEngine.cancelTask(taskId)
    }

    public func listTransferRequests(): ArrayList<TransferRequest> {
        let result = ArrayList<TransferRequest>()
        synchronized(transferRequestsMutex) {
            for ((_, request) in transferRequests) {
                result.add(request)
            }
        }
        result
    }

    public func getTransferRequest(requestId: String): ?TransferRequest {
        synchronized(transferRequestsMutex) {
            transferRequests.get(requestId)
        }
    }

    public func ingestTransferRequest(request: TransferRequest): TransferRequest {
        registerRuntimeRequestCandidate(request.sourceDevice, request.sourceName, request.requesterHost, request.requesterPort)
        registerRuntimeRequestCandidate(request.requesterDeviceId, request.requesterName, request.requesterHost, request.requesterPort)
        ensureIncomingRequestAllowed(request)

        let now = currentTimestamp()
        if (request.id.trimAscii().size == 0) {
            request.id = "req-" + generateId()
        }
        request.targetDevice = "local"
        request.filePath = normalizeVirtualPath(request.filePath)
        request.targetPath = normalizeVirtualPath(request.targetPath)
        if (request.targetPath.size == 0) {
            request.targetPath = "/"
        }
        if (request.metadata.path.size == 0) {
            request.metadata.path = request.filePath
        }
        if (request.metadata.name.size == 0) {
            request.metadata.name = extractVirtualBaseName(request.filePath)
        }
        request.metadata.mimeType = resolvePreviewMimeType(request.metadata.mimeType, request.filePath, request.sourceIsDir)
        request.metadata.category = resolveTransferRequestCategory(request)
        if (request.sourceName.trimAscii().size == 0) {
            request.sourceName = request.sourceDevice
        }
        if (request.requesterName.trimAscii().size == 0) {
            request.requesterName = request.requesterDeviceId
        }
        if (!request.sourceIsDir && request.totalEntries <= 0) {
            request.totalEntries = 1
        }
        if (request.totalBytes <= 0 && request.metadata.size > 0) {
            request.totalBytes = request.metadata.size
        }
        request.fileCategory = request.metadata.category
        request.protocolPreferences = sanitizeTransferProtocolPreferences(request.protocolPreferences)
        if (request.protocolCandidates.size == 0) {
            request.protocolCandidates = buildTransferProtocolCandidates(
                request.fileCategory,
                request.totalBytes,
                request.protocolPreferences,
                request.sourceIsDir,
                0
            )
        } else {
            request.protocolCandidates = sanitizeTransferProtocolPreferences(request.protocolCandidates)
        }
        if (request.createdAt <= 0) {
            request.createdAt = now
        }
        request.updatedAt = now
        request.status = RequestPending
        request.resolvedAt = 0
        request.acceptedTaskId = ""
        request.responseMessage = ""

        synchronized(transferRequestsMutex) {
            transferRequests.add(request.id, request)
        }
        request
    }

    public func sendTransferRequest(
        sourceDevice: String,
        targetDevice: String,
        filePath: String,
        targetPath: String,
        note: String,
        protocolPreferences!: ArrayList<String> = ArrayList<String>()
    ): TransferRequest {
        ensureDeviceUsableForTransfer(sourceDevice, "transfer request source")
        ensureDeviceUsableForTransfer(targetDevice, "transfer request target")

        let request = buildTransferRequest(sourceDevice, filePath, targetPath, note, protocolPreferences: protocolPreferences)
        if (targetDevice == "local") {
            return ingestTransferRequest(request)
        }

        match (openRemoteNodeClient(targetDevice)) {
            case Some(client) =>
                try {
                    let ok = client.pushTransferRequest(buildTransferRequestIngressPayload(request))
                    client.close()
                    if (!ok) {
                        throw Exception("对端未接受传输请求")
                    }
                    return request
                } catch (e: Exception) {
                    client.close()
                    throw e
                }
            case None =>
                throw Exception("目标设备当前不支持传输请求投递: ${targetDevice}")
        }
    }

    public func acceptTransferRequest(requestId: String, targetPath: String): TransferTask {
        var requestSnapshot: ?TransferRequest = None
        synchronized(transferRequestsMutex) {
            match (transferRequests.get(requestId)) {
                case Some(request) =>
                    match (request.status) {
                        case RequestPending => ()
                        case _ => throw Exception("传输请求当前不可接受: ${requestId}")
                    }
                    requestSnapshot = Some(request)
                case None =>
                    throw Exception("传输请求不存在: ${requestId}")
            }
        }

        match (requestSnapshot) {
            case Some(request) =>
                let resolvedSource = resolveTransferRequestSourceDevice(request)
                let resolvedTargetPath = normalizeVirtualPath(if (targetPath.trimAscii().size > 0) { targetPath } else { request.targetPath })
                let task = createTransferTask(
                    resolvedSource,
                    "local",
                    request.filePath,
                    resolvedTargetPath,
                    fileCategory: request.fileCategory,
                    protocolPreferences: request.protocolPreferences
                )
                let now = currentTimestamp()
                synchronized(transferRequestsMutex) {
                    if (let Some(stored) <- transferRequests.get(requestId)) {
                        stored.status = RequestAccepted
                        stored.targetPath = resolvedTargetPath
                        stored.updatedAt = now
                        stored.resolvedAt = now
                        stored.responseMessage = "已接受传输请求"
                        stored.acceptedTaskId = task.id
                    }
                }
                task
            case None =>
                throw Exception("传输请求不存在: ${requestId}")
        }
    }

    public func rejectTransferRequest(requestId: String, reason: String): ?TransferRequest {
        let now = currentTimestamp()
        synchronized(transferRequestsMutex) {
            match (transferRequests.get(requestId)) {
                case Some(request) =>
                    match (request.status) {
                        case RequestPending => ()
                        case _ => return Some(request)
                    }
                    request.status = RequestRejected
                    request.updatedAt = now
                    request.resolvedAt = now
                    request.responseMessage = if (reason.trimAscii().size > 0) { reason.trimAscii() } else { "已拒绝传输请求" }
                    Some(request)
                case None =>
                    None
            }
        }
    }

    public func cancelTransferRequest(requestId: String, reason: String): ?TransferRequest {
        let now = currentTimestamp()
        synchronized(transferRequestsMutex) {
            match (transferRequests.get(requestId)) {
                case Some(request) =>
                    match (request.status) {
                        case RequestPending => ()
                        case _ => return Some(request)
                    }
                    request.status = RequestCancelled
                    request.updatedAt = now
                    request.resolvedAt = now
                    request.responseMessage = if (reason.trimAscii().size > 0) { reason.trimAscii() } else { "已取消传输请求" }
                    Some(request)
                case None =>
                    None
            }
        }
    }

    func updateTaskStatus(taskId: String, status: TaskStatus, progress: Float64): Unit {
        synchronized(tasksMutex) {
            if (let Some(task) <- tasks.get(taskId)) {
                task.status = status
                task.progress = progress
                task.updatedAt = currentTimestamp()
            }
        }
    }

    // CFM/P Master boundary: filesystem domain
    public func listDir(deviceId: String, path: String): ArrayList<FileEntry> {
        match (fileManager.getProvider(deviceId)) {
            case Some(provider) => provider.listDir(path)
            case None =>
                match (openRemoteFileClient(deviceId)) {
                    case Some(client) =>
                        try {
                            let entries = client.listDir(path)
                            client.close()
                            return entries
                        } catch (e: Exception) {
                            client.close()
                            logger.logWarn("fs", "远端目录读取失败", "${deviceId}:${path} ${e.message}", "core/server")
                        }
                    case None => ()
                }
                ArrayList<FileEntry>()
        }
    }

    public func getFileInfo(deviceId: String, path: String): ?FileMetadata {
        match (fileManager.getProvider(deviceId)) {
            case Some(provider) =>
                try {
                    return Some(provider.getFileInfo(path))
                } catch (e: Exception) {
                    logger.logWarn("fs", "文件信息读取失败", "${deviceId}:${path} ${e.message}", "core/server")
                    return None
                }
            case None =>
                match (openRemoteFileClient(deviceId)) {
                    case Some(client) =>
                        try {
                            let info = client.getFileInfo(path)
                            client.close()
                            return info
                        } catch (e: Exception) {
                            client.close()
                            logger.logWarn("fs", "远端文件信息读取失败", "${deviceId}:${path} ${e.message}", "core/server")
                        }
                    case None => ()
                }
                None
        }
    }

    public func readFile(deviceId: String, path: String, offset: Int64, length: Int64): Array<UInt8> {
        match (fileManager.getProvider(deviceId)) {
            case Some(provider) => provider.readFile(path, offset, length)
            case None =>
                match (openRemoteFileClient(deviceId)) {
                    case Some(client) =>
                        try {
                            let bytes = client.readRange(path, offset, length)
                            client.close()
                            return bytes
                        } catch (e: Exception) {
                            client.close()
                            logger.logWarn("fs", "远端文件读取失败", "${deviceId}:${path} ${e.message}", "core/server")
                        }
                    case None => ()
                }
                Array<UInt8>(0, repeat: 0)
        }
    }

    public func writeFile(deviceId: String, path: String, data: Array<UInt8>, offset: Int64): Unit {
        fileManager.writeFile(deviceId, path, data, offset)
    }

    public func createDir(deviceId: String, path: String): Bool {
        match (fileManager.getProvider(deviceId)) {
            case Some(provider) =>
                try {
                    provider.createDir(path)
                    return true
                } catch (e: Exception) {
                    logger.logWarn("fs", "目录创建失败", "${deviceId}:${path} ${e.message}", "core/server")
                    return false
                }
            case None =>
                match (openRemoteFileClient(deviceId)) {
                    case Some(client) =>
                        try {
                            let ok = client.createDir(path)
                            client.close()
                            return ok
                        } catch (e: Exception) {
                            client.close()
                            logger.logWarn("fs", "远端目录创建失败", "${deviceId}:${path} ${e.message}", "core/server")
                        }
                    case None => ()
                }
                false
        }
    }

    // CFM/P Master boundary: security + peer domain
    public func getSecurityMode(): String {
        if (!profile.supportsPeerTransfer) {
            return "plain"
        }
        peerTransferFeature.getSecurityMode()
    }

    public func setSecurityMode(rawMode: String): String {
        if (!profile.supportsPeerTransfer) {
            return "plain"
        }
        let mode = peerTransferFeature.setSecurityMode(rawMode)
        logger.logInfo("peer", "安全模式已更新", mode, "core/server")
        mode
    }

    public func beginPeerHandshake(peerId: String): String {
        if (!profile.supportsPeerTransfer) {
            return ""
        }
        peerTransferFeature.beginHandshake(peerId)
    }

    public func acceptPeerUpload(targetPath: String, peerId: String, token: String, payload: Array<UInt8>): PeerTransferResult {
        if (!profile.supportsPeerTransfer) {
            let result = PeerTransferResult()
            result.success = false
            result.message = "peer transfer disabled in current edition"
            return result
        }
        peerTransferFeature.acceptUpload(targetPath, peerId, token, payload)
    }

    public func providePeerDownload(sourcePath: String, peerId: String, token: String): PeerDownloadPayload {
        if (!profile.supportsPeerTransfer) {
            let result = PeerDownloadPayload()
            result.result.success = false
            result.result.message = "peer transfer disabled in current edition"
            return result
        }
        peerTransferFeature.provideDownload(sourcePath, peerId, token)
    }

    public func pullPeerLocal(sourcePath: String, targetPath: String): PeerTransferResult {
        if (!profile.supportsPeerTransfer) {
            let result = PeerTransferResult()
            result.success = false
            result.message = "peer transfer disabled in current edition"
            return result
        }
        peerTransferFeature.pullLocalToPath(sourcePath, targetPath)
    }

    // CFM/P Master boundary: monitor domain
    public func monitorSystem(): JsonObject {
        monitorFeature.systemSnapshot(uptimeSeconds())
    }

    public func monitorCPU(): JsonObject {
        monitorFeature.cpuSnapshot()
    }

    public func monitorMemory(): JsonObject {
        monitorFeature.memorySnapshot()
    }

    public func monitorDisk(path: String): JsonObject {
        monitorFeature.diskSnapshot(path)
    }

    public func monitorNetwork(): JsonObject {
        monitorFeature.networkSnapshot()
    }

    public func monitorTemperature(): JsonObject {
        monitorFeature.temperatureSnapshot()
    }

    public func monitorUptime(): JsonObject {
        monitorFeature.uptimeSnapshot(uptimeSeconds())
    }

    func currentPrimaryIp(): String {
        match (getDevice("local")) {
            case Some(device) => device.ip
            case None => ""
        }
    }

    func ensureParentDir(path: String): Unit {
        let runes = path.toRuneArray()
        var slash: Int64 = -1
        for (i in 0..runes.size) {
            if (runes[i] == r'/') {
                slash = i
            }
        }
        if (slash <= 0) {
            return
        }
        let parent = strSubstring(path, 0, slash)
        try {
            Directory.create(parent, recursive: true)
        } catch (_: Exception) {}
    }

    func isDeviceOnline(deviceId: String): Bool {
        match (getDevice(deviceId)) {
            case Some(device) => device.online
            case None => false
        }
    }

    func writeRelayTarget(deviceId: String, path: String, payload: Array<UInt8>): Bool {
        match (fileManager.getProvider(deviceId)) {
            case Some(_provider) =>
                try {
                    writeFile(deviceId, path, payload, 0)
                    return true
                } catch (_: Exception) {
                    return false
                }
            case None =>
                match (openRemoteFileClient(deviceId)) {
                    case Some(client) =>
                        try {
                            let ok = client.uploadFile(
                                "relay-cache",
                                path,
                                payload.size,
                                2 * 1024 * 1024,
                                { offset: Int64, length: Int64 =>
                                    sliceTransferBytes(payload, offset, length)
                                }
                            )
                            client.close()
                            return ok
                        } catch (_: Exception) {
                            client.close()
                            return false
                        }
                    case None => false
                }
        }
    }

    func writeChunkTarget(deviceId: String, path: String, payload: Array<UInt8>, offset: Int64): Bool {
        try {
            writeFile(deviceId, path, payload, offset)
            true
        } catch (_: Exception) {
            false
        }
    }

    // CFM/P Master boundary: relay + whitelist domain
    public func createRelayJob(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        payload: Array<UInt8>
    ): RelayJob {
        if (!profile.supportsRelay) {
            let job = RelayJob()
            job.status = "disabled"
            job.message = "relay disabled in current edition"
            job.targetDevice = targetDevice
            job.targetPath = targetPath
            job.fileName = fileName
            return job
        }
        ensureDeviceUsableForTransfer(targetDevice, "relay target")
        relayFeature.createJobFromPayload(sourceDevice, targetDevice, targetPath, fileName, payload)
    }

    public func listRelayJobs(): ArrayList<RelayJob> {
        if (!profile.supportsRelay) {
            return ArrayList<RelayJob>()
        }
        relayFeature.listJobs()
    }

    public func getRelayJob(jobId: String): ?RelayJob {
        if (!profile.supportsRelay) {
            return None
        }
        relayFeature.getJob(jobId)
    }

    public func relayCacheDescriptor(jobId: String): ?(String, String) {
        if (!profile.supportsRelay) {
            return None
        }
        relayFeature.cacheDescriptor(jobId)
    }

    public func createRelayTextRecord(sourceDevice: String, fileName: String, content: String): RelayJob {
        createRelayTextRecord(sourceDevice, fileName, content, "/tmpSL")
    }

    public func createRelayTextRecord(sourceDevice: String, fileName: String, content: String, targetPath: String): RelayJob {
        if (!profile.supportsRelay) {
            let job = RelayJob()
            job.status = "disabled"
            job.message = "relay disabled in current edition"
            job.fileName = fileName
            job.recordKind = "text"
            return job
        }
        relayFeature.createTextRecord(sourceDevice, fileName, content, targetPath)
    }

    public func retryRelayJob(jobId: String): ?RelayJob {
        if (!profile.supportsRelay) {
            return None
        }
        relayFeature.retryJob(jobId)
    }

    public func deleteRelayRecord(jobId: String): Bool {
        if (!profile.supportsRelay) {
            return false
        }
        relayFeature.deleteJob(jobId)
    }

    public func cancelRelayJob(jobId: String): Bool {
        if (!profile.supportsRelay) {
            return false
        }
        relayFeature.cancelJob(jobId)
    }

    public func upsertWhitelistRule(sourceDevice: String, targetDevice: String, enabled: Bool): WhitelistRule {
        if (!profile.supportsWhitelist) {
            let rule = WhitelistRule()
            rule.sourceDevice = sourceDevice
            rule.targetDevice = targetDevice
            rule.enabled = false
            return rule
        }
        ensureDeviceUsableForTransfer(targetDevice, "whitelist target")
        relayFeature.upsertRule(sourceDevice, targetDevice, enabled)
    }

    public func listWhitelistRules(targetDevice: String): ArrayList<WhitelistRule> {
        if (!profile.supportsWhitelist) {
            return ArrayList<WhitelistRule>()
        }
        relayFeature.listRules(targetDevice)
    }

    public func setWhitelistRuleEnabled(sourceDevice: String, targetDevice: String, enabled: Bool): ?WhitelistRule {
        if (!profile.supportsWhitelist) {
            return None
        }
        relayFeature.setRuleEnabled(sourceDevice, targetDevice, enabled)
    }

    public func removeWhitelistRule(sourceDevice: String, targetDevice: String): Bool {
        if (!profile.supportsWhitelist) {
            return false
        }
        relayFeature.removeRule(sourceDevice, targetDevice)
    }

    public func cleanupRelayJobs(statusFilter: String, olderThan: Int64): Int64 {
        if (!profile.supportsRelay) {
            return 0
        }
        relayFeature.cleanupJobs(statusFilter, olderThan)
    }

    public func restoreRelayJob(jobId: String, targetDevice: String, targetPath: String): Bool {
        if (!profile.supportsRelay) {
            return false
        }
        ensureDeviceUsableForTransfer(targetDevice, "relay restore target")
        relayFeature.restoreJob(jobId, targetDevice, targetPath)
    }

    public func relayStats(): JsonObject {
        if (!profile.supportsRelay) {
            return JsonObject()
                .putBool("enabled", false)
                .putInt("total", 0)
        }
        relayFeature.stats()
    }

    // CFM/P Master boundary: favorites domain
    public func favoriteStoreMode(): String {
        if (!profile.supportsFavorites) {
            return "disabled"
        }
        favoritesFeature.mode()
    }

    public func listFavorites(): ArrayList<FavoriteEntry> {
        if (!profile.supportsFavorites) {
            return ArrayList<FavoriteEntry>()
        }
        favoritesFeature.list()
    }

    public func replaceFavorites(entries: ArrayList<FavoriteEntry>): ArrayList<FavoriteEntry> {
        if (!profile.supportsFavorites) {
            return ArrayList<FavoriteEntry>()
        }
        favoritesFeature.replace(entries)
    }

    // CFM/P Master boundary: chunk transfer domain
    public func createChunkSession(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        fileSize: Int64,
        chunkSize: Int64
    ): ChunkSession {
        chunkTransferFeature.createSession(sourceDevice, targetDevice, targetPath, fileName, fileSize, chunkSize)
    }

    public func writeChunkSession(sessionId: String, index: Int64, payload: Array<UInt8>): ChunkWriteResult {
        chunkTransferFeature.writeChunk(sessionId, index, payload)
    }

    public func chunkSessionManifest(sessionId: String): JsonObject {
        chunkTransferFeature.sessionManifest(sessionId)
    }

    public func completeChunkSession(sessionId: String): ChunkCompleteResult {
        chunkTransferFeature.completeSession(sessionId)
    }

    public func summarizeTransferSource(deviceId: String, path: String): JsonObject {
        let plan = buildTransferPlan(deviceId, path)
        JsonObject()
            .putBool("success", true)
            .putBool("sourceIsDir", plan.sourceIsDir)
            .put("rootName", plan.rootName)
            .putInt("totalDirs", plan.dirRelPaths.size)
            .putInt("totalFiles", plan.files.size)
            .putInt("totalEntries", plan.totalEntries)
            .putInt("totalBytes", plan.totalBytes)
            .put("totalBytesText", formatBytes(plan.totalBytes))
    }

    func openRemoteFileClient(deviceId: String): ?ConnectorFileClient {
        if (deviceId == "local") {
            return None
        }
        ensureRemoteDeviceTrusted(deviceId, "remote filesystem access")
        match (getDevice(deviceId)) {
            case Some(device) =>
                if (defaultConnectorTypeForDevice(device) == "local-fs" || defaultConnectorTypeForDevice(device) == "manual") {
                    return None
                }
                connectorRegistry.openFileClient(device)
            case None => None
        }
    }

    func openRemoteNodeClient(deviceId: String): ?SoonLinkNodeClient {
        if (deviceId == "local") {
            return None
        }
        ensureRemoteDeviceTrusted(deviceId, "transfer request delivery")
        match (getDevice(deviceId)) {
            case Some(device) =>
                if (defaultConnectorTypeForDevice(device) != "soonlink-http") {
                    return None
                }
                if (device.ip.trimAscii().size == 0 || device.port <= 0) {
                    return None
                }
                Some(SoonLinkNodeClient(device.ip.trimAscii(), device.port))
            case None =>
                None
        }
    }

    func ensureIncomingRequestAllowed(request: TransferRequest): Unit {
        ensureKnownDeviceNotBlocked(request.requesterDeviceId, "请求发起节点")
        if (request.sourceDevice != request.requesterDeviceId) {
            ensureKnownDeviceNotBlocked(request.sourceDevice, "源节点")
        }
    }

    func ensureKnownDeviceNotBlocked(deviceId: String, label: String): Unit {
        let normalized = deviceId.trimAscii()
        if (normalized.size == 0 || normalized == "local") {
            return
        }
        match (getDevice(normalized)) {
            case Some(device) =>
                match (device.trustState) {
                    case Blocked => throw Exception("${label}已拉黑，拒绝接收传输请求: ${normalized}")
                    case _ => ()
                }
            case None => ()
        }
    }

    func registerRuntimeRequestCandidate(deviceId: String, name: String, host: String, port: Int64): Unit {
        let normalizedId = deviceId.trimAscii()
        let normalizedHost = host.trimAscii()
        if (normalizedId.size == 0 || normalizedId == "local" || normalizedId == config.nodeId.trimAscii()) {
            return
        }
        if (normalizedHost.size == 0 || port <= 0) {
            return
        }
        match (getDevice(normalizedId)) {
            case Some(_) =>
                return
            case None => ()
        }

        let device = Device(
            id: normalizedId,
            name: if (name.trimAscii().size > 0) { name.trimAscii() } else { normalizedId },
            deviceType: "node",
            ip: normalizedHost,
            port: port,
            online: true
        )
        applyDiscoveredDeviceCapabilities(device)
        applyDefaultDeviceConnector(device)
        applyDeviceTrustState(device, Unknown, "request")
        registerDevice(device)
    }

    func buildTransferRequest(
        sourceDevice: String,
        filePath: String,
        targetPath: String,
        note: String,
        protocolPreferences!: ArrayList<String> = ArrayList<String>()
    ): TransferRequest {
        let normalizedSource = sourceDevice.trimAscii()
        let normalizedFilePath = normalizeVirtualPath(filePath)
        let plan = buildTransferPlan(normalizedSource, normalizedFilePath)
        let request = TransferRequest()
        request.id = "req-" + generateId()
        request.requesterDeviceId = config.nodeId.trimAscii()
        request.requesterName = resolveNodeDisplayName()
        request.requesterHost = resolveDiscoveryAdvertiseIp()
        request.requesterPort = Int64(config.webPort)
        request.sourceDevice = resolveTransferRequestSourceDeviceId(normalizedSource)
        request.sourceName = resolveTransferRequestSourceName(normalizedSource)
        request.targetDevice = "local"
        request.filePath = normalizedFilePath
        request.targetPath = normalizeVirtualPath(targetPath)
        request.sourceIsDir = plan.sourceIsDir
        request.totalEntries = plan.totalEntries
        request.totalBytes = plan.totalBytes
        request.note = note.trimAscii()
        request.protocolPreferences = sanitizeTransferProtocolPreferences(protocolPreferences)

        match (getFileInfo(normalizedSource, normalizedFilePath)) {
            case Some(meta) =>
                if (meta.category.trimAscii().size == 0) {
                    meta.category = resolveTransferFileCategory(normalizedFilePath, meta.mimeType, meta.isDir)
                }
                request.metadata = meta
            case None =>
                request.metadata.name = plan.rootName
                request.metadata.path = normalizedFilePath
                request.metadata.isDir = plan.sourceIsDir
                request.metadata.size = plan.totalBytes
                request.metadata.mimeType = resolvePreviewMimeType("", normalizedFilePath, plan.sourceIsDir)
        }

        if (request.metadata.path.size == 0) {
            request.metadata.path = normalizedFilePath
        }
        if (request.metadata.name.size == 0) {
            request.metadata.name = plan.rootName
        }
        request.metadata.category = resolveTransferRequestCategory(request)
        request.fileCategory = request.metadata.category
        request.protocolCandidates = buildTransferProtocolCandidates(
            request.fileCategory,
            request.totalBytes,
            request.protocolPreferences,
            request.sourceIsDir,
            0
        )
        if (request.targetPath.size == 0) {
            request.targetPath = "/"
        }
        request
    }

    func resolveTransferTaskCategory(task: TransferTask, preferredCategory: String): String {
        let normalizedPreferred = normalizeRequestedTransferCategory(preferredCategory)
        if (normalizedPreferred.size > 0) {
            return normalizedPreferred
        }
        if (task.metadata.category.trimAscii().size > 0) {
            return task.metadata.category.trimAscii().toLower()
        }
        resolveTransferFileCategory(task.filePath, task.metadata.mimeType, task.sourceIsDir || task.metadata.isDir)
    }

    func resolveTransferRequestCategory(request: TransferRequest): String {
        let normalizedRequested = normalizeRequestedTransferCategory(request.fileCategory)
        if (normalizedRequested.size > 0) {
            return normalizedRequested
        }
        if (request.metadata.category.trimAscii().size > 0) {
            return request.metadata.category.trimAscii().toLower()
        }
        resolveTransferFileCategory(request.filePath, request.metadata.mimeType, request.sourceIsDir || request.metadata.isDir)
    }

    func normalizeRequestedTransferCategory(raw: String): String {
        let normalized = raw.trimAscii().toLower()
        if (normalized == "directory") { return "directory" }
        if (normalized == "image") { return "image" }
        if (normalized == "video") { return "video" }
        if (normalized == "audio") { return "audio" }
        if (normalized == "document") { return "document" }
        if (normalized == "archive") { return "archive" }
        if (normalized == "code") { return "code" }
        if (normalized == "text") { return "text" }
        if (normalized == "unknown") { return "unknown" }
        ""
    }

    func resolveTransferRequestSourceDeviceId(sourceDevice: String): String {
        let normalized = sourceDevice.trimAscii()
        if (normalized == "local" || normalized.size == 0) {
            let publicId = config.nodeId.trimAscii()
            if (publicId.size == 0) {
                throw Exception("当前节点未配置 nodeId，暂时无法向对端发送传输请求")
            }
            return publicId
        }
        normalized
    }

    func resolveTransferRequestSourceName(sourceDevice: String): String {
        let normalized = sourceDevice.trimAscii()
        if (normalized == "local" || normalized.size == 0) {
            return resolveNodeDisplayName()
        }
        match (getDevice(normalized)) {
            case Some(device) =>
                if (device.name.trimAscii().size > 0) {
                    device.name
                } else {
                    normalized
                }
            case None =>
                normalized
        }
    }

    func resolveTransferRequestSourceDevice(request: TransferRequest): String {
        let normalized = request.sourceDevice.trimAscii()
        if (normalized.size == 0) {
            throw Exception("传输请求缺少源设备ID")
        }
        if (normalized == config.nodeId.trimAscii()) {
            return "local"
        }
        match (getDevice(normalized)) {
            case Some(_) =>
                normalized
            case None =>
                throw Exception("源节点尚未登记或不可用: ${normalized}")
        }
    }

    func buildTransferRequestIngressPayload(request: TransferRequest): String {
        let preferences = JsonArray()
        for (value in request.protocolPreferences) {
            preferences.addStr(value)
        }
        let candidates = JsonArray()
        for (value in request.protocolCandidates) {
            candidates.addStr(value)
        }
        JsonObject()
            .put("id", request.id)
            .put("requesterDeviceId", request.requesterDeviceId)
            .put("requesterName", request.requesterName)
            .put("requesterHost", request.requesterHost)
            .putInt("requesterPort", request.requesterPort)
            .put("sourceDevice", request.sourceDevice)
            .put("sourceName", request.sourceName)
            .put("filePath", request.filePath)
            .put("targetPath", request.targetPath)
            .put("fileName", request.metadata.name)
            .put("mimeType", request.metadata.mimeType)
            .put("fileCategory", request.fileCategory)
            .putInt("sourceSize", request.metadata.size)
            .putInt("sourceModified", request.metadata.modified)
            .putBool("sourceIsDir", request.sourceIsDir)
            .putInt("totalEntries", request.totalEntries)
            .putInt("totalBytes", request.totalBytes)
            .putArr("protocolPreferences", preferences)
            .putArr("protocolCandidates", candidates)
            .put("note", request.note)
            .putInt("createdAt", request.createdAt)
            .toString()
    }

    func normalizeManagedDeviceRecord(record: DeviceRegistryRecord, existing: ?Device): String {
        record.id = record.id.trimAscii()
        record.name = record.name.trimAscii()
        record.deviceType = record.deviceType.trimAscii().toLower()
        record.connectorType = normalizeConnectorType(record.connectorType)
        record.endpointScheme = normalizeEndpointScheme(record.endpointScheme)
        record.endpointBasePath = normalizeEndpointBasePath(record.endpointBasePath)
        record.ip = record.ip.trimAscii()

        let validationError = validateManagedDeviceRecord(record)
        if (validationError.size > 0) {
            return validationError
        }

        if (record.name.size == 0) {
            record.name = record.id
        }
        if (record.deviceType.size == 0) {
            record.deviceType = "remote"
        }
        if (record.port <= 0) {
            record.port = Int64(config.webPort)
        }

        match (existing) {
            case Some(device) =>
                record.online = device.online
                record.lastSeen = if (device.lastSeen > 0) { device.lastSeen } else { currentTimestamp() }
                record.trustState = device.trustState
                record.trustSource = device.trustSource
                record.trustUpdatedAt = device.trustUpdatedAt
                if (record.connectorType.size == 0) {
                    record.connectorType = defaultConnectorTypeForDevice(device)
                }
            case None =>
                record.online = false
                record.lastSeen = if (record.lastSeen > 0) { record.lastSeen } else { currentTimestamp() }
                record.trustState = Unknown
                record.trustSource = "manual"
                record.trustUpdatedAt = currentTimestamp()
        }

        if (record.connectorType.size == 0) {
            record.connectorType = "soonlink-http"
        }
        let normalizedDevice = registryRecordToDevice(record)
        applyDefaultDeviceEndpoint(normalizedDevice)
        record.endpointScheme = normalizedDevice.endpointScheme
        record.endpointBasePath = normalizedDevice.endpointBasePath
        ""
    }

    func executeTransferTask(task: TransferTask, onProgress: (Float64) -> Unit): Bool {
        try {
            let plan = buildTransferPlan(task.sourceDevice, task.filePath)
            synchronized(tasksMutex) {
                task.metadata.name = if (task.metadata.name.size > 0) { task.metadata.name } else { plan.rootName }
                task.sourceIsDir = plan.sourceIsDir
                task.totalEntries = plan.totalEntries
                task.completedEntries = 0
                task.totalBytes = plan.totalBytes
                task.transferredBytes = 0
                task.currentItem = plan.rootName
                task.error = ""
                task.updatedAt = currentTimestamp()
            }
            onProgress(0.0)

            if (plan.sourceIsDir) {
                return executeDirectoryTransfer(task, plan, onProgress)
            }
            if (plan.files.size == 0) {
                throw Exception("empty transfer plan")
            }
            let single = plan.files[0]
            let targetFilePath = composeTaskTargetFilePath(task.targetPath, plan.rootName)
            return transferPlannedFile(task, single, targetFilePath, 0, 0, onProgress)
        } catch (e: Exception) {
            synchronized(tasksMutex) {
                task.error = "传输失败: ${e.message}"
                task.updatedAt = currentTimestamp()
            }
            false
        }
    }

    func executeDirectoryTransfer(task: TransferTask, plan: TransferPlan, onProgress: (Float64) -> Unit): Bool {
        if (plan.rootName.size == 0) {
            throw Exception("invalid source directory")
        }

        let targetRoot = composeTaskTargetDir(task.targetPath, plan.rootName)
        var completedEntries: Int64 = 0
        var transferredBytes: Int64 = 0

        for (relDir in plan.dirRelPaths) {
            if (isTaskCancelled(task)) {
                return false
            }
            let dirPath = if (relDir.size == 0) { targetRoot } else { joinVirtualPath(targetRoot, relDir) }
            if (!createDir(task.targetDevice, dirPath)) {
                throw Exception("目标目录创建失败: ${dirPath}")
            }
            completedEntries += 1
            updateTaskTransferState(task, transferredBytes, completedEntries, dirPath, onProgress)
        }

        for (item in plan.files) {
            if (isTaskCancelled(task)) {
                return false
            }
            let targetFilePath = joinVirtualPath(targetRoot, item.relativePath)
            let ok = transferPlannedFile(task, item, targetFilePath, transferredBytes, completedEntries, onProgress)
            if (!ok) {
                return false
            }
            transferredBytes += item.size
            completedEntries += 1
        }

        updateTaskTransferState(task, transferredBytes, completedEntries, targetRoot, onProgress)
        true
    }

    func transferPlannedFile(
        task: TransferTask,
        item: TransferFilePlanItem,
        targetFilePath: String,
        transferredBefore: Int64,
        completedBefore: Int64,
        onProgress: (Float64) -> Unit
    ): Bool {
        match (fileManager.getProvider(task.targetDevice)) {
            case Some(provider) =>
                let chunkSize = resolveTaskChunkSize(task)
                if (item.size == 0) {
                    provider.writeFile(targetFilePath, Array<UInt8>(0, repeat: 0), 0)
                    updateTaskTransferState(task, transferredBefore, completedBefore + 1, targetFilePath, onProgress)
                    return true
                }

                var offset: Int64 = 0
                while (offset < item.size) {
                    if (isTaskCancelled(task)) {
                        return false
                    }
                    let nextSize = if (item.size - offset > chunkSize) { chunkSize } else { item.size - offset }
                    let payload = readFile(task.sourceDevice, item.sourcePath, offset, nextSize)
                    if (payload.size <= 0 && nextSize > 0) {
                        throw Exception("源文件读取中断: ${item.sourcePath}")
                    }
                    provider.writeFile(targetFilePath, payload, offset)
                    offset += payload.size
                    updateTaskTransferState(task, transferredBefore + offset, completedBefore, targetFilePath, onProgress)
                }
                updateTaskTransferState(task, transferredBefore + item.size, completedBefore + 1, targetFilePath, onProgress)
                true
            case None =>
                match (openRemoteFileClient(task.targetDevice)) {
                    case Some(client) =>
                        try {
                            let ok = client.uploadFile(
                                task.sourceDevice,
                                targetFilePath,
                                item.size,
                                resolveTaskChunkSize(task),
                                { offset: Int64, length: Int64 =>
                                    readFile(task.sourceDevice, item.sourcePath, offset, length)
                                }
                            )
                            client.close()
                            if (ok) {
                                updateTaskTransferState(task, transferredBefore + item.size, completedBefore + 1, targetFilePath, onProgress)
                                return true
                            }
                            synchronized(tasksMutex) {
                                task.error = "远端写入失败: ${task.targetDevice}:${targetFilePath}"
                                task.updatedAt = currentTimestamp()
                            }
                            return false
                        } catch (e: Exception) {
                            client.close()
                            synchronized(tasksMutex) {
                                task.error = "远端写入失败: ${e.message}"
                                task.updatedAt = currentTimestamp()
                            }
                            return false
                        }
                    case None =>
                        synchronized(tasksMutex) {
                            task.error = "目标设备不是可用 SoonLink 节点: ${task.targetDevice}"
                            task.updatedAt = currentTimestamp()
                        }
                        false
                }
        }
    }

    func buildTransferPlan(sourceDevice: String, sourcePath: String): TransferPlan {
        match (getFileInfo(sourceDevice, sourcePath)) {
            case Some(info) =>
                let plan = TransferPlan()
                plan.sourcePath = sourcePath
                plan.sourceIsDir = info.isDir
                plan.rootName = deriveTransferRootName(info, sourcePath)

                if (!info.isDir) {
                    let item = TransferFilePlanItem()
                    item.sourcePath = sourcePath
                    item.relativePath = plan.rootName
                    item.size = info.size
                    plan.files.add(item)
                    plan.totalEntries = 1
                    plan.totalBytes = info.size
                    return plan
                }

                if (normalizeVirtualPath(sourcePath) == "/") {
                    throw Exception("暂不支持直接传输根目录")
                }
                plan.dirRelPaths.add("")
                plan.totalEntries = 1
                appendDirectoryPlan(plan, sourceDevice, sourcePath, "")
                plan
            case None =>
                throw Exception("源项不存在: ${sourceDevice}:${sourcePath}")
        }
    }

    func appendDirectoryPlan(plan: TransferPlan, deviceId: String, currentPath: String, relativeBase: String): Unit {
        let entries = listDir(deviceId, currentPath)
        for (entry in entries) {
            let name = if (entry.name.size > 0) { entry.name } else { extractVirtualBaseName(entry.path) }
            let relativePath = if (relativeBase.size > 0) { "${relativeBase}/${name}" } else { name }
            if (entry.isDir) {
                plan.dirRelPaths.add(relativePath)
                plan.totalEntries += 1
                appendDirectoryPlan(plan, deviceId, entry.path, relativePath)
                continue
            }

            let item = TransferFilePlanItem()
            item.sourcePath = entry.path
            item.relativePath = relativePath
            match (getFileInfo(deviceId, entry.path)) {
                case Some(info) => item.size = info.size
                case None => item.size = entry.size
            }
            plan.files.add(item)
            plan.totalEntries += 1
            plan.totalBytes += item.size
        }
    }

    func deriveTransferRootName(info: FileMetadata, sourcePath: String): String {
        if (info.name.size > 0) {
            return sanitizeTransferSegment(info.name)
        }
        sanitizeTransferSegment(extractVirtualBaseName(sourcePath))
    }

    func resolveTaskChunkSize(task: TransferTask): Int64 {
        if (task.chunkSize > 0) {
            return task.chunkSize
        }
        2 * 1024 * 1024
    }

    func updateTaskTransferState(
        task: TransferTask,
        transferredBytes: Int64,
        completedEntries: Int64,
        currentItem: String,
        onProgress: (Float64) -> Unit
    ): Unit {
        var progress = 0.0
        let totalBytes = if (task.totalBytes > 0) { task.totalBytes } else { 0 }
        let totalEntries = if (task.totalEntries > 0) { task.totalEntries } else { 0 }
        if (totalBytes > 0) {
            progress = Float64(transferredBytes) / Float64(totalBytes) * 100.0
        } else if (totalEntries > 0) {
            progress = Float64(completedEntries) / Float64(totalEntries) * 100.0
        }
        if (progress > 100.0) {
            progress = 100.0
        }

        synchronized(tasksMutex) {
            task.transferredBytes = transferredBytes
            task.completedEntries = completedEntries
            task.currentItem = currentItem
            task.progress = progress
            task.updatedAt = currentTimestamp()
        }
        onProgress(progress)
    }

    func isTaskCancelled(task: TransferTask): Bool {
        synchronized(tasksMutex) {
            match (task.status) {
                case Cancelled => true
                case _ => false
            }
        }
    }
}

class TransferPlan {
    var sourcePath: String = ""
    var rootName: String = ""
    var sourceIsDir: Bool = false
    var dirRelPaths: ArrayList<String> = ArrayList<String>()
    var files: ArrayList<TransferFilePlanItem> = ArrayList<TransferFilePlanItem>()
    var totalEntries: Int64 = 0
    var totalBytes: Int64 = 0

    init() {}
}

class TransferFilePlanItem {
    var sourcePath: String = ""
    var relativePath: String = ""
    var size: Int64 = 0

    init() {}
}

class CoreServerTransferProtocol <: TransferProtocol {
    let server: CoreServer
    let protocolName: String

    public init(server: CoreServer, protocolName: String) {
        this.server = server
        this.protocolName = protocolName
    }

    public func name(): String {
        protocolName
    }

    public func transfer(task: TransferTask, onProgress: (Float64) -> Unit): Bool {
        server.executeTransferTask(task, onProgress)
    }
}

func normalizeVirtualPath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) {
        out = "/"
    }
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

func composeTaskTargetDir(targetPath: String, rootName: String): String {
    let normalizedTarget = normalizeVirtualPath(targetPath)
    let safeRootName = sanitizeTransferSegment(rootName)
    if (normalizedTarget == "/") {
        return "/" + safeRootName
    }
    if (strEndsWith(normalizedTarget, "/" + safeRootName)) {
        return normalizedTarget
    }
    normalizedTarget + "/" + safeRootName
}

func composeTaskTargetFilePath(targetPath: String, fileName: String): String {
    let normalizedTarget = normalizeVirtualPath(targetPath)
    let safeFileName = sanitizeTransferSegment(fileName)
    if (normalizedTarget == "/") {
        return "/" + safeFileName
    }
    if (strEndsWith(normalizedTarget, "/" + safeFileName)) {
        return normalizedTarget
    }
    normalizedTarget + "/" + safeFileName
}

func joinVirtualPath(base: String, relative: String): String {
    if (relative.size == 0) {
        return normalizeVirtualPath(base)
    }
    let normalizedBase = normalizeVirtualPath(base)
    let normalizedRel = strTrimPrefix(relative.trimAscii(), "/")
    if (normalizedBase == "/") {
        return "/" + normalizedRel
    }
    normalizedBase + "/" + normalizedRel
}

func extractVirtualBaseName(path: String): String {
    let normalized = normalizeVirtualPath(path)
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

func sanitizeTransferSegment(name: String): String {
    var out = name.trimAscii()
    if (out.size == 0) {
        out = "item"
    }
    out = strReplace(out, "/", "_")
    out = strReplace(out, "\\", "_")
    out
}

func sliceTransferBytes(data: Array<UInt8>, offset: Int64, length: Int64): Array<UInt8> {
    if (offset < 0 || length <= 0 || offset >= data.size) {
        return Array<UInt8>(0, repeat: 0)
    }
    var end = offset + length
    if (end > data.size) {
        end = data.size
    }
    let size = end - offset
    let out = Array<UInt8>(size, repeat: 0)
    var index: Int64 = 0
    var cursor = offset
    while (cursor < end) {
        out[index] = data[cursor]
        index += 1
        cursor += 1
    }
    out
}

func randomNumericPin(length: Int64): String {
    let digits = "0123456789".toRuneArray()
    let random = Random()
    var out = ""
    var index: Int64 = 0
    while (index < length) {
        var raw = random.nextInt64()
        if (raw < 0) {
            raw = -raw
        }
        out += digits[raw % digits.size].toString()
        index += 1
    }
    out
}
