package soonlnk.product

import ignite.api2.GetData
import soonlnk.commons.*
import std.convert.*
import std.unicode.*

public class CliAction {
    public var command: String = "serve"
    public var effectiveCommandLine: Array<String> = Array<String>(0, repeat: "")

    public init() {}
}

public class CliOutput {
    public var exitCode: Int64 = 0
    public var body: String = ""

    public init() {}
}

public func runProductCli(commandLine: Array<String>): Int64 {
    let action = resolveCliAction(commandLine)
    match (action.command) {
        case "serve" =>
            let config = loadAppConfig(action.effectiveCommandLine)
            let product = buildProduct(config)
            println("启动产品形态: ${product.name()}")
            product.start()
            product.stop()
            println("服务已关闭")
            0
        case "version" =>
            let profile = currentRuntimeProfile()
            println(buildVersionPayload(profile))
            0
        case "capabilities" =>
            let profile = currentRuntimeProfile()
            println(buildCapabilitiesPayload(profile))
            0
        case "config" =>
            let config = loadAppConfigWithConsole(action.effectiveCommandLine, consoleEnabled: false)
            let profile = currentRuntimeProfile()
            println(buildConfigPayload(config, profile))
            0
        case "status" =>
            emitCliOutput(executeAutomationCommand(action))
        case "devices" =>
            emitCliOutput(executeAutomationCommand(action))
        case "tasks" =>
            emitCliOutput(executeAutomationCommand(action))
        case "connectors" =>
            emitCliOutput(executeAutomationCommand(action))
        case "register-device" =>
            emitCliOutput(executeAutomationCommand(action))
        case "remove-device" =>
            emitCliOutput(executeAutomationCommand(action))
        case "remember-device" =>
            emitCliOutput(executeAutomationCommand(action))
        case "trust-device" =>
            emitCliOutput(executeAutomationCommand(action))
        case "pair-device-pin" =>
            emitCliOutput(executeAutomationCommand(action))
        case "confirm-device-pin" =>
            emitCliOutput(executeAutomationCommand(action))
        case "fs-list" =>
            emitCliOutput(executeAutomationCommand(action))
        case "fs-info" =>
            emitCliOutput(executeAutomationCommand(action))
        case "summary" =>
            emitCliOutput(executeAutomationCommand(action))
        case "transfer" =>
            emitCliOutput(executeAutomationCommand(action))
        case "mcp" =>
            let profile = currentRuntimeProfile()
            if (!profile.supportsMcp) {
                println(buildMachineErrorPayload("MCP_DISABLED", "当前产品形态未启用 MCP"))
                return 1
            }
            let config = loadAppConfigWithConsole(action.effectiveCommandLine, consoleEnabled: false)
            runMcpServer(config, profile: profile)
        case "help" =>
            println(renderCliHelp())
            0
        case "invalid" =>
            let badCommand = resolveInvalidCommand(commandLine)
            println("未知命令: ${badCommand}")
            println(renderCliHelp())
            1
        case _ =>
            println(renderCliHelp())
            1
    }
}

public func resolveCliAction(commandLine: Array<String>): CliAction {
    let action = CliAction()
    if (commandLine.size <= 1) {
        action.command = "serve"
        action.effectiveCommandLine = commandLine
        return action
    }

    let firstArg = commandLine[1].trimAscii()
    let normalized = firstArg.toLower()
    if (normalized.size == 0) {
        action.command = "serve"
        action.effectiveCommandLine = commandLine
        return action
    }

    if (strStartsWithCli(normalized, "-")) {
        if (normalized == "--help" || normalized == "-h") {
            action.command = "help"
            action.effectiveCommandLine = commandLine
            return action
        }
        action.command = "serve"
        action.effectiveCommandLine = commandLine
        return action
    }

    match (normalized) {
        case "serve" =>
            action.command = "serve"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "version" =>
            action.command = "version"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "capabilities" =>
            action.command = "capabilities"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "config" =>
            action.command = "config"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "status" =>
            action.command = "status"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "devices" =>
            action.command = "devices"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "tasks" =>
            action.command = "tasks"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "connectors" =>
            action.command = "connectors"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "register-device" =>
            action.command = "register-device"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "remove-device" =>
            action.command = "remove-device"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "remember-device" =>
            action.command = "remember-device"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "trust-device" =>
            action.command = "trust-device"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "pair-device-pin" =>
            action.command = "pair-device-pin"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "confirm-device-pin" =>
            action.command = "confirm-device-pin"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "fs-list" =>
            action.command = "fs-list"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "fs-info" =>
            action.command = "fs-info"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "summary" =>
            action.command = "summary"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "transfer" =>
            action.command = "transfer"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "mcp" =>
            action.command = "mcp"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case "help" =>
            action.command = "help"
            action.effectiveCommandLine = stripSubcommand(commandLine)
        case _ =>
            action.command = "invalid"
            action.effectiveCommandLine = commandLine
    }
    action
}

