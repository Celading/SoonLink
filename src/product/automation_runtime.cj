package soonlnk.product

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import std.collection.ArrayList
import std.unicode.*

public class AutomationRuntime {
    public let profile: RuntimeProfile
    public let config: AppConfig
    public let server: CoreServer
    var started: Bool = false

    public init(config: AppConfig, profile!: RuntimeProfile = currentRuntimeProfile()) {
        let normalized = normalizeAppConfigForRuntime(config, profile)
        this.profile = profile
        this.config = normalized
        this.server = CoreServer(normalized, profile: profile)
        this.server.setConsoleOutputEnabled(false)
    }

    public func start(): Unit {
        if (started) {
            return
        }
        server.startAutomationRuntime()
        started = true
    }

    public func stop(): Unit {
        if (!started) {
            return
        }
        server.stop()
        started = false
    }
}

public func buildMachineErrorPayload(code: String, message: String): String {
    JsonObject()
        .putBool("success", false)
        .put("code", code)
        .put("error", message)
        .toString()
}

public func buildStatusPayload(runtime: AutomationRuntime): String {
    let devices = runtime.server.listDevices()
    let tasks = runtime.server.listTasks()
    let out = JsonObject()
        .putBool("success", true)
        .put("name", runtime.profile.productName)
        .putObj("capabilities", runtimeCapabilitiesToJson(runtime.profile))
        .putObj("config", buildAutomationConfigObject(runtime.config))
        .putObj("discovery", buildAutomationDiscoveryObject(runtime))
        .putObj("system", runtime.server.monitorSystem())
        .putInt("deviceCount", devices.size)
        .putInt("taskCount", tasks.size)
        .putArr("devices", devicesToJsonArray(devices))
        .putArr("tasks", tasksToJsonArray(tasks))
    match (runtime.server.getDevice("local")) {
        case Some(device) => out.putObj("localDevice", device.toJson())
        case None => ()
    }
    out.toString()
}

func buildAutomationDiscoveryObject(runtime: AutomationRuntime): JsonObject {
    let localDevice = runtime.server.getDevice("local")
    let effectiveAdvertiseIp = resolveAutomationDiscoveryEffectiveIp(runtime, localDevice)
    let endpointHost = resolveAutomationDiscoveryLocalEndpointHost(localDevice, effectiveAdvertiseIp)
    let endpointPort = resolveAutomationDiscoveryLocalEndpointPort(runtime, localDevice)

    let out = JsonObject()
        .put("mode", if (runtime.profile.supportsActiveDiscovery) { "active" } else { "passive" })
        .put("nodeId", runtime.config.nodeId)
        .putBool("supportsActiveDiscovery", runtime.profile.supportsActiveDiscovery)
        .putBool("supportsMdnsDiscovery", runtime.profile.supportsMdnsDiscovery)
        .putBool("udpBroadcastEnabled", runtime.config.discoveryBroadcastEnabled)
        .putBool("mdnsEnabled", runtime.config.enableMdns)
        .putInt("udpPort", runtime.config.discoveryUdpPort)
        .putInt("heartbeatSeconds", runtime.config.discoveryHeartbeatSeconds)
        .put("configuredAdvertiseIp", runtime.config.discoveryAdvertiseIp)
        .put("effectiveAdvertiseIp", effectiveAdvertiseIp)
        .put("localEndpoint", buildAutomationDiscoveryEndpointText(endpointHost, endpointPort))
        .put("localEndpointHost", endpointHost)
        .putInt("localEndpointPort", endpointPort)
        .putArr("channels", buildAutomationDiscoveryChannels(runtime))
        .putBool("rememberRequiresConfirmation", true)
        .putBool("discoverable", runtime.profile.supportsActiveDiscovery &&
            (runtime.config.discoveryBroadcastEnabled || runtime.config.enableMdns))
        .put("registerDeviceCommand", buildAutomationRegisterDeviceCommand(runtime.config.nodeId, endpointHost, endpointPort))
    match (localDevice) {
        case Some(device) => out.putObj("localDevice", device.toJson())
        case None => ()
    }
    out
}

