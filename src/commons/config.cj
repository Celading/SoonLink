package soonlnk.commons

import std.collection.HashMap
import std.convert.*
import std.env.{getVariable, getHomeDirectory}
import std.fs.remove
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
    public var adminPassword: String = ""
    public var adminBearerToken: String = ""
    public var adminSessionTtlSeconds: Int64 = 43200

    public var configFile: String = "./config/soonlink.toml"
    public var deviceRegistryFile: String = "./config/devices.json"
    public var logDir: String = "./logs"
    public var localRootDir: String = ""

    public var securityMode: String = "plain"
    public var discoveryUdpPort: Int64 = 19090
    public var enableMdns: Bool = true
    public var discoveryHeartbeatSeconds: Int64 = 30
    public var discoveryAdvertiseIp: String = ""
    public var discoveryBroadcastEnabled: Bool = true
    public var discoveryAuthKey: String = ""
    public var localAuthTrustProxyHeaders: Bool = false
    public var relayEnabled: Bool = true
    public var relayCacheDir: String = "./cache/relay"
    public var relayRetentionHours: Int64 = 24
    public var relayLimitMode: String = "fixed"
    public var relayLimitBytes: Int64 = 20 * 1024 * 1024 * 1024
    public var relayLimitPercent: Int64 = 10
    public var localSendEnabled: Bool = true
    public var localSendDiscoveryEnabled: Bool = true
    public var localSendAnnounceEnabled: Bool = true
    public var localSendAnnounceIntervalSeconds: Int64 = 5
    public var localSendAlias: String = ""
    public var localSendFingerprint: String = ""
    public var localSendDeviceModel: String = "SoonLink"
    public var localSendDeviceType: String = "desktop"
    public var localSendDownloadEnabled: Bool = true
    public var localSendAcceptPolicy: String = "manual"
    public var localSendDefaultSaveDir: String = "/tmpSL"
    public var localSendWhitelist: String = ""
    public var localSendBlacklist: String = ""
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
        adminPassword!: String = "",
        adminBearerToken!: String = "",
        adminSessionTtlSeconds!: Int64 = 43200,
        configFile!: String = "./config/soonlink.toml",
        deviceRegistryFile!: String = "./config/devices.json",
        logDir!: String = "./logs",
        localRootDir!: String = "",
        securityMode!: String = "plain",
        discoveryUdpPort!: Int64 = 19090,
        enableMdns!: Bool = true,
        discoveryHeartbeatSeconds!: Int64 = 30,
        discoveryAdvertiseIp!: String = "",
        discoveryBroadcastEnabled!: Bool = true,
        discoveryAuthKey!: String = "",
        localAuthTrustProxyHeaders!: Bool = false,
        relayEnabled!: Bool = true,
        relayCacheDir!: String = "./cache/relay",
        relayRetentionHours!: Int64 = 24,
        relayLimitMode!: String = "fixed",
        relayLimitBytes!: Int64 = 20 * 1024 * 1024 * 1024,
        relayLimitPercent!: Int64 = 10,
        localSendEnabled!: Bool = true,
        localSendDiscoveryEnabled!: Bool = true,
        localSendAnnounceEnabled!: Bool = true,
        localSendAnnounceIntervalSeconds!: Int64 = 5,
        localSendAlias!: String = "",
        localSendFingerprint!: String = "",
        localSendDeviceModel!: String = "SoonLink",
        localSendDeviceType!: String = "desktop",
        localSendDownloadEnabled!: Bool = true,
        localSendAcceptPolicy!: String = "manual",
        localSendDefaultSaveDir!: String = "/tmpSL",
        localSendWhitelist!: String = "",
        localSendBlacklist!: String = "",
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
        this.adminPassword = adminPassword
        this.adminBearerToken = adminBearerToken
        this.adminSessionTtlSeconds = adminSessionTtlSeconds
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
        this.discoveryAuthKey = discoveryAuthKey
        this.localAuthTrustProxyHeaders = localAuthTrustProxyHeaders
        this.relayEnabled = relayEnabled
        this.relayCacheDir = relayCacheDir
        this.relayRetentionHours = relayRetentionHours
        this.relayLimitMode = relayLimitMode
        this.relayLimitBytes = relayLimitBytes
        this.relayLimitPercent = relayLimitPercent
        this.localSendEnabled = localSendEnabled
        this.localSendDiscoveryEnabled = localSendDiscoveryEnabled
        this.localSendAnnounceEnabled = localSendAnnounceEnabled
        this.localSendAnnounceIntervalSeconds = localSendAnnounceIntervalSeconds
        this.localSendAlias = localSendAlias
        this.localSendFingerprint = localSendFingerprint
        this.localSendDeviceModel = localSendDeviceModel
        this.localSendDeviceType = localSendDeviceType
        this.localSendDownloadEnabled = localSendDownloadEnabled
        this.localSendAcceptPolicy = localSendAcceptPolicy
        this.localSendDefaultSaveDir = localSendDefaultSaveDir
        this.localSendWhitelist = localSendWhitelist
        this.localSendBlacklist = localSendBlacklist
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

    let fileMgr = LocalFileMgr()
    let selection = resolveConfigFileSelection(args, fileMgr: fileMgr)
    config.configFile = selection.path
    if (selection.path.size > 0 && fileMgr.exists(selection.path)) {
        let store = configStoreFor(selection.path)
        let storedValues = store.load()
        config = applyStoredConfig(config, storedValues)
    }

    config = applyEnvOverrides(config)
    config = applyArgOverrides(config, args)
    config = finalizeAppConfig(config)

    if (selection.shouldPersist && !selection.existed) {
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
    values.add("localsend_enabled", if (config.localSendEnabled) { "true" } else { "false" })
    values.add("localsend_discovery_enabled", if (config.localSendDiscoveryEnabled) { "true" } else { "false" })
    values.add("localsend_announce_enabled", if (config.localSendAnnounceEnabled) { "true" } else { "false" })
    values.add("localsend_announce_interval_seconds", "${config.localSendAnnounceIntervalSeconds}")
    values.add("localsend_alias", config.localSendAlias)
    values.add("localsend_fingerprint", config.localSendFingerprint)
    values.add("localsend_device_model", config.localSendDeviceModel)
    values.add("localsend_device_type", config.localSendDeviceType)
    values.add("localsend_download_enabled", if (config.localSendDownloadEnabled) { "true" } else { "false" })
    values.add("localsend_accept_policy", config.localSendAcceptPolicy)
    values.add("localsend_default_save_dir", config.localSendDefaultSaveDir)
    values.add("localsend_whitelist", config.localSendWhitelist)
    values.add("localsend_blacklist", config.localSendBlacklist)
    values.add("favorites_store_mode", config.favoritesStoreMode)
    values.add("favorites_toml_file", config.favoritesTomlFile)
    values.add("whitelist_toml_file", config.whitelistTomlFile)

    if (config.configFile.size == 0) {
        return
    }
    configStoreFor(config.configFile).save(values)
}