public func buildVersionPayload(profile: RuntimeProfile): String {
    let moduleName = resolveTechnicalPackageName(GetData.GetDataClass.ModuleName())
    let moduleVersion = resolveProductVersion(GetData.GetDataClass.ModuleVer())
    JsonObject()
        .put("name", profile.productName)
        .put("package", moduleName)
        .put("version", moduleVersion)
        .toString()
}

public func buildCapabilitiesPayload(profile: RuntimeProfile): String {
    let out = JsonObject()
        .put("name", profile.productName)
        .putObj("capabilities", runtimeCapabilitiesToJson(profile))
        .putArr("capabilityTags", runtimeCapabilityTags(profile))
    out.toString()
}

public func buildConfigPayload(config: AppConfig, profile: RuntimeProfile): String {
    let normalized = normalizeAppConfigForRuntime(config, profile)
    JsonObject()
        .put("name", profile.productName)
        .put("nodeId", normalized.nodeId)
        .put("listenAddr", normalized.listenAddr)
        .putInt("webPort", Int64(normalized.webPort))
        .put("tempDir", normalized.tempDir)
        .put("rootDir", normalized.localRootDir)
        .put("logDir", normalized.logDir)
        .put("configFile", normalized.configFile)
        .put("deviceRegistryFile", normalized.deviceRegistryFile)
        .put("securityMode", normalized.securityMode)
        .putInt("discoveryUdpPort", normalized.discoveryUdpPort)
        .putInt("discoveryHeartbeatSeconds", normalized.discoveryHeartbeatSeconds)
        .put("discoveryAdvertiseIp", normalized.discoveryAdvertiseIp)
        .putBool("enableMdns", normalized.enableMdns)
        .putBool("discoveryBroadcastEnabled", normalized.discoveryBroadcastEnabled)
        .putBool("relayEnabled", normalized.relayEnabled)
        .put("relayCacheDir", normalized.relayCacheDir)
        .put("favoritesStoreMode", normalized.favoritesStoreMode)
        .putBool("trustProxyHeaders", normalized.localAuthTrustProxyHeaders)
        .toString()
}