public func buildDevicesPayload(runtime: AutomationRuntime, deviceId: String): String {
    if (deviceId.size > 0) {
        match (runtime.server.getDevice(deviceId)) {
            case Some(device) =>
                return JsonObject()
                    .putBool("success", true)
                    .putObj("device", device.toJson())
                    .toString()
            case None =>
                return buildMachineErrorPayload("DEVICE_NOT_FOUND", "设备不存在: ${deviceId}")
        }
    }

    let devices = runtime.server.listDevices()
    JsonObject()
        .putBool("success", true)
        .putArr("devices", devicesToJsonArray(devices))
        .toString()
}

public func buildUpsertDevicePayload(runtime: AutomationRuntime, record: DeviceRegistryRecord): String {
    let validationError = runtime.server.validateManagedDeviceRecord(record)
    if (validationError.size > 0) {
        return buildMachineErrorPayload("INVALID_DEVICE_RECORD", validationError)
    }

    try {
        let device = runtime.server.upsertManagedDeviceRecord(record)
        JsonObject()
            .putBool("success", true)
            .putObj("device", device.toJson())
            .put("message", "设备端点已保存")
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("DEVICE_UPSERT_FAILED", "设备端点保存失败: ${e.message}")
    }
}

public func buildRemoveDevicePayload(runtime: AutomationRuntime, deviceId: String): String {
    let normalizedId = deviceId.trimAscii()
    if (normalizedId.size == 0) {
        return buildMachineErrorPayload("MISSING_DEVICE_ID", "deviceId 不能为空")
    }
    if (normalizedId.toLower() == "local") {
        return buildMachineErrorPayload("LOCAL_DEVICE_RESERVED", "local 设备由运行时保留，不能删除")
    }

    if (!runtime.server.removeManagedDeviceRecord(normalizedId)) {
        return buildMachineErrorPayload("DEVICE_NOT_FOUND", "设备不存在或未删除: ${normalizedId}")
    }

    JsonObject()
        .putBool("success", true)
        .put("deviceId", normalizedId)
        .put("message", "设备端点已删除")
        .toString()
}

public func buildRememberDevicePayload(runtime: AutomationRuntime, deviceId: String): String {
    let normalizedId = deviceId.trimAscii()
    if (normalizedId.size == 0) {
        return buildMachineErrorPayload("MISSING_DEVICE_ID", "deviceId 不能为空")
    }

    try {
        let device = runtime.server.rememberDiscoveredDevice(normalizedId)
        JsonObject()
            .putBool("success", true)
            .putObj("device", device.toJson())
            .put("message", "设备已记住")
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("DEVICE_REMEMBER_FAILED", e.message)
    }
}

public func buildDeviceTrustPayload(runtime: AutomationRuntime, deviceId: String, state: String): String {
    let normalizedId = deviceId.trimAscii()
    let normalizedState = state.trimAscii().toLower()
    if (normalizedId.size == 0) {
        return buildMachineErrorPayload("MISSING_DEVICE_ID", "deviceId 不能为空")
    }
    if (normalizedState.size == 0) {
        return buildMachineErrorPayload("MISSING_TRUST_STATE", "state 不能为空")
    }

    try {
        let device = runtime.server.setDeviceTrustState(normalizedId, normalizedState)
        JsonObject()
            .putBool("success", true)
            .putObj("device", device.toJson())
            .put("message", "设备授信状态已更新")
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("DEVICE_TRUST_UPDATE_FAILED", e.message)
    }
}