public func defaultSoonLinkConfigFile(): String {
    var home = ""
    try {
        home = getHomeDirectory().toString()
    } catch (_: Exception) {
        home = getEnvStr("HOME", "/tmp")
    }
    if (home.trimAscii().size == 0) {
        home = "/tmp"
    }
    home + "/.soonlink/etc/sl-config.toml"
}

public func fallbackSoonLinkConfigFile(): String {
    "./config/soonlink.toml"
}

public class ConfigFileSelection {
    public var path: String = ""
    public var shouldPersist: Bool = false
    public var existed: Bool = false

    public init(path!: String = "", shouldPersist!: Bool = false, existed!: Bool = false) {
        this.path = path
        this.shouldPersist = shouldPersist
        this.existed = existed
    }
}

func resolveConfigFileSelection(args: Array<String>, fileMgr!: FileMgr = LocalFileMgr()): ConfigFileSelection {
    if (let Some(configPath) <- findArgValue(args, "--config", "-c")) {
        return ConfigFileSelection(path: configPath, shouldPersist: true, existed: fileMgr.exists(configPath))
    }

    let envPath = getEnvStr("SOONLINK_CONFIG_FILE", "")
    if (envPath.size > 0) {
        return ConfigFileSelection(path: envPath, shouldPersist: true, existed: fileMgr.exists(envPath))
    }

    let userPath = defaultSoonLinkConfigFile()
    let userExisted = fileMgr.exists(userPath)
    if (configPathCanReadWrite(userPath, fileMgr: fileMgr)) {
        return ConfigFileSelection(path: userPath, shouldPersist: true, existed: userExisted)
    }

    let fallbackPath = fallbackSoonLinkConfigFile()
    let fallbackExisted = fileMgr.exists(fallbackPath)
    if (configPathCanReadWrite(fallbackPath, fileMgr: fileMgr)) {
        return ConfigFileSelection(path: fallbackPath, shouldPersist: true, existed: fallbackExisted)
    }

    ConfigFileSelection()
}