public func renderCliHelp(): String {
    "SoonLink CLI\n" +
    "Usage:\n" +
    "  soonlnk serve [options]\n" +
    "  soonlnk version\n" +
    "  soonlnk capabilities\n" +
    "  soonlnk config [options]\n" +
    "  soonlnk status [options]\n" +
    "  soonlnk devices [--id <deviceId>] [options]\n" +
    "  soonlnk tasks [--id <taskId>] [options]\n" +
    "  soonlnk connectors [--id <deviceId>] [options]\n" +
    "  soonlnk register-device --id <deviceId> --ip <host> [--port <port>] [options]\n" +
    "  soonlnk remove-device --id <deviceId> [options]\n" +
    "  soonlnk remember-device --id <deviceId> [options]\n" +
    "  soonlnk trust-device --id <deviceId> --state <trusted|blocked|unknown> [options]\n" +
    "  soonlnk pair-device-pin --id <deviceId> [options]\n" +
    "  soonlnk confirm-device-pin --id <deviceId> --pin <pin> [options]\n" +
    "  soonlnk fs-list --path <path> [--device <deviceId>] [options]\n" +
    "  soonlnk fs-info --path <path> [--device <deviceId>] [options]\n" +
    "  soonlnk summary --path <path> [--device <deviceId>] [options]\n" +
    "  soonlnk transfer --source-device <id> --target-device <id> --file-path <path> [--target-path <path>] [options]\n" +
    "  soonlnk mcp [options]\n" +
    "  soonlnk help\n" +
    "\n" +
    "Common options:\n" +
    "  -c, --config <path>     override config file\n" +
    "  -p, --port <port>       override web port\n" +
    "  --root-dir <path>       override local root dir\n" +
    "  --temp-dir <path>       override temp dir\n" +
    "  --log-dir <path>        override log dir\n" +
    "  --node-id <id>          override stable discovery node id\n" +
    "  --discovery-port <port> override UDP discovery port\n" +
    "  --advertise-ip <ip>     override discovery advertise IP\n" +
    "  --enable-mdns           enable mDNS discovery when the current runtime supports it\n" +
    "  --disable-mdns          disable mDNS discovery\n" +
    "  --enable-discovery-broadcast  allow UDP broadcast discovery\n" +
    "  --disable-discovery-broadcast disable UDP broadcast discovery\n" +
    "\n" +
    "Automation options:\n" +
    "  --device <deviceId>     target device for fs-list/fs-info/summary\n" +
    "  --id <value>            device id or task id for lookup commands\n" +
    "  --name <name>           manual device display name\n" +
    "  --device-type <type>    manual device type, default remote\n" +
    "  --connector <type>      manual connector type, default soonlink-http\n" +
    "  --scheme <value>        endpoint scheme, for example http / https\n" +
    "  --base-path <path>      endpoint base path, for example /soonlink\n" +
    "  --ip <host>             manual device host or IP\n" +
    "  --port <port>           manual device port\n" +
    "  --state <state>         trust state for trust-device\n" +
    "  --pin <pin>             PIN for confirm-device-pin\n" +
    "  --path <path>           source path for file commands\n" +
    "  --source-device <id>    source device for transfer\n" +
    "  --target-device <id>    target device for transfer\n" +
    "  --file-path <path>      source file or directory path for transfer\n" +
    "  --target-path <path>    target directory or file path for transfer\n"
}

func executeAutomationCommand(action: CliAction): CliOutput {
    let output = CliOutput()
    let profile = currentRuntimeProfile()
    let config = loadAppConfigWithConsole(action.effectiveCommandLine, consoleEnabled: false)
    let runtime = AutomationRuntime(config, profile: profile)

    try {
        runtime.start()
        match (action.command) {
            case "status" =>
                output.body = buildStatusPayload(runtime)
            case "devices" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device-id")
                output.body = buildDevicesPayload(runtime, id)
            case "tasks" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--task-id")
                output.body = buildTasksPayload(runtime, id)
            case "connectors" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device")
                output.body = buildConnectorsPayload(runtime, id)
            case "register-device" =>
                let record = buildCliDeviceRecord(action.effectiveCommandLine, Int64(runtime.config.webPort))
                output.body = buildUpsertDevicePayload(runtime, record)
            case "remove-device" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device-id")
                output.body = buildRemoveDevicePayload(runtime, id)
            case "remember-device" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device-id")
                output.body = buildRememberDevicePayload(runtime, id)
            case "trust-device" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device-id")
                let state = findCliArgValue(action.effectiveCommandLine, "--state")
                output.body = buildDeviceTrustPayload(runtime, id, state)
            case "pair-device-pin" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device-id")
                output.body = buildDevicePinStartPayload(runtime, id)
            case "confirm-device-pin" =>
                let id = firstNonEmptyCliArg(action.effectiveCommandLine, "--id", "--device-id")
                let pin = findCliArgValue(action.effectiveCommandLine, "--pin")
                output.body = buildDevicePinConfirmPayload(runtime, id, pin)
            case "fs-list" =>
                let path = firstNonEmptyCliArg(action.effectiveCommandLine, "--path", "--file-path")
                if (path.size == 0) {
                    output.exitCode = 1
                    output.body = buildMachineErrorPayload("MISSING_PATH", "path 不能为空")
                    return output
                }
                output.body = buildFsListPayload(runtime, findCliArgValue(action.effectiveCommandLine, "--device"), path)
            case "fs-info" =>
                let path = firstNonEmptyCliArg(action.effectiveCommandLine, "--path", "--file-path")
                if (path.size == 0) {
                    output.exitCode = 1
                    output.body = buildMachineErrorPayload("MISSING_PATH", "path 不能为空")
                    return output
                }
                output.body = buildFsInfoPayload(runtime, findCliArgValue(action.effectiveCommandLine, "--device"), path)
            case "summary" =>
                let path = firstNonEmptyCliArg(action.effectiveCommandLine, "--path", "--file-path")
                if (path.size == 0) {
                    output.exitCode = 1
                    output.body = buildMachineErrorPayload("MISSING_PATH", "path 不能为空")
                    return output
                }
                output.body = buildSummaryPayload(runtime, findCliArgValue(action.effectiveCommandLine, "--device"), path)
            case "transfer" =>
                let sourceDevice = firstNonEmptyCliArg(action.effectiveCommandLine, "--source-device", "--source")
                let targetDevice = firstNonEmptyCliArg(action.effectiveCommandLine, "--target-device", "--target")
                let filePath = firstNonEmptyCliArg(action.effectiveCommandLine, "--file-path", "--path")
                let targetPath = findCliArgValue(action.effectiveCommandLine, "--target-path")
                if (sourceDevice.size == 0 || targetDevice.size == 0 || filePath.size == 0) {
                    output.exitCode = 1
                    output.body = buildMachineErrorPayload("MISSING_TRANSFER_FIELDS", "source-device、target-device 与 file-path 不能为空")
                    return output
                }
                output.body = buildTransferTaskPayload(runtime, sourceDevice, targetDevice, filePath, targetPath)
            case _ =>
                output.exitCode = 1
                output.body = buildMachineErrorPayload("CLI_UNSUPPORTED_COMMAND", "当前命令尚未实现: ${action.command}")
        }

        if (output.body.contains("\"success\":false")) {
            output.exitCode = 1
        }
        output
    } finally {
        runtime.stop()
    }
}

