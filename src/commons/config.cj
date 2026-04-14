package soonlnk.commons

import std.collection.HashMap
import std.convert.*
import std.env.{getVariable, getHomeDirectory}
import std.unicode.*

public struct AppConfig {
    public var nodeId: String = ""
    public var listenAddr: String = ":8080"
    public var webPort: UInt16 = 8081
    public var tempDir: String = "/tmp/soonlink"
    public var maxConnections: Int64 = 100
    public var encryptionKey: String = ""
    public var certFile: String = ""
    public var keyFile: String = ""

    public var configFile: String = "./config/soonlink.toml"
    public var deviceRegistryFile: String = "./config/devices.json"
    public var logDir: String = "./logs"
    public var localRootDir: String = ""

    public var securityMode: String = "plain"
    public var discoveryUdpPort: Int64 = 19090
    public var enableMdns: Bool = false
    public var discoveryHeartbeatSeconds: Int64 = 30
    public var discoveryAdvertiseIp: String = ""
    public var discoveryBroadcastEnabled: Bool = true
    public var localAuthTrustProxyHeaders: Bool = false
    public var relayEnabled: Bool = true
    public var relayCacheDir: String = "./cache/relay"
    public var relayRetentionHours: Int64 = 24
    public var relayLimitMode: String = "fixed"
    public var relayLimitBytes: Int64 = 20 * 1024 * 1024 * 1024
    public var relayLimitPercent: Int64 = 10
    public var favoritesStoreMode: String = "cache"
    public var favoritesTomlFile: String = "./config/favorites.toml"
    public var whitelistTomlFile: String = "./config/whitelist.toml"

    public init(
        nodeId!: String = "",
        listenAddr!: String = ":8080",
        webPort!: UInt16 = 8081,
        tempDir!: String = "/tmp/soonlink",
        maxConnections!: Int64 = 100,
        encryptionKey!: String = "",
        certFile!: String = "",
        keyFile!: String = "",
        configFile!: String = "./config/soonlink.toml",
        deviceRegistryFile!: String = "./config/devices.json",
        logDir!: String = "./logs",
        localRootDir!: String = "",
        securityMode!: String = "plain",
        discoveryUdpPort!: Int64 = 19090,
        enableMdns!: Bool = false,
        discoveryHeartbeatSeconds!: Int64 = 30,
        discoveryAdvertiseIp!: String = "",
        discoveryBroadcastEnabled!: Bool = true,
        localAuthTrustProxyHeaders!: Bool = false,
        relayEnabled!: Bool = true,
        relayCacheDir!: String = "./cache/relay",
        relayRetentionHours!: Int64 = 24,
        relayLimitMode!: String = "fixed",
        relayLimitBytes!: Int64 = 20 * 1024 * 1024 * 1024,
        relayLimitPercent!: Int64 = 10,
        favoritesStoreMode!: String = "cache",
        favoritesTomlFile!: String = "./config/favorites.toml",
        whitelistTomlFile!: String = "./config/whitelist.toml"
    ) {
        this.nodeId = nodeId
        this.listenAddr = listenAddr
        this.webPort = webPort
        this.tempDir = tempDir
        this.maxConnections = maxConnections
        this.encryptionKey = encryptionKey
        this.certFile = certFile
        this.keyFile = keyFile
        this.configFile = configFile
        this.deviceRegistryFile = deviceRegistryFile
        this.logDir = logDir
        this.localRootDir = localRootDir
        this.securityMode = securityMode
        this.discoveryUdpPort = discoveryUdpPort
        this.enableMdns = enableMdns
        this.discoveryHeartbeatSeconds = discoveryHeartbeatSeconds
        this.discoveryAdvertiseIp = discoveryAdvertiseIp
        this.discoveryBroadcastEnabled = discoveryBroadcastEnabled
        this.localAuthTrustProxyHeaders = localAuthTrustProxyHeaders
        this.relayEnabled = relayEnabled
        this.relayCacheDir = relayCacheDir
        this.relayRetentionHours = relayRetentionHours
        this.relayLimitMode = relayLimitMode
        this.relayLimitBytes = relayLimitBytes
        this.relayLimitPercent = relayLimitPercent
        this.favoritesStoreMode = favoritesStoreMode
        this.favoritesTomlFile = favoritesTomlFile
        this.whitelistTomlFile = whitelistTomlFile
    }
}