public func buildDevicePinStartPayload(runtime: AutomationRuntime, deviceId: String): String {
    let normalizedId = deviceId.trimAscii()
    if (normalizedId.size == 0) {
        return buildMachineErrorPayload("MISSING_DEVICE_ID", "deviceId 不能为空")
    }

    try {
        let session = runtime.server.startPinPairing(normalizedId)
        JsonObject()
            .putBool("success", true)
            .putObj("pairing", session.toJson())
            .put("message", "PIN 配对口令已生成")
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("DEVICE_PIN_START_FAILED", e.message)
    }
}

public func buildDevicePinConfirmPayload(runtime: AutomationRuntime, deviceId: String, pin: String): String {
    let normalizedId = deviceId.trimAscii()
    let normalizedPin = pin.trimAscii()
    if (normalizedId.size == 0 || normalizedPin.size == 0) {
        return buildMachineErrorPayload("MISSING_PIN_FIELDS", "deviceId 与 pin 不能为空")
    }

    try {
        let device = runtime.server.confirmPinPairing(normalizedId, normalizedPin)
        JsonObject()
            .putBool("success", true)
            .putObj("device", device.toJson())
            .put("message", "PIN 配对成功，设备已授信")
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("DEVICE_PIN_CONFIRM_FAILED", e.message)
    }
}

public func buildTasksPayload(runtime: AutomationRuntime, taskId: String): String {
    if (taskId.size > 0) {
        match (runtime.server.getTask(taskId)) {
            case Some(task) =>
                return JsonObject()
                    .putBool("success", true)
                    .putObj("task", task.toJson())
                    .toString()
            case None =>
                return buildMachineErrorPayload("TASK_NOT_FOUND", "任务不存在: ${taskId}")
        }
    }

    let tasks = runtime.server.listTasks()
    JsonObject()
        .putBool("success", true)
        .putArr("tasks", tasksToJsonArray(tasks))
        .toString()
}

public func buildConnectorsPayload(runtime: AutomationRuntime, deviceId: String): String {
    let out = JsonObject()
        .putBool("success", true)
        .putArr("connectors", connectorDescriptorsToJsonArray(runtime.server.listConnectors()))

    if (deviceId.size > 0) {
        match (runtime.server.getDevice(deviceId)) {
            case Some(device) =>
                let devices = JsonArray()
                devices.addObj(buildConnectorBindingObject(runtime.server, device))
                return out.putArr("devices", devices).toString()
            case None =>
                return buildMachineErrorPayload("DEVICE_NOT_FOUND", "设备不存在: ${deviceId}")
        }
    }

    let devices = JsonArray()
    for (device in runtime.server.listDevices()) {
        devices.addObj(buildConnectorBindingObject(runtime.server, device))
    }
    out.putArr("devices", devices).toString()
}

public func buildFsListPayload(runtime: AutomationRuntime, deviceId: String, path: String): String {
    let resolvedDevice = resolveAutomationDevice(deviceId)
    let resolvedPath = resolveAutomationPath(path)
    try {
        let files = runtime.server.listDir(resolvedDevice, resolvedPath)
        JsonObject()
            .putBool("success", true)
            .put("device", resolvedDevice)
            .put("path", resolvedPath)
            .putArr("files", fileEntriesToJsonArray(files))
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("FS_LIST_FAILED", e.message)
    }
}

public func buildFsInfoPayload(runtime: AutomationRuntime, deviceId: String, path: String): String {
    let resolvedDevice = resolveAutomationDevice(deviceId)
    let resolvedPath = resolveAutomationPath(path)
    try {
        match (runtime.server.getFileInfo(resolvedDevice, resolvedPath)) {
            case Some(info) =>
                JsonObject()
                    .putBool("success", true)
                    .put("device", resolvedDevice)
                    .putObj("info", info.toJson())
                    .toString()
            case None =>
                buildMachineErrorPayload("FILE_NOT_FOUND", "文件或目录不存在: ${resolvedDevice}:${resolvedPath}")
        }
    } catch (e: Exception) {
        buildMachineErrorPayload("FS_INFO_FAILED", e.message)
    }
}