func emitCliOutput(output: CliOutput): Int64 {
    if (output.body.size > 0) {
        println(output.body)
    }
    output.exitCode
}

func stripSubcommand(commandLine: Array<String>): Array<String> {
    if (commandLine.size <= 2) {
        let out = Array<String>(1, repeat: "")
        out[0] = commandLine[0]
        return out
    }

    let out = Array<String>(commandLine.size - 1, repeat: "")
    out[0] = commandLine[0]
    var i: Int64 = 2
    while (i < commandLine.size) {
        out[i - 1] = commandLine[i]
        i += 1
    }
    out
}

func resolveInvalidCommand(commandLine: Array<String>): String {
    if (commandLine.size > 1) {
        return commandLine[1]
    }
    ""
}

func strStartsWithCli(text: String, prefix: String): Bool {
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

func findCliArgValue(commandLine: Array<String>, name: String): String {
    if (name.size == 0) {
        return ""
    }
    var i: Int64 = 1
    while (i < commandLine.size) {
        let current = commandLine[i]
        if (current == name) {
            if (i + 1 < commandLine.size) {
                return commandLine[i + 1]
            }
            return ""
        }
        if (strStartsWithCli(current, name + "=")) {
            return strSubstring(current, name.size + 1, current.size)
        }
        i += 1
    }
    ""
}

func firstNonEmptyCliArg(commandLine: Array<String>, primary: String, secondary: String): String {
    let primaryValue = findCliArgValue(commandLine, primary).trimAscii()
    if (primaryValue.size > 0) {
        return primaryValue
    }
    let secondaryValue = findCliArgValue(commandLine, secondary).trimAscii()
    if (secondaryValue.size > 0) {
        return secondaryValue
    }
    ""
}

func buildCliDeviceRecord(commandLine: Array<String>, defaultPort: Int64): DeviceRegistryRecord {
    let record = DeviceRegistryRecord()
    record.id = firstNonEmptyCliArg(commandLine, "--id", "--device-id")
    record.name = findCliArgValue(commandLine, "--name")
    record.deviceType = firstNonEmptyCliArg(commandLine, "--device-type", "--type")
    record.connectorType = firstNonEmptyCliArg(commandLine, "--connector", "--connector-type")
    record.endpointScheme = findCliArgValue(commandLine, "--scheme")
    record.endpointBasePath = findCliArgValue(commandLine, "--base-path")
    record.ip = firstNonEmptyCliArg(commandLine, "--ip", "--host")

    let portRaw = findCliArgValue(commandLine, "--port").trimAscii()
    if (portRaw.size > 0) {
        try {
            record.port = Int64.parse(portRaw)
        } catch (_: Exception) {
            record.port = defaultPort
        }
    } else {
        record.port = defaultPort
    }
    record
}