public func defaultAppConfig(): AppConfig {
    loadAppConfig(Array<String>())
}

public func loadAppConfig(commandLine: Array<String>): AppConfig {
    loadAppConfigWithConsole(commandLine)
}

public func loadAppConfigWithConsole(commandLine: Array<String>, consoleEnabled!: Bool = true): AppConfig {
    var config = AppConfig()
    let args = normalizeCommandLine(commandLine)

    config.configFile = getEnvStr("SOONLINK_CONFIG_FILE", config.configFile)
    if (let Some(configPath) <- findArgValue(args, "--config", "-c")) {
        config.configFile = configPath
    }

    let fileMgr = LocalFileMgr()
    let existed = fileMgr.exists(config.configFile)
    let store = TomlConfigStore(config.configFile)
    let tomlValues = store.load()
    config = applyTomlConfig(config, tomlValues)

    config = applyEnvOverrides(config)
    config = applyArgOverrides(config, args)
    config = finalizeAppConfig(config)

    if (!existed) {
        saveAppConfig(config)
    }

    if (consoleEnabled) {
        println(
            "配置加载完成 - Web端口: ${config.webPort}, 临时目录: ${config.tempDir}, 最大连接数: ${config.maxConnections}, " +
            "安全模式: ${config.securityMode}, 节点ID: ${config.nodeId}, 通告IP: ${config.discoveryAdvertiseIp}, 自动发现端口: ${config.discoveryUdpPort}, 根目录: ${config.localRootDir}, 配置文件: ${config.configFile}"
        )
    }

    config
}

public func saveAppConfig(config: AppConfig): Unit {
    let values = HashMap<String, String>()
    values.add("node_id", config.nodeId)
    values.add("listen_addr", config.listenAddr)
    values.add("web_port", "${config.webPort}")
    values.add("temp_dir", config.tempDir)
    values.add("max_connections", "${config.maxConnections}")
    values.add("encryption_key", config.encryptionKey)
    values.add("cert_file", config.certFile)
    values.add("key_file", config.keyFile)
    values.add("device_registry_file", config.deviceRegistryFile)
    values.add("log_dir", config.logDir)
    values.add("local_root_dir", config.localRootDir)
    values.add("security_mode", config.securityMode)
    values.add("discovery_udp_port", "${config.discoveryUdpPort}")
    values.add("enable_mdns", if (config.enableMdns) { "true" } else { "false" })
    values.add("discovery_heartbeat_seconds", "${config.discoveryHeartbeatSeconds}")
    values.add("discovery_advertise_ip", config.discoveryAdvertiseIp)
    values.add("discovery_broadcast_enabled", if (config.discoveryBroadcastEnabled) { "true" } else { "false" })
    values.add("local_auth_trust_proxy_headers", if (config.localAuthTrustProxyHeaders) { "true" } else { "false" })
    values.add("relay_enabled", if (config.relayEnabled) { "true" } else { "false" })
    values.add("relay_cache_dir", config.relayCacheDir)
    values.add("relay_retention_hours", "${config.relayRetentionHours}")
    values.add("relay_limit_mode", config.relayLimitMode)
    values.add("relay_limit_bytes", "${config.relayLimitBytes}")
    values.add("relay_limit_percent", "${config.relayLimitPercent}")
    values.add("favorites_store_mode", config.favoritesStoreMode)
    values.add("favorites_toml_file", config.favoritesTomlFile)
    values.add("whitelist_toml_file", config.whitelistTomlFile)

    TomlConfigStore(config.configFile).save(values)
}