public func buildSummaryPayload(runtime: AutomationRuntime, deviceId: String, path: String): String {
    let resolvedDevice = resolveAutomationDevice(deviceId)
    let resolvedPath = resolveAutomationPath(path)
    try {
        JsonObject()
            .putBool("success", true)
            .put("device", resolvedDevice)
            .putObj("summary", runtime.server.summarizeTransferSource(resolvedDevice, resolvedPath))
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("SUMMARY_FAILED", "源项摘要失败: ${e.message}")
    }
}

public func buildTransferTaskPayload(
    runtime: AutomationRuntime,
    sourceDevice: String,
    targetDevice: String,
    filePath: String,
    targetPath: String
): String {
    let resolvedSource = resolveAutomationDevice(sourceDevice)
    let resolvedTarget = resolveAutomationDevice(targetDevice)
    let resolvedFilePath = resolveAutomationPath(filePath)
    if (resolvedTarget.size == 0) {
        return buildMachineErrorPayload("MISSING_TARGET_DEVICE", "targetDevice 不能为空")
    }
    if (resolvedFilePath.size == 0 || resolvedFilePath == "/") {
        return buildMachineErrorPayload("MISSING_FILE_PATH", "filePath 不能为空")
    }

    match (runtime.server.getDevice(resolvedSource)) {
        case None =>
            return buildMachineErrorPayload("SOURCE_DEVICE_NOT_FOUND", "源设备不存在: ${resolvedSource}")
        case _ => ()
    }
    match (runtime.server.getDevice(resolvedTarget)) {
        case None =>
            return buildMachineErrorPayload("TARGET_DEVICE_NOT_FOUND", "目标设备不存在: ${resolvedTarget}")
        case _ => ()
    }

    try {
        let task = runtime.server.createTransferTask(resolvedSource, resolvedTarget, resolvedFilePath, targetPath)
        JsonObject()
            .putBool("success", true)
            .putObj("task", task.toJson())
            .toString()
    } catch (e: Exception) {
        buildMachineErrorPayload("TRANSFER_CREATE_FAILED", e.message)
    }
}

func buildAutomationConfigObject(config: AppConfig): JsonObject {
    JsonObject()
        .put("nodeId", config.nodeId)
        .put("listenAddr", config.listenAddr)
        .putInt("webPort", Int64(config.webPort))
        .put("tempDir", config.tempDir)
        .put("rootDir", config.localRootDir)
        .put("logDir", config.logDir)
        .put("configFile", config.configFile)
        .put("deviceRegistryFile", config.deviceRegistryFile)
        .put("securityMode", config.securityMode)
        .putInt("discoveryUdpPort", config.discoveryUdpPort)
        .putInt("discoveryHeartbeatSeconds", config.discoveryHeartbeatSeconds)
        .put("discoveryAdvertiseIp", config.discoveryAdvertiseIp)
        .putBool("enableMdns", config.enableMdns)
        .putBool("discoveryBroadcastEnabled", config.discoveryBroadcastEnabled)
        .putBool("relayEnabled", config.relayEnabled)
        .putBool("trustProxyHeaders", config.localAuthTrustProxyHeaders)
        .put("relayCacheDir", config.relayCacheDir)
        .put("favoritesStoreMode", config.favoritesStoreMode)
}

func resolveAutomationDiscoveryEffectiveIp(runtime: AutomationRuntime, localDevice: ?Device): String {
    match (localDevice) {
        case Some(device) =>
            let ip = device.ip.trimAscii()
            if (ip.size > 0) {
                return ip
            }
        case None => ()
    }
    let configured = runtime.config.discoveryAdvertiseIp.trimAscii()
    if (configured.size > 0) {
        return configured
    }
    "127.0.0.1"
}