func configPathCanReadWrite(path: String, fileMgr!: FileMgr = LocalFileMgr()): Bool {
    if (path.size == 0) {
        return false
    }

    if (fileMgr.exists(path)) {
        try {
            let text = fileMgr.readText(path)
            fileMgr.writeText(path, text, false)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    let probePath = path + ".probe"
    try {
        fileMgr.writeText(probePath, "", false)
        try {
            remove(probePath)
        } catch (_: Exception) {}
        return true
    } catch (_: Exception) {
        try {
            remove(probePath)
        } catch (_: Exception) {}
        return false
    }
}

func applyStoredConfig(config: AppConfig, values: HashMap<String, String>): AppConfig {
    var out = config

    out.nodeId = getConfigValue(values, "node_id", "node", "id") ?? out.nodeId
    out.listenAddr = getConfigValue(values, "listen_addr", "listen", "listen_address") ?? out.listenAddr
    out.tempDir = getConfigValue(values, "temp_dir", "temp", "tmp_dir") ?? out.tempDir
    out.encryptionKey = getConfigValue(values, "encryption_key", "key", "") ?? out.encryptionKey
    out.certFile = getConfigValue(values, "cert_file", "cert", "") ?? out.certFile
    out.keyFile = getConfigValue(values, "key_file", "", "") ?? out.keyFile
    out.deviceRegistryFile = getConfigValue(values, "device_registry_file", "devices_file", "") ?? out.deviceRegistryFile
    out.logDir = getConfigValue(values, "log_dir", "logs", "") ?? out.logDir
    out.localRootDir = getConfigValue(values, "local_root_dir", "root_dir", "root") ?? out.localRootDir
    out.securityMode = getConfigValue(values, "security_mode", "security", "") ?? out.securityMode
    out.discoveryAdvertiseIp = getConfigValue(values, "discovery_advertise_ip", "advertise_ip", "") ?? out.discoveryAdvertiseIp
    out.relayCacheDir = getConfigValue(values, "relay_cache_dir", "relay_cache", "") ?? out.relayCacheDir
    out.relayLimitMode = getConfigValue(values, "relay_limit_mode", "", "") ?? out.relayLimitMode
    out.localSendAlias = getConfigValue(values, "localsend_alias", "local_send_alias", "localsend-alias") ?? out.localSendAlias
    out.localSendFingerprint = getConfigValue(values, "localsend_fingerprint", "local_send_fingerprint", "localsend-fingerprint") ?? out.localSendFingerprint
    out.localSendDeviceModel = getConfigValue(values, "localsend_device_model", "local_send_device_model", "localsend-device-model") ?? out.localSendDeviceModel
    out.localSendDeviceType = getConfigValue(values, "localsend_device_type", "local_send_device_type", "localsend-device-type") ?? out.localSendDeviceType
    out.localSendAcceptPolicy = getConfigValue(values, "localsend_accept_policy", "local_send_accept_policy", "localsend-accept-policy") ?? out.localSendAcceptPolicy
    out.localSendDefaultSaveDir = getConfigValue(values, "localsend_default_save_dir", "local_send_default_save_dir", "localsend-default-save-dir") ?? out.localSendDefaultSaveDir
    out.localSendWhitelist = getConfigValue(values, "localsend_whitelist", "local_send_whitelist", "localsend-whitelist") ?? out.localSendWhitelist
    out.localSendBlacklist = getConfigValue(values, "localsend_blacklist", "local_send_blacklist", "localsend-blacklist") ?? out.localSendBlacklist
    out.favoritesStoreMode = getConfigValue(values, "favorites_store_mode", "favorites_mode", "") ?? out.favoritesStoreMode
    out.favoritesTomlFile = getConfigValue(values, "favorites_toml_file", "favorites_file", "") ?? out.favoritesTomlFile
    out.whitelistTomlFile = getConfigValue(values, "whitelist_toml_file", "whitelist_file", "") ?? out.whitelistTomlFile

    if (let Some(v) <- getConfigValue(values, "web_port", "port", "")) {
        out.webPort = UInt16(parseIntOrDefault(v, Int64(out.webPort)))
    }
    if (let Some(v) <- getConfigValue(values, "max_connections", "connections", "")) {
        out.maxConnections = parseIntOrDefault(v, out.maxConnections)
    }
    if (let Some(v) <- getConfigValue(values, "discovery_udp_port", "discovery_port", "")) {
        out.discoveryUdpPort = parseIntOrDefault(v, out.discoveryUdpPort)
    }
    if (let Some(v) <- getConfigValue(values, "enable_mdns", "mdns", "")) {
        out.enableMdns = parseBoolOrDefault(v, out.enableMdns)
    }
    if (let Some(v) <- getConfigValue(values, "discovery_heartbeat_seconds", "heartbeat_seconds", "")) {
        out.discoveryHeartbeatSeconds = parseIntOrDefault(v, out.discoveryHeartbeatSeconds)
    }
    if (let Some(v) <- getConfigValue(values, "discovery_broadcast_enabled", "enable_discovery_broadcast", "")) {
        out.discoveryBroadcastEnabled = parseBoolOrDefault(v, out.discoveryBroadcastEnabled)
    }
    if (let Some(v) <- getConfigValue(values, "local_auth_trust_proxy_headers", "trust_proxy_headers", "")) {
        out.localAuthTrustProxyHeaders = parseBoolOrDefault(v, out.localAuthTrustProxyHeaders)
    }
    if (let Some(v) <- getConfigValue(values, "relay_enabled", "relay", "")) {
        out.relayEnabled = parseBoolOrDefault(v, out.relayEnabled)
    }
    if (let Some(v) <- getConfigValue(values, "relay_retention_hours", "relay_retention", "")) {
        out.relayRetentionHours = parseIntOrDefault(v, out.relayRetentionHours)
    }
    if (let Some(v) <- getConfigValue(values, "relay_limit_bytes", "", "")) {
        out.relayLimitBytes = parseIntOrDefault(v, out.relayLimitBytes)
    }
    if (let Some(v) <- getConfigValue(values, "relay_limit_percent", "", "")) {
        out.relayLimitPercent = parseIntOrDefault(v, out.relayLimitPercent)
    }
    if (let Some(v) <- getConfigValue(values, "localsend_enabled", "local_send_enabled", "localsend-enabled")) {
        out.localSendEnabled = parseBoolOrDefault(v, out.localSendEnabled)
    }
    if (let Some(v) <- getConfigValue(values, "localsend_discovery_enabled", "local_send_discovery_enabled", "localsend-discovery-enabled")) {
        out.localSendDiscoveryEnabled = parseBoolOrDefault(v, out.localSendDiscoveryEnabled)
    }
    if (let Some(v) <- getConfigValue(values, "localsend_announce_enabled", "local_send_announce_enabled", "localsend-announce-enabled")) {
        out.localSendAnnounceEnabled = parseBoolOrDefault(v, out.localSendAnnounceEnabled)
    }
    if (let Some(v) <- getConfigValue(values, "localsend_announce_interval_seconds", "local_send_announce_interval_seconds", "localsend-announce-interval-seconds")) {
        out.localSendAnnounceIntervalSeconds = parseIntOrDefault(v, out.localSendAnnounceIntervalSeconds)
    }
    if (let Some(v) <- getConfigValue(values, "localsend_download_enabled", "local_send_download_enabled", "localsend-download-enabled")) {
        out.localSendDownloadEnabled = parseBoolOrDefault(v, out.localSendDownloadEnabled)
    }

    out
}

func getConfigValue(values: HashMap<String, String>, primary: String, alias1: String, alias2: String): ?String {
    if (let Some(v) <- values.get(primary)) {
        return Some(v)
    }
    if (alias1.size > 0) {
        if (let Some(v) <- values.get(alias1)) {
            return Some(v)
        }
    }
    if (alias2.size > 0) {
        if (let Some(v) <- values.get(alias2)) {
            return Some(v)
        }
    }
    None
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
    out.adminPassword = getEnvStr("SOONLINK_ADMIN_PASSWORD", out.adminPassword)
    out.adminBearerToken = getEnvStr("SOONLINK_ADMIN_BEARER_TOKEN", out.adminBearerToken)
    out.adminSessionTtlSeconds = getEnvInt("SOONLINK_ADMIN_SESSION_TTL_SECONDS", out.adminSessionTtlSeconds)
    out.deviceRegistryFile = getEnvStr("SOONLINK_DEVICE_REGISTRY_FILE", out.deviceRegistryFile)
    out.logDir = getEnvStr("SOONLINK_LOG_DIR", out.logDir)
    out.localRootDir = getEnvStr("SOONLINK_LOCAL_ROOT_DIR", out.localRootDir)
    out.securityMode = getEnvStr("SOONLINK_SECURITY_MODE", out.securityMode)
    out.discoveryUdpPort = getEnvInt("SOONLINK_DISCOVERY_UDP_PORT", out.discoveryUdpPort)
    out.enableMdns = getEnvBool("SOONLINK_ENABLE_MDNS", out.enableMdns)
    out.discoveryHeartbeatSeconds = getEnvInt("SOONLINK_DISCOVERY_HEARTBEAT_SECONDS", out.discoveryHeartbeatSeconds)
    out.discoveryAdvertiseIp = getEnvStr("SOONLINK_DISCOVERY_ADVERTISE_IP", out.discoveryAdvertiseIp)
    out.discoveryBroadcastEnabled = getEnvBool("SOONLINK_DISCOVERY_BROADCAST_ENABLED", out.discoveryBroadcastEnabled)
    out.discoveryAuthKey = getEnvStr("SOONLINK_DISCOVERY_AUTH_KEY", out.discoveryAuthKey)
    out.localAuthTrustProxyHeaders = getEnvBool("SOONLINK_LOCAL_AUTH_TRUST_PROXY_HEADERS", out.localAuthTrustProxyHeaders)
    out.relayEnabled = getEnvBool("SOONLINK_RELAY_ENABLED", out.relayEnabled)
    out.relayCacheDir = getEnvStr("SOONLINK_RELAY_CACHE_DIR", out.relayCacheDir)
    out.relayRetentionHours = getEnvInt("SOONLINK_RELAY_RETENTION_HOURS", out.relayRetentionHours)
    out.relayLimitMode = getEnvStr("SOONLINK_RELAY_LIMIT_MODE", out.relayLimitMode)
    out.relayLimitBytes = getEnvInt("SOONLINK_RELAY_LIMIT_BYTES", out.relayLimitBytes)
    out.relayLimitPercent = getEnvInt("SOONLINK_RELAY_LIMIT_PERCENT", out.relayLimitPercent)
    out.localSendEnabled = getEnvBool("SOONLINK_LOCALSEND_ENABLED", out.localSendEnabled)
    out.localSendDiscoveryEnabled = getEnvBool("SOONLINK_LOCALSEND_DISCOVERY_ENABLED", out.localSendDiscoveryEnabled)
    out.localSendAnnounceEnabled = getEnvBool("SOONLINK_LOCALSEND_ANNOUNCE_ENABLED", out.localSendAnnounceEnabled)
    out.localSendAnnounceIntervalSeconds = getEnvInt("SOONLINK_LOCALSEND_ANNOUNCE_INTERVAL_SECONDS", out.localSendAnnounceIntervalSeconds)
    out.localSendAlias = getEnvStr("SOONLINK_LOCALSEND_ALIAS", out.localSendAlias)
    out.localSendFingerprint = getEnvStr("SOONLINK_LOCALSEND_FINGERPRINT", out.localSendFingerprint)
    out.localSendDeviceModel = getEnvStr("SOONLINK_LOCALSEND_DEVICE_MODEL", out.localSendDeviceModel)
    out.localSendDeviceType = getEnvStr("SOONLINK_LOCALSEND_DEVICE_TYPE", out.localSendDeviceType)
    out.localSendDownloadEnabled = getEnvBool("SOONLINK_LOCALSEND_DOWNLOAD_ENABLED", out.localSendDownloadEnabled)
    out.localSendAcceptPolicy = getEnvStr("SOONLINK_LOCALSEND_ACCEPT_POLICY", out.localSendAcceptPolicy)
    out.localSendDefaultSaveDir = getEnvStr("SOONLINK_LOCALSEND_DEFAULT_SAVE_DIR", out.localSendDefaultSaveDir)
    out.localSendWhitelist = getEnvStr("SOONLINK_LOCALSEND_WHITELIST", out.localSendWhitelist)
    out.localSendBlacklist = getEnvStr("SOONLINK_LOCALSEND_BLACKLIST", out.localSendBlacklist)
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
    if (let Some(v) <- findArgValue(args, "--discovery-auth-key", "")) {
        out.discoveryAuthKey = v
    }
    if (let Some(v) <- findArgValue(args, "--max-connections", "")) {
        out.maxConnections = parseIntOrDefault(v, out.maxConnections)
    }
    if (let Some(v) <- findArgValue(args, "--favorites-mode", "")) {
        out.favoritesStoreMode = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-announce-interval-seconds", "")) {
        out.localSendAnnounceIntervalSeconds = parseIntOrDefault(v, out.localSendAnnounceIntervalSeconds)
    }
    if (let Some(v) <- findArgValue(args, "--localsend-alias", "")) {
        out.localSendAlias = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-fingerprint", "")) {
        out.localSendFingerprint = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-device-model", "")) {
        out.localSendDeviceModel = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-device-type", "")) {
        out.localSendDeviceType = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-accept-policy", "")) {
        out.localSendAcceptPolicy = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-default-save-dir", "")) {
        out.localSendDefaultSaveDir = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-whitelist", "")) {
        out.localSendWhitelist = v
    }
    if (let Some(v) <- findArgValue(args, "--localsend-blacklist", "")) {
        out.localSendBlacklist = v
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
    if (containsExactArg(args, "--enable-localsend")) {
        out.localSendEnabled = true
    }
    if (containsExactArg(args, "--disable-localsend")) {
        out.localSendEnabled = false
    }
    if (containsExactArg(args, "--enable-localsend-discovery")) {
        out.localSendDiscoveryEnabled = true
    }
    if (containsExactArg(args, "--disable-localsend-discovery")) {
        out.localSendDiscoveryEnabled = false
    }
    if (containsExactArg(args, "--enable-localsend-announce")) {
        out.localSendAnnounceEnabled = true
    }
    if (containsExactArg(args, "--disable-localsend-announce")) {
        out.localSendAnnounceEnabled = false
    }
    if (containsExactArg(args, "--enable-localsend-download")) {
        out.localSendDownloadEnabled = true
    }
    if (containsExactArg(args, "--disable-localsend-download")) {
        out.localSendDownloadEnabled = false
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
    if (out.adminSessionTtlSeconds <= 0) {
        out.adminSessionTtlSeconds = 43200
    }
    if (out.localSendAnnounceIntervalSeconds <= 0) {
        out.localSendAnnounceIntervalSeconds = 5
    }
    out.localSendAcceptPolicy = normalizeLocalSendAcceptPolicy(out.localSendAcceptPolicy)
    if (out.localSendDefaultSaveDir.trimAscii().size == 0) {
        out.localSendDefaultSaveDir = "/tmpSL"
    }
    if (out.localSendDeviceModel.trimAscii().size == 0) {
        out.localSendDeviceModel = "SoonLink"
    }
    if (out.localSendDeviceType.trimAscii().size == 0) {
        out.localSendDeviceType = "desktop"
    }
    out
}

public func normalizeLocalSendAcceptPolicy(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    if (normalized == "auto" || normalized == "whitelist" || normalized == "reject" || normalized == "manual") {
        return normalized
    }
    "manual"
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