func applyTomlConfig(config: AppConfig, values: HashMap<String, String>): AppConfig {
    var out = config

    out.nodeId = values.get("node_id") ?? out.nodeId
    out.listenAddr = values.get("listen_addr") ?? out.listenAddr
    out.tempDir = values.get("temp_dir") ?? out.tempDir
    out.encryptionKey = values.get("encryption_key") ?? out.encryptionKey
    out.certFile = values.get("cert_file") ?? out.certFile
    out.keyFile = values.get("key_file") ?? out.keyFile
    out.deviceRegistryFile = values.get("device_registry_file") ?? out.deviceRegistryFile
    out.logDir = values.get("log_dir") ?? out.logDir
    out.localRootDir = values.get("local_root_dir") ?? out.localRootDir
    out.securityMode = values.get("security_mode") ?? out.securityMode
    out.discoveryAdvertiseIp = values.get("discovery_advertise_ip") ?? out.discoveryAdvertiseIp
    out.relayCacheDir = values.get("relay_cache_dir") ?? out.relayCacheDir
    out.relayLimitMode = values.get("relay_limit_mode") ?? out.relayLimitMode
    out.favoritesStoreMode = values.get("favorites_store_mode") ?? out.favoritesStoreMode
    out.favoritesTomlFile = values.get("favorites_toml_file") ?? out.favoritesTomlFile
    out.whitelistTomlFile = values.get("whitelist_toml_file") ?? out.whitelistTomlFile

    if (let Some(v) <- values.get("web_port")) {
        out.webPort = UInt16(parseIntOrDefault(v, Int64(out.webPort)))
    }
    if (let Some(v) <- values.get("max_connections")) {
        out.maxConnections = parseIntOrDefault(v, out.maxConnections)
    }
    if (let Some(v) <- values.get("discovery_udp_port")) {
        out.discoveryUdpPort = parseIntOrDefault(v, out.discoveryUdpPort)
    }
    if (let Some(v) <- values.get("enable_mdns")) {
        out.enableMdns = parseBoolOrDefault(v, out.enableMdns)
    }
    if (let Some(v) <- values.get("discovery_heartbeat_seconds")) {
        out.discoveryHeartbeatSeconds = parseIntOrDefault(v, out.discoveryHeartbeatSeconds)
    }
    if (let Some(v) <- values.get("discovery_broadcast_enabled")) {
        out.discoveryBroadcastEnabled = parseBoolOrDefault(v, out.discoveryBroadcastEnabled)
    }
    if (let Some(v) <- values.get("local_auth_trust_proxy_headers")) {
        out.localAuthTrustProxyHeaders = parseBoolOrDefault(v, out.localAuthTrustProxyHeaders)
    }
    if (let Some(v) <- values.get("relay_enabled")) {
        out.relayEnabled = parseBoolOrDefault(v, out.relayEnabled)
    }
    if (let Some(v) <- values.get("relay_retention_hours")) {
        out.relayRetentionHours = parseIntOrDefault(v, out.relayRetentionHours)
    }
    if (let Some(v) <- values.get("relay_limit_bytes")) {
        out.relayLimitBytes = parseIntOrDefault(v, out.relayLimitBytes)
    }
    if (let Some(v) <- values.get("relay_limit_percent")) {
        out.relayLimitPercent = parseIntOrDefault(v, out.relayLimitPercent)
    }

    out
}