func resolveAutomationDiscoveryLocalEndpointHost(localDevice: ?Device, effectiveAdvertiseIp: String): String {
    match (localDevice) {
        case Some(device) =>
            let ip = device.ip.trimAscii()
            if (ip.size > 0) {
                return ip
            }
        case None => ()
    }
    effectiveAdvertiseIp.trimAscii()
}

func resolveAutomationDiscoveryLocalEndpointPort(runtime: AutomationRuntime, localDevice: ?Device): Int64 {
    match (localDevice) {
        case Some(device) =>
            if (device.port > 0) {
                return device.port
            }
        case None => ()
    }
    Int64(runtime.config.webPort)
}

func buildAutomationDiscoveryChannels(runtime: AutomationRuntime): JsonArray {
    let arr = JsonArray()
    if (runtime.profile.supportsActiveDiscovery && runtime.config.discoveryBroadcastEnabled) {
        arr.addStr("udp-broadcast")
    }
    if (runtime.profile.supportsActiveDiscovery && runtime.config.enableMdns) {
        arr.addStr("mdns")
    }
    arr
}

func buildAutomationDiscoveryEndpointText(endpointHost: String, endpointPort: Int64): String {
    let host = endpointHost.trimAscii()
    if (host.size == 0) {
        return ""
    }
    if (endpointPort > 0) {
        return "${host}:${endpointPort}"
    }
    host
}

func buildAutomationRegisterDeviceCommand(nodeId: String, endpointHost: String, endpointPort: Int64): String {
    let normalizedId = nodeId.trimAscii()
    let normalizedHost = endpointHost.trimAscii()
    if (normalizedId.size == 0 || normalizedHost.size == 0 || endpointPort <= 0) {
        return ""
    }
    "soonlnk register-device --id ${normalizedId} --ip ${normalizedHost} --port ${endpointPort} --connector soonlink-http --scheme http"
}

func devicesToJsonArray(devices: ArrayList<Device>): JsonArray {
    let arr = JsonArray()
    for (device in devices) {
        arr.addObj(device.toJson())
    }
    arr
}

func tasksToJsonArray(tasks: ArrayList<TransferTask>): JsonArray {
    let arr = JsonArray()
    for (task in tasks) {
        arr.addObj(task.toJson())
    }
    arr
}

func connectorDescriptorsToJsonArray(descriptors: ArrayList<ConnectorDescriptor>): JsonArray {
    let arr = JsonArray()
    for (descriptor in descriptors) {
        arr.addObj(descriptor.toJson())
    }
    arr
}

func fileEntriesToJsonArray(entries: ArrayList<FileEntry>): JsonArray {
    let arr = JsonArray()
    for (entry in entries) {
        arr.addObj(entry.toJson())
    }
    arr
}

func buildConnectorBindingObject(server: CoreServer, device: Device): JsonObject {
    let resolvedType = defaultConnectorTypeForDevice(device)
    let endpoint = buildDeviceEndpoint(device)
    let out = JsonObject()
        .put("id", device.id)
        .put("name", device.name)
        .put("deviceType", device.deviceType)
        .put("connectorType", resolvedType)
        .put("endpointScheme", endpoint.scheme)
        .put("endpointBasePath", endpoint.basePath)
        .put("ip", device.ip)
        .putInt("port", device.port)
        .putObj("endpoint", endpoint.toJson())
        .putBool("online", device.online)

    match (server.describeConnector(resolvedType)) {
        case Some(descriptor) =>
            out.putBool("driverAvailable", true)
            out.putObj("connector", descriptor.toJson())
        case None =>
            out.putBool("driverAvailable", false)
    }
    out
}

func resolveAutomationDevice(deviceId: String): String {
    let trimmed = deviceId.trimAscii()
    if (trimmed.size > 0) {
        return trimmed
    }
    "local"
}

func resolveAutomationPath(path: String): String {
    let trimmed = path.trimAscii()
    if (trimmed.size == 0) {
        return "/"
    }
    trimmed
}