func applyEnvOverrides(config: AppConfig): AppConfig {
    var out = config

    out.nodeId = getEnvStr("SOONLINK_NODE_ID", out.nodeId)
    out.listenAddr = getEnvStr("SOONLINK_LISTEN_ADDR", out.listenAddr)
    out.webPort = UInt16(getEnvInt("SOONLINK_WEB_PORT", Int64(out.webPort)))
    out.tempDir = getEnvStr("SOONLINK_TEMP_DIR", out.tempDir)
    out.maxConnections = getEnvInt("SOONLINK_MAX_CONNECTIONS", out.maxConnections)
    out.encryptionKey = getEnvStr("SOONLINK_ENCRYPTION_KEY", out.encryptionKey)
    out.certFile = getEnvStr("SOONLINK_CERT_FILE", out.certFile)
    out.keyFile = getEnvStr("SOONLINK_KEY_FILE", out.keyFile)
    out.deviceRegistryFile = getEnvStr("SOONLINK_DEVICE_REGISTRY_FILE", out.deviceRegistryFile)
    out.logDir = getEnvStr("SOONLINK_LOG_DIR", out.logDir)
    out.localRootDir = getEnvStr("SOONLINK_LOCAL_ROOT_DIR", out.localRootDir)
    out.securityMode = getEnvStr("SOONLINK_SECURITY_MODE", out.securityMode)
    out.discoveryUdpPort = getEnvInt("SOONLINK_DISCOVERY_UDP_PORT", out.discoveryUdpPort)
    out.enableMdns = getEnvBool("SOONLINK_ENABLE_MDNS", out.enableMdns)
    out.discoveryHeartbeatSeconds = getEnvInt("SOONLINK_DISCOVERY_HEARTBEAT_SECONDS", out.discoveryHeartbeatSeconds)
    out.discoveryAdvertiseIp = getEnvStr("SOONLINK_DISCOVERY_ADVERTISE_IP", out.discoveryAdvertiseIp)
    out.discoveryBroadcastEnabled = getEnvBool("SOONLINK_DISCOVERY_BROADCAST_ENABLED", out.discoveryBroadcastEnabled)
    out.localAuthTrustProxyHeaders = getEnvBool("SOONLINK_LOCAL_AUTH_TRUST_PROXY_HEADERS", out.localAuthTrustProxyHeaders)
    out.relayEnabled = getEnvBool("SOONLINK_RELAY_ENABLED", out.relayEnabled)
    out.relayCacheDir = getEnvStr("SOONLINK_RELAY_CACHE_DIR", out.relayCacheDir)
    out.relayRetentionHours = getEnvInt("SOONLINK_RELAY_RETENTION_HOURS", out.relayRetentionHours)
    out.relayLimitMode = getEnvStr("SOONLINK_RELAY_LIMIT_MODE", out.relayLimitMode)
    out.relayLimitBytes = getEnvInt("SOONLINK_RELAY_LIMIT_BYTES", out.relayLimitBytes)
    out.relayLimitPercent = getEnvInt("SOONLINK_RELAY_LIMIT_PERCENT", out.relayLimitPercent)
    out.favoritesStoreMode = getEnvStr("SOONLINK_FAVORITES_STORE_MODE", out.favoritesStoreMode)
    out.favoritesTomlFile = getEnvStr("SOONLINK_FAVORITES_TOML_FILE", out.favoritesTomlFile)
    out.whitelistTomlFile = getEnvStr("SOONLINK_WHITELIST_TOML_FILE", out.whitelistTomlFile)

    out
}

func applyArgOverrides(config: AppConfig, args: Array<String>): AppConfig {
    var out = config

    if (let Some(v) <- findArgValue(args, "--node-id", "")) {
        out.nodeId = v
    }
    if (let Some(v) <- findArgValue(args, "--listen", "-l")) {
        out.listenAddr = v
    }
    if (let Some(v) <- findArgValue(args, "--port", "-p")) {
        out.webPort = UInt16(parseIntOrDefault(v, Int64(out.webPort)))
    }
    if (let Some(v) <- findArgValue(args, "--temp-dir", "")) {
        out.tempDir = v
    }
    if (let Some(v) <- findArgValue(args, "--root-dir", "--root")) {
        out.localRootDir = v
    }
    if (let Some(v) <- findArgValue(args, "--log-dir", "")) {
        out.logDir = v
    }
    if (let Some(v) <- findArgValue(args, "--config", "-c")) {
        out.configFile = v
    }
    if (let Some(v) <- findArgValue(args, "--security-mode", "")) {
        out.securityMode = v
    }
    if (let Some(v) <- findArgValue(args, "--discovery-port", "--discovery-udp-port")) {
        out.discoveryUdpPort = parseIntOrDefault(v, out.discoveryUdpPort)
    }
    if (let Some(v) <- findArgValue(args, "--advertise-ip", "")) {
        out.discoveryAdvertiseIp = v
    }
    if (let Some(v) <- findArgValue(args, "--max-connections", "")) {
        out.maxConnections = parseIntOrDefault(v, out.maxConnections)
    }
    if (let Some(v) <- findArgValue(args, "--favorites-mode", "")) {
        out.favoritesStoreMode = v
    }
    if (containsExactArg(args, "--enable-mdns")) {
        out.enableMdns = true
    }
    if (containsExactArg(args, "--disable-mdns")) {
        out.enableMdns = false
    }
    if (containsExactArg(args, "--enable-discovery-broadcast")) {
        out.discoveryBroadcastEnabled = true
    }
    if (containsExactArg(args, "--disable-discovery-broadcast")) {
        out.discoveryBroadcastEnabled = false
    }
    if (containsExactArg(args, "--trust-proxy-headers")) {
        out.localAuthTrustProxyHeaders = true
    }
    if (containsExactArg(args, "--no-trust-proxy-headers")) {
        out.localAuthTrustProxyHeaders = false
    }

    out
}

func finalizeAppConfig(config: AppConfig): AppConfig {
    var out = config
    if (out.localRootDir.size == 0) {
        try {
            out.localRootDir = getHomeDirectory().toString()
        } catch (_: Exception) {
            out.localRootDir = getEnvStr("HOME", "/tmp")
        }
    }
    if (out.nodeId.trimAscii().size == 0) {
        out.nodeId = generateNodeId(out)
    }
    out
}

func generateNodeId(config: AppConfig): String {
    let rawHost = getEnvStr("HOSTNAME", getEnvStr("HOST", "soonlink"))
    let host = normalizeNodeToken(rawHost)
    let fingerprint = stableNodeFingerprint("${config.configFile}|${config.localRootDir}|${config.webPort}")
    "node-${host}-${config.webPort}-${fingerprint}"
}

func normalizeNodeToken(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    if (normalized.size == 0 || normalized == "unknown") {
        return "soonlink"
    }

    var out = ""
    var pendingDash = false
    for (ch in normalized.toRuneArray()) {
        if ((ch >= r'a' && ch <= r'z') || (ch >= r'0' && ch <= r'9')) {
            if (pendingDash && out.size > 0) {
                out += "-"
            }
            out += ch.toString()
            pendingDash = false
        } else {
            pendingDash = out.size > 0
        }
    }
    if (out.size == 0) {
        return "soonlink"
    }
    out
}

func stableNodeFingerprint(raw: String): String {
    let digits = "0123456789abcdef".toRuneArray()
    var acc: Int64 = 17
    for (ch in raw.toRuneArray()) {
        acc = (acc * 131 + Int64(UInt32(ch))) % 16777215
    }
    if (acc < 0) {
        acc = -acc
    }

    let out = Array<String>(6, repeat: "0")
    var value = acc
    var i: Int64 = 5
    while (i >= 0) {
        out[i] = digits[value % 16].toString()
        value /= 16
        i -= 1
    }

    var result = ""
    for (part in out) {
        result += part
    }
    result
}

func normalizeCommandLine(commandLine: Array<String>): Array<String> {
    if (commandLine.size <= 1) {
        return Array<String>()
    }
    let args = Array<String>(commandLine.size - 1, repeat: "")
    var i: Int64 = 1
    while (i < commandLine.size) {
        args[i - 1] = commandLine[i]
        i += 1
    }
    args
}

func containsExactArg(args: Array<String>, target: String): Bool {
    for (arg in args) {
        if (arg == target) {
            return true
        }
    }
    false
}

func findArgValue(args: Array<String>, longName: String, shortName: String): ?String {
    var i: Int64 = 0
    while (i < args.size) {
        let current = args[i]
        if (current == longName || (shortName.size > 0 && current == shortName)) {
            if (i + 1 < args.size) {
                return Some(args[i + 1])
            }
            return None
        }
        if (longName.size > 0 && strStartsWith(current, longName + "=")) {
            return Some(strSubstring(current, longName.size + 1, current.size))
        }
        if (shortName.size > 0 && strStartsWith(current, shortName + "=")) {
            return Some(strSubstring(current, shortName.size + 1, current.size))
        }
        i += 1
    }
    None
}

func getEnvStr(key: String, defaultVal: String): String {
    if (let Some(value) <- getVariable(key)) {
        if (value.size > 0) {
            return value
        }
    }
    defaultVal
}

func getEnvInt(key: String, defaultVal: Int64): Int64 {
    if (let Some(value) <- getVariable(key)) {
        if (value.size > 0) {
            return parseIntOrDefault(value, defaultVal)
        }
    }
    defaultVal
}

func getEnvBool(key: String, defaultVal: Bool): Bool {
    if (let Some(value) <- getVariable(key)) {
        if (value.size > 0) {
            return parseBoolOrDefault(value, defaultVal)
        }
    }
    defaultVal
}

func parseIntOrDefault(raw: String, defaultVal: Int64): Int64 {
    try {
        Int64.parse(raw)
    } catch (_: Exception) {
        defaultVal
    }
}

func parseBoolOrDefault(raw: String, defaultVal: Bool): Bool {
    let normalized = raw.trimAscii().toLower()
    if (normalized == "true" || normalized == "1" || normalized == "yes") {
        return true
    }
    if (normalized == "false" || normalized == "0" || normalized == "no") {
        return false
    }
    defaultVal
}
