package soonlnk.master

import soonlnk.api2.*
import soonlnk.commons.*
import soonlnk.features.*
import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.unicode.*
import std.sync.Mutex
import std.fs.{File, OpenMode}
import stdx.net.http.HttpResponseWriter
import ignite.{App, Ctx, Config, FormFile, Handler, Group, RouteOption, ResponseSpec, ParamSpec, ParamLocation, SwaggerInfo}
import ignite.middleware.{loggerMiddleware, corsMiddleware, recoverMiddleware, CorsConfig}
import ignite.api2.GetData

var folderVisibilitySettings: HashMap<String, Bool> = HashMap<String, Bool>()
var hideDotEntriesInExplorer: Bool = false
var hideCacheEntriesInExplorer: Bool = false
var lastKnownLocalIP: String = ""

let listDirCacheMutex: Mutex = Mutex()
var listDirCache: HashMap<String, ListDirCacheEntry> = HashMap<String, ListDirCacheEntry>()
let listDirCacheTTLSeconds: Int64 = 2
let previewTextMaxBytes: Int64 = 256 * 1024

public class ListDirCacheEntry {
    public let entries: ArrayList<FileEntry>
    public let cachedAt: Int64
    public init(entries: ArrayList<FileEntry>, cachedAt: Int64) {
        this.entries = entries
        this.cachedAt = cachedAt
    }
}

public class VisibilityFolderNode {
    public let path: String
    public let name: String
    public let depth: Int64
    public let visible: Bool

    public init(path: String, name: String, depth: Int64, visible: Bool) {
        this.path = path
        this.name = name
        this.depth = depth
        this.visible = visible
    }

    public func toJson(): JsonObject {
        JsonObject()
            .put("path", path)
            .put("name", name)
            .putInt("depth", depth)
            .putBool("visible", visible)
    }
}

class TextPreviewSnippet {
    var content: String = ""
    var encoding: String = "utf-8"
    var lineCount: Int64 = 0
    var truncated: Bool = false

    init() {}
}

public struct WebAccessContext {
    public var isLocalAdmin: Bool = false
    public var accessMode: String = "remote"
    public var themeVariant: String = "remote"
    public var clientIP: String = ""
    public var resolvedIP: String = ""

    public init(
        isLocalAdmin!: Bool = false,
        accessMode!: String = "remote",
        themeVariant!: String = "remote",
        clientIP!: String = "",
        resolvedIP!: String = ""
    ) {
        this.isLocalAdmin = isLocalAdmin
        this.accessMode = accessMode
        this.themeVariant = themeVariant
        this.clientIP = clientIP
        this.resolvedIP = resolvedIP
    }
}

public func resolveWebAccessContext(
    clientIP: String,
    forwardedFor: String,
    trustProxyHeaders: Bool
): WebAccessContext {
    let normalizedClientIP = normalizeClientIP(clientIP)
    let forwardedFirst = extractFirstForwardedIP(forwardedFor)
    var resolvedIP = normalizedClientIP
    if (trustProxyHeaders && forwardedFirst.size > 0) {
        resolvedIP = normalizeClientIP(forwardedFirst)
    }

    let isLocalAdmin = isLocalAddress(resolvedIP)
    WebAccessContext(
        isLocalAdmin: isLocalAdmin,
        accessMode: if (isLocalAdmin) { "local-admin" } else { "remote" },
        themeVariant: if (isLocalAdmin) { "admin" } else { "remote" },
        clientIP: normalizedClientIP,
        resolvedIP: resolvedIP
    )
}

func buildLocalOnlyMiddleware(config: AppConfig): Handler {
    { ctx: Ctx =>
        let access = resolveWebAccessContext(
            ctx.ip,
            ctx.header("x-forwarded-for") ?? "",
            config.localAuthTrustProxyHeaders
        )
        if (access.isLocalAdmin) {
            ctx.next()
            return
        }
        ctx.status(403).json(JsonObject()
            .put("error", "Access denied - Admin panel only accessible from localhost")
            .put("code", "ADMIN_ACCESS_DENIED")
            .toString())
    }
}

func requireLocalApiAdmin(ctx: Ctx, config: AppConfig): Bool {
    let access = resolveWebAccessContext(
        ctx.ip,
        ctx.header("x-forwarded-for") ?? "",
        config.localAuthTrustProxyHeaders
    )
    if (access.isLocalAdmin) {
        return true
    }
    ctx.status(403).json(JsonObject()
        .putBool("success", false)
        .put("error", "仅本机管理员可维护手动节点")
        .put("code", "ADMIN_ACCESS_DENIED")
        .toString())
    false
}

func extractFirstForwardedIP(forwardedFor: String): String {
    let trimmed = forwardedFor.trimAscii()
    if (trimmed.size == 0) {
        return ""
    }
    let runes = trimmed.toRuneArray()
    var splitAt: Int64 = trimmed.size
    for (i in 0..runes.size) {
        if (runes[i] == r',') {
            splitAt = i
            break
        }
    }
    normalizeClientIP(strSubstring(trimmed, 0, splitAt))
}

func normalizeClientIP(raw: String): String {
    var ip = raw.trimAscii().toLower()
    if (ip.size == 0) {
        return ""
    }

    if (strStartsWith(ip, "[")) {
        let runes = ip.toRuneArray()
        var closeAt: Int64 = -1
        for (i in 0..runes.size) {
            if (runes[i] == r']') {
                closeAt = i
                break
            }
        }
        if (closeAt > 1) {
            ip = strSubstring(ip, 1, closeAt)
        }
    } else if (ip.contains(".") && ip.contains(":")) {
        let runes = ip.toRuneArray()
        var lastColon: Int64 = -1
        for (i in 0..runes.size) {
            if (runes[i] == r':') {
                lastColon = i
            }
        }
        if (lastColon > 0) {
            ip = strSubstring(ip, 0, lastColon)
        }
    }

    if (strStartsWith(ip, "::ffff:")) {
        ip = strTrimPrefix(ip, "::ffff:")
    }
    if (ip == "0:0:0:0:0:0:0:1") {
        return "::1"
    }
    ip
}

func isLocalAddress(ip: String): Bool {
    let normalized = normalizeClientIP(ip)
    normalized == "127.0.0.1" || normalized == "::1" || normalized == "localhost"
}

public class WebServer {
    let server: CoreServer
    let masters: MasterBundle
    let fileHelper: FileHelper
    let port: UInt16
    let app: App
    var ipMonitorRunning: Bool = false

    public init(server: CoreServer, port: UInt16) {
        this.server = server
        this.masters = MasterBundle(server)
        this.fileHelper = FileHelper()
        this.port = port

        let igniteConfig = Config(
            appName: resolveRuntimeDisplayName(server.profile),
            appVersion: currentProductVersion(),
            serverHeader: "${resolveTechnicalPackageName(server.profile.productName)}-Cj",
            bodyLimit: 100 * 1024 * 1024,
            enableSwagger: true,
            enablePrintRoutes: false,
        )
        this.app = App.create(config: igniteConfig)
    }

    public func start(): Unit {
        app.swagger(SwaggerInfo(
            title: "${resolveRuntimeDisplayName(server.profile)} / 溯联 API",
            description: "${resolveRuntimeDisplayName(server.profile)}（溯联）文件传输服务 API 文档",
            version: currentProductVersion()
        ))

        app.use(recoverMiddleware())
        app.use(loggerMiddleware())
        app.use(corsMiddleware())

        app.`static`("/static", "./web/static")

        setupRoutes()

        let bindHost = resolveBindHost(server.config.listenAddr)
        let localIP = server.refreshLocalDeviceAddress()
        match (server.getDevice("local")) {
            case Some(localDevice) =>
                println("当前设备: ${localDevice.name}  ${localDevice.ip}:${localDevice.port}")
            case None => ()
        }
        logAccessUrls(server, localIP, port)

        lastKnownLocalIP = localIP
        ipMonitorRunning = true
        spawn {
            while (ipMonitorRunning) {
                sleep(Duration.second * 60)
                if (!ipMonitorRunning) {
                    break
                }
                let current = server.refreshLocalDeviceAddress()
                if (current != lastKnownLocalIP) {
                    let displayIP = if (current.size > 0) { current } else { "127.0.0.1" }
                    println("[WARN] 设备IP已变动，当前IP: " + displayIP)
                    logAccessUrls(server, displayIP, port)
                    lastKnownLocalIP = current
                }
            }
        }

        app.listen(bindHost, port)
    }

    public func stop(): Unit {
        ipMonitorRunning = false
        app.shutdown()
    }

    func setupRoutes(): Unit {
        let s = server
        let m = masters

        // ── 首页 ──
        app.get("/", { ctx: Ctx =>
            try {
                let html = renderTemplate("./web/views/index.html", [("Title", "SoonLink文件传输系统")])
                ctx.html(html)
            } catch (_: Exception) {
                ctx.html("<h1>SoonLink文件传输系统</h1><p>Powered by Ignite (Cangjie)</p>")
            }
        }, option: RouteOption()
            .withSummary("首页")
            .withTag("页面")
            .asHidden()
        )

        app.get("/login", { ctx: Ctx =>
            try {
                let html = renderTemplate("./web/views/login.html", [("Title", "SoonLink 登录入口")])
                ctx.html(html)
            } catch (_: Exception) {
                ctx.html("<h1>SoonLink 登录入口</h1><p>Core 版本仅提供能力占位，不启用远程提权。</p>")
            }
        }, option: RouteOption()
            .withSummary("登录入口（能力预留）")
            .withTag("页面")
            .asHidden()
        )

        // ── 健康检查 ──
        app.get("/health", { ctx: Ctx =>
            ctx.json(JsonObject()
                .put("status", "healthy")
                .putInt("timestamp", currentTimestamp())
                .putInt("uptime", s.uptimeSeconds())
                .toString())
        }, option: RouteOption()
            .withSummary("健康检查")
            .withTag("系统")
            .withResponse(ResponseSpec(200, description: "健康状态"))
        )

        app.get("/api/health", { ctx: Ctx =>
            let devices = s.listDevices()
            let tasks = s.listTasks()
            ctx.json(JsonObject()
                .put("status", "healthy")
                .putInt("timestamp", currentTimestamp())
                .putInt("uptime", s.uptimeSeconds())
                .putInt("devices", devices.size)
                .putInt("activeTasks", tasks.size)
                .put("version", currentProductVersion())
                .toString())
        }, option: RouteOption()
            .withSummary("API 健康检查")
            .withTag("系统")
            .withResponse(ResponseSpec(200, description: "详细健康状态"))
        )

        // ── 系统信息 ──
        app.get("/api/info", { ctx: Ctx =>
            let devices = s.listDevices()
            let tasks = s.listTasks()
            var onlineDevices: Int64 = 0
            for (d in devices) {
                if (d.online) { onlineDevices += 1 }
            }
            var taskStats = HashMap<String, Int64>()
            for (t in tasks) {
                let key = taskStatusToString(t.status)
                let count = taskStats.get(key) ?? 0
                taskStats.add(key, count + 1)
            }
            let statsObj = JsonObject()
            for ((k, v) in taskStats) {
                statsObj.putInt(k, v)
            }
            ctx.json(JsonObject()
                .putObj("system", JsonObject()
                    .put("version", currentProductVersion())
                    .put("displayName", resolveRuntimeDisplayName(s.profile))
                    .putInt("uptime", s.uptimeSeconds())
                    .putInt("timestamp", currentTimestamp()))
                .putObj("devices", JsonObject()
                    .putInt("total", devices.size)
                    .putInt("online", onlineDevices))
                .putObj("tasks", JsonObject()
                    .putInt("total", tasks.size)
                    .putObj("stats", statsObj))
                .toString())
        }, option: RouteOption()
            .withSummary("获取系统信息")
            .withTag("系统")
        )

        // ── 管理员路由组 ──
        let admin = app.group("/admin")
        admin.use(buildLocalOnlyMiddleware(s.config))

        admin.get("/", { ctx: Ctx =>
            try {
                let html = renderTemplate("./web/views/admin.html", [("Title", "SoonLink管理员面板")])
                ctx.html(html)
            } catch (_: Exception) {
                ctx.html("<h1>SoonLink管理员面板</h1>")
            }
        })

        admin.get("/logs", { ctx: Ctx =>
            try {
                let html = renderTemplate("./web/views/admin.html", [("Title", "系统日志"), ("Page", "logs")])
                ctx.html(html)
            } catch (_: Exception) {
                ctx.html("<h1>系统日志</h1>")
            }
        })

        admin.get("/config", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .putObj("config", appConfigToJson(s.config, s.profile))
                .toString())
        })

        admin.post("/config", { ctx: Ctx =>
            let body = ctx.bodyString()
            var updated = s.config

            if (let Some(v) <- parseJsonString(body, "tempDir")) {
                if (v.size > 0) { updated.tempDir = v }
            }
            if (let Some(v) <- parseJsonString(body, "maxConnections")) {
                try { updated.maxConnections = Int64.parse(v) } catch (_: Exception) {}
            }
            if (let Some(v) <- parseJsonString(body, "logDir")) {
                if (v.size > 0) { updated.logDir = v }
            }
            if (let Some(v) <- parseJsonString(body, "localRootDir")) {
                if (v.size > 0) { updated.localRootDir = v }
            }
            if (s.profile.supportsPeerTransfer) {
                if (let Some(v) <- parseJsonString(body, "securityMode")) {
                    updated.securityMode = s.setSecurityMode(v)
                }
            }
            if (s.profile.supportsActiveDiscovery) {
                if (let Some(v) <- parseJsonString(body, "enableMdns")) {
                    updated.enableMdns = v == "true"
                }
            }
            if (s.profile.supportsActiveDiscovery) {
                if (let Some(v) <- parseJsonString(body, "discoveryUdpPort")) {
                    try { updated.discoveryUdpPort = Int64.parse(v) } catch (_: Exception) {}
                }
            }
            if (let Some(v) <- parseJsonString(body, "localAuthTrustProxyHeaders")) {
                updated.localAuthTrustProxyHeaders = v == "true"
            }
            if (s.profile.supportsRelay) {
                if (let Some(v) <- parseJsonString(body, "relayEnabled")) {
                    updated.relayEnabled = v == "true"
                }
            }
            if (s.profile.supportsRelay) {
                if (let Some(v) <- parseJsonString(body, "relayCacheDir")) {
                    if (v.size > 0) { updated.relayCacheDir = v }
                }
            }
            if (s.profile.supportsRelay) {
                if (let Some(v) <- parseJsonString(body, "relayRetentionHours")) {
                    try { updated.relayRetentionHours = Int64.parse(v) } catch (_: Exception) {}
                }
            }
            if (s.profile.supportsRelay) {
                if (let Some(v) <- parseJsonString(body, "relayLimitMode")) {
                    if (v == "fixed" || v == "percent") { updated.relayLimitMode = v }
                }
            }
            if (s.profile.supportsRelay) {
                if (let Some(v) <- parseJsonString(body, "relayLimitBytes")) {
                    try { updated.relayLimitBytes = Int64.parse(v) } catch (_: Exception) {}
                }
            }
            if (s.profile.supportsRelay) {
                if (let Some(v) <- parseJsonString(body, "relayLimitPercent")) {
                    try { updated.relayLimitPercent = Int64.parse(v) } catch (_: Exception) {}
                }
            }
            if (s.profile.supportsFavorites) {
                if (let Some(v) <- parseJsonString(body, "favoritesStoreMode")) {
                    if (v == "cache" || v == "toml") { updated.favoritesStoreMode = v }
                }
            }
            if (s.profile.supportsFavorites) {
                if (let Some(v) <- parseJsonString(body, "favoritesTomlFile")) {
                    if (v.size > 0) { updated.favoritesTomlFile = v }
                }
            }
            if (s.profile.supportsWhitelist) {
                if (let Some(v) <- parseJsonString(body, "whitelistTomlFile")) {
                    if (v.size > 0) { updated.whitelistTomlFile = v }
                }
            }

            updated = normalizeAppConfigForProfile(updated, s.profile)
            saveAppConfig(updated)

            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "配置已写入配置文件，重启后生效")
                .putObj("config", appConfigToJson(updated, s.profile))
                .toString())
        })

        admin.get("/cleanup", { ctx: Ctx =>
            ctx.json(JsonObject().putBool("success", true).put("message", "系统清理").toString())
        })

        admin.post("/cleanup", { ctx: Ctx =>
            ctx.json(JsonObject().putBool("success", true).put("message", "清理任务已排队").toString())
        })

        admin.post("/shutdown", { ctx: Ctx =>
            ctx.json(JsonObject().putBool("success", true).put("message", "系统将在3秒后关闭").toString())
        })

        // 管理员API
        let adminApi = admin.group("/api")

        adminApi.get("/logs", { ctx: Ctx =>
            let limitStr = ctx.queryDefault("limit", "200")
            var limit: Int64 = 200
            try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
            if (limit <= 0) { limit = 200 }
            if (limit > 500) { limit = 500 }

            let logs = m.logs.list(limit)
            let logsArr = JsonArray()
            for (entry in logs) {
                logsArr.addObj(entry.toJson())
            }
            ctx.json(JsonObject()
                .putBool("success", true)
                .putArr("logs", logsArr)
                .putInt("total", logs.size)
                .toString())
        })

        adminApi.get("/system", { ctx: Ctx =>
            ctx.json(buildAdminSystemPayload(s, m).toString())
        })

        adminApi.get("/drives", { ctx: Ctx =>
            ctx.json(buildAdminDrivesPayload(s).toString())
        })

        adminApi.post("/visibility", { ctx: Ctx =>
            let body = ctx.bodyString()
            var updated: Bool = false

            if (let Some(raw) <- parseJsonString(body, "hideDotEntries")) {
                hideDotEntriesInExplorer = raw == "true"
                updated = true
            }

            if (let Some(raw) <- parseJsonString(body, "hideCacheEntries")) {
                hideCacheEntriesInExplorer = raw == "true"
                updated = true
            }

            if (let Some(rawPath) <- parseJsonString(body, "path")) {
                if (rawPath.trimAscii().size > 0) {
                    let path = normalizeFolderPath(rawPath)
                    let visibleStr = parseJsonString(body, "visible") ?? "true"
                    let visible = visibleStr == "true"
                    folderVisibilitySettings.add(path, visible)
                    updated = true
                }
            }

            if (!updated) {
                ctx.status(400).json(JsonObject().putBool("success", false).put("error", "至少提供 path 或过滤开关").toString())
                return
            }

            invalidateListDirCache()
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "可见性设置已更新")
                .putObj("filters", JsonObject()
                    .putBool("hideDotEntries", hideDotEntriesInExplorer)
                    .putBool("hideCacheEntries", hideCacheEntriesInExplorer))
                .toString())
        })

        adminApi.get("/visibility", { ctx: Ctx =>
            let settingsObj = JsonObject()
            for ((path, visible) in folderVisibilitySettings) {
                settingsObj.putBool(path, visible)
            }
            ctx.json(JsonObject()
                .putBool("success", true)
                .putObj("settings", settingsObj)
                .putObj("filters", JsonObject()
                    .putBool("hideDotEntries", hideDotEntriesInExplorer)
                    .putBool("hideCacheEntries", hideCacheEntriesInExplorer))
                .putArr("folders", buildVisibilityFolders(m))
                .toString())
        })

        // ── API路由 ──
        let api = app.group("/api")

        api.get("/session/context", { ctx: Ctx =>
            let access = resolveWebAccessContext(
                ctx.ip,
                ctx.header("x-forwarded-for") ?? "",
                s.config.localAuthTrustProxyHeaders
            )
            ctx.json(buildSessionContextPayload(s, access).toString())
        }, option: RouteOption()
            .withSummary("获取当前访问上下文")
            .withTag("会话")
        )

        api.get("/connectors", { ctx: Ctx =>
            let deviceId = ctx.queryDefault("device", "")
            let connectors = JsonArray()
            for (descriptor in s.listConnectors()) {
                connectors.addObj(descriptor.toJson())
            }

            let devices = JsonArray()
            if (deviceId.size > 0) {
                match (s.getDevice(deviceId)) {
                    case Some(device) =>
                        devices.addObj(buildConnectorBindingJson(s, device))
                    case None =>
                        ctx.status(404).json(JsonObject()
                            .putBool("success", false)
                            .put("error", "设备不存在")
                            .toString())
                        return
                }
            } else {
                for (device in s.listDevices()) {
                    devices.addObj(buildConnectorBindingJson(s, device))
                }
            }

            ctx.json(JsonObject()
                .putBool("success", true)
                .putArr("connectors", connectors)
                .putArr("devices", devices)
                .toString())
        }, option: RouteOption()
            .withSummary("列出连接器驱动与设备绑定关系")
            .withTag("连接器")
        )

        // 设备相关
        let devices = api.group("/devices")

        devices.get("/", { ctx: Ctx =>
            let deviceList = m.devices.listDevices()
            let arr = JsonArray()
            for (d in deviceList) {
                arr.addObj(d.toJson())
            }
            ctx.json(arr.toString())
        }, option: RouteOption()
            .withSummary("列出所有设备")
            .withTag("设备")
            .withResponse(ResponseSpec(200, description: "设备列表"))
        )

        devices.get("/:id", { ctx: Ctx =>
            let id = ctx.params("id")
            match (m.devices.getDevice(id)) {
                case Some(device) => ctx.json(device.toJson().toString())
                case None => ctx.status(404).json(
                    JsonObject().put("error", "设备不存在").toString())
            }
        }, option: RouteOption()
            .withSummary("获取设备信息")
            .withTag("设备")
            .withParam(ParamSpec("id", Path, description: "设备ID", required: true))
        )

        devices.post("/register", { ctx: Ctx =>
            if (!requireLocalApiAdmin(ctx, s.config)) {
                return
            }
            let body = ctx.bodyString()
            let record = buildManagedDeviceRecordFromJson(body, "", Int64(s.config.webPort))
            let validationError = s.validateManagedDeviceRecord(record)
            if (validationError.size > 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", validationError)
                    .toString())
                return
            }

            let device = m.devices.upsert(record)
            ctx.json(JsonObject()
                .putBool("success", true)
                .putObj("device", device.toJson())
                .put("message", "设备注册成功")
                .toString())
        }, option: RouteOption()
            .withSummary("手动注册设备")
            .withTag("设备")
        )

        devices.put("/:id", { ctx: Ctx =>
            if (!requireLocalApiAdmin(ctx, s.config)) {
                return
            }

            let routeId = ctx.params("id").trimAscii()
            if (routeId.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "设备ID不能为空")
                    .toString())
                return
            }

            let body = ctx.bodyString()
            let bodyId = (parseJsonString(body, "id") ?? "").trimAscii()
            if (bodyId.size > 0 && bodyId != routeId) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "路径设备ID与请求体不一致")
                    .toString())
                return
            }

            let record = buildManagedDeviceRecordFromJson(body, routeId, Int64(s.config.webPort))
            let validationError = s.validateManagedDeviceRecord(record)
            if (validationError.size > 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", validationError)
                    .toString())
                return
            }

            let device = m.devices.upsert(record)
            ctx.json(JsonObject()
                .putBool("success", true)
                .putObj("device", device.toJson())
                .put("message", "设备端点已保存")
                .toString())
        }, option: RouteOption()
            .withSummary("保存或更新手动设备端点")
            .withTag("设备")
            .withParam(ParamSpec("id", Path, description: "设备ID", required: true))
        )

        devices.delete("/:id", { ctx: Ctx =>
            if (!requireLocalApiAdmin(ctx, s.config)) {
                return
            }

            let routeId = ctx.params("id").trimAscii()
            if (routeId.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "设备ID不能为空")
                    .toString())
                return
            }

            if (!m.devices.remove(routeId)) {
                ctx.status(404).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "设备不存在或已删除")
                    .toString())
                return
            }

            ctx.json(JsonObject()
                .putBool("success", true)
                .put("deviceId", routeId)
                .put("message", "设备端点已删除")
                .toString())
        }, option: RouteOption()
            .withSummary("删除手动设备端点")
            .withTag("设备")
            .withParam(ParamSpec("id", Path, description: "设备ID", required: true))
        )

        devices.post("/heartbeat", { ctx: Ctx =>
            let body = ctx.bodyString()
            let id = parseJsonString(body, "id") ?? ""
            if (id.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "设备ID不能为空")
                    .toString())
                return
            }

            match (m.devices.heartbeat(id)) {
                case Some(device) =>
                    ctx.json(JsonObject()
                        .putBool("success", true)
                        .putObj("device", device.toJson())
                        .put("message", "心跳已更新")
                        .toString())
                case None =>
                    ctx.status(404).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "设备不存在")
                        .toString())
            }
        }, option: RouteOption()
            .withSummary("设备心跳上报")
            .withTag("设备")
        )

        devices.post("/:id/trust", { ctx: Ctx =>
            if (!requireLocalApiAdmin(ctx, s.config)) {
                return
            }

            let deviceId = ctx.params("id").trimAscii()
            let body = ctx.bodyString()
            let state = parseJsonString(body, "state") ?? ""
            if (deviceId.size == 0 || state.trimAscii().size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "deviceId 与 state 不能为空")
                    .toString())
                return
            }

            try {
                let device = m.devices.setTrust(deviceId, state)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putObj("device", device.toJson())
                    .put("message", "设备授信状态已更新")
                    .toString())
            } catch (e: Exception) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", e.message)
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("更新设备授信状态")
            .withTag("设备")
            .withParam(ParamSpec("id", Path, description: "设备ID", required: true))
        )

        devices.post("/:id/pairing/pin", { ctx: Ctx =>
            if (!requireLocalApiAdmin(ctx, s.config)) {
                return
            }

            let deviceId = ctx.params("id").trimAscii()
            if (deviceId.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "设备ID不能为空")
                    .toString())
                return
            }

            try {
                let session = m.devices.startPinPairing(deviceId)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putObj("pairing", session.toJson())
                    .put("message", "PIN 配对口令已生成")
                    .toString())
            } catch (e: Exception) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", e.message)
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("创建设备 PIN 配对口令")
            .withTag("设备")
            .withParam(ParamSpec("id", Path, description: "设备ID", required: true))
        )

        devices.post("/:id/pairing/confirm", { ctx: Ctx =>
            if (!requireLocalApiAdmin(ctx, s.config)) {
                return
            }

            let deviceId = ctx.params("id").trimAscii()
            let body = ctx.bodyString()
            let pin = parseJsonString(body, "pin") ?? ""
            if (deviceId.size == 0 || pin.trimAscii().size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "设备ID 与 PIN 不能为空")
                    .toString())
                return
            }

            try {
                let device = m.devices.confirmPinPairing(deviceId, pin)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putObj("device", device.toJson())
                    .put("message", "PIN 配对成功，设备已授信")
                    .toString())
            } catch (e: Exception) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", e.message)
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("确认设备 PIN 配对")
            .withTag("设备")
            .withParam(ParamSpec("id", Path, description: "设备ID", required: true))
        )

        // Relay / Whitelist / Favorites
        if (s.profile.supportsRelay) {
            let relay = api.group("/relay")
            let relayJobs = relay.group("/jobs")

            relayJobs.get("/", { ctx: Ctx =>
                let jobs = m.relay.list()
                let arr = JsonArray()
                for (job in jobs) {
                    arr.addObj(job.toJson())
                }
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putArr("jobs", arr)
                    .toString())
            }, option: RouteOption().withSummary("列出中继任务").withTag("中继"))

            relayJobs.get("/stats", { ctx: Ctx =>
                let stats = m.relay.stats()
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putObj("stats", stats)
                    .toString())
            }, option: RouteOption().withSummary("中继任务统计").withTag("中继"))

            relayJobs.post("/", { ctx: Ctx =>
                if (!s.config.relayEnabled) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "relay disabled")
                        .toString())
                    return
                }

                let sourceDevice = ctx.formValue("sourceDevice") ?? "unknown"
                let targetDevice = ctx.formValue("targetDevice") ?? ""
                let targetPath = ctx.formValue("targetPath") ?? "/"

                if (targetDevice.size == 0) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "targetDevice 不能为空")
                        .toString())
                    return
                }

                match (ctx.formFile("file")) {
                    case Some(file) =>
                        let inputName = ctx.formValue("fileName") ?? ""
                        let fileName = if (inputName.size > 0) { inputName } else { "payload.bin" }
                        try {
                            let job = m.relay.create(sourceDevice, targetDevice, targetPath, fileName, file.data)
                            ctx.status(200).json(JsonObject()
                                .putBool("success", true)
                                .putObj("job", job.toJson())
                                .toString())
                        } catch (e: Exception) {
                            ctx.status(400).json(JsonObject()
                                .putBool("success", false)
                                .put("error", e.message)
                                .toString())
                        }
                    case None =>
                        ctx.status(400).json(JsonObject()
                            .putBool("success", false)
                            .put("error", "未收到文件，请使用字段名 file")
                            .toString())
                }
            }, option: RouteOption().withSummary("创建中继任务").withTag("中继"))

            relayJobs.get("/:id/cache", { ctx: Ctx =>
                let id = ctx.params("id")
                match (m.relay.cacheDescriptor(id)) {
                    case Some((cachePath, fileName)) =>
                        let _ = ctx.download(cachePath, filename: fileName)
                    case None =>
                        ctx.status(404).json(JsonObject()
                            .putBool("success", false)
                            .put("error", "cache file unavailable")
                            .toString())
                }
            }, option: RouteOption().withSummary("下载中继缓存文件").withTag("中继"))

            relayJobs.get("/:id", { ctx: Ctx =>
                let id = ctx.params("id")
                match (m.relay.get(id)) {
                    case Some(job) => ctx.json(JsonObject().putBool("success", true).putObj("job", job.toJson()).toString())
                    case None => ctx.status(404).json(JsonObject().putBool("success", false).put("error", "任务不存在").toString())
                }
            }, option: RouteOption().withSummary("查询中继任务").withTag("中继"))

            relayJobs.post("/:id/restore", { ctx: Ctx =>
                let id = ctx.params("id")
                let body = ctx.bodyString()
                let targetDevice = parseJsonString(body, "targetDevice") ?? ""
                let targetPath = parseJsonString(body, "targetPath") ?? "/"
                if (targetDevice.size == 0) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "targetDevice 不能为空")
                        .toString())
                    return
                }

                try {
                    let restored = m.relay.restore(id, targetDevice, targetPath)
                    match (m.relay.get(id)) {
                        case Some(job) =>
                            ctx.status(if (restored) { 200 } else { 400 }).json(JsonObject()
                                .putBool("success", restored)
                                .putObj("job", job.toJson())
                                .put("message", job.message)
                                .toString())
                        case None =>
                            ctx.status(404).json(JsonObject()
                                .putBool("success", false)
                                .put("error", "任务不存在")
                                .toString())
                    }
                } catch (e: Exception) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", e.message)
                        .toString())
                }
            }, option: RouteOption().withSummary("回流中继缓存文件").withTag("中继"))

            relayJobs.post("/:id/retry", { ctx: Ctx =>
                let id = ctx.params("id")
                match (m.relay.retry(id)) {
                    case Some(job) => ctx.json(JsonObject().putBool("success", true).putObj("job", job.toJson()).toString())
                    case None => ctx.status(404).json(JsonObject().putBool("success", false).put("error", "任务不存在").toString())
                }
            }, option: RouteOption().withSummary("重试中继任务").withTag("中继"))

            relayJobs.post("/:id/cancel", { ctx: Ctx =>
                let id = ctx.params("id")
                let ok = m.relay.cancel(id)
                ctx.status(if (ok) { 200 } else { 404 }).json(JsonObject()
                    .putBool("success", ok)
                    .put("message", if (ok) { "任务已取消" } else { "任务不存在" })
                    .toString())
            }, option: RouteOption().withSummary("取消中继任务").withTag("中继"))

            relayJobs.post("/batch-retry", { ctx: Ctx =>
                let body = ctx.bodyString()
                let ids = parseJsonStringArray(body, "ids")
                var updated: Int64 = 0
                let arr = JsonArray()
                for (id in ids) {
                    match (m.relay.retry(id)) {
                        case Some(job) =>
                            updated += 1
                            arr.addObj(job.toJson())
                        case None => ()
                    }
                }
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putInt("updated", updated)
                    .putArr("jobs", arr)
                    .toString())
            }, option: RouteOption().withSummary("批量重试中继任务").withTag("中继"))

            relayJobs.post("/batch-cancel", { ctx: Ctx =>
                let body = ctx.bodyString()
                let ids = parseJsonStringArray(body, "ids")
                var updated: Int64 = 0
                let arr = JsonArray()
                for (id in ids) {
                    if (m.relay.cancel(id)) {
                        updated += 1
                        arr.addStr(id)
                    }
                }
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putInt("updated", updated)
                    .putArr("ids", arr)
                    .toString())
            }, option: RouteOption().withSummary("批量取消中继任务").withTag("中继"))

            relayJobs.post("/cleanup", { ctx: Ctx =>
                let body = ctx.bodyString()
                let status = parseJsonString(body, "status") ?? ""
                let olderThanStr = parseJsonString(body, "olderThan") ?? "0"
                let olderThanHoursStr = parseJsonString(body, "olderThanHours") ?? "0"
                var olderThan: Int64 = 0
                try { olderThan = Int64.parse(olderThanStr) } catch (_: Exception) {}

                if (olderThan <= 0) {
                    var olderThanHours: Int64 = 0
                    try { olderThanHours = Int64.parse(olderThanHoursStr) } catch (_: Exception) {}
                    if (olderThanHours > 0) {
                        olderThan = currentTimestamp() - olderThanHours * 3600
                    }
                }

                let removed = m.relay.cleanup(status, olderThan)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putInt("removed", removed)
                    .put("status", status)
                    .putInt("olderThan", olderThan)
                    .toString())
            }, option: RouteOption().withSummary("清理中继任务").withTag("中继"))
        }

        if (s.profile.supportsWhitelist) {
            let whitelist = api.group("/whitelist")

            whitelist.get("/rules", { ctx: Ctx =>
                let target = ctx.queryDefault("targetDevice", "")
                let rules = m.whitelist.list(target)
                let arr = JsonArray()
                for (rule in rules) {
                    arr.addObj(rule.toJson())
                }
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putArr("rules", arr)
                    .toString())
            }, option: RouteOption().withSummary("获取白名单规则").withTag("白名单"))

            whitelist.post("/rules", { ctx: Ctx =>
                let body = ctx.bodyString()
                let source = parseJsonString(body, "sourceDevice") ?? "*"
                let target = parseJsonString(body, "targetDevice") ?? ""
                let enabled = (parseJsonString(body, "enabled") ?? "true") == "true"
                if (target.size == 0) {
                    ctx.status(400).json(JsonObject().putBool("success", false).put("error", "targetDevice 不能为空").toString())
                    return
                }
                try {
                    let rule = m.whitelist.upsert(source, target, enabled)
                    ctx.json(JsonObject()
                        .putBool("success", true)
                        .putObj("rule", rule.toJson())
                        .toString())
                } catch (e: Exception) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", e.message)
                        .toString())
                }
            }, option: RouteOption().withSummary("新增或更新白名单").withTag("白名单"))

            whitelist.post("/rules/toggle", { ctx: Ctx =>
                let body = ctx.bodyString()
                let source = parseJsonString(body, "sourceDevice") ?? "*"
                let target = parseJsonString(body, "targetDevice") ?? ""
                let enabled = (parseJsonString(body, "enabled") ?? "true") == "true"
                if (target.size == 0) {
                    ctx.status(400).json(JsonObject().putBool("success", false).put("error", "targetDevice 不能为空").toString())
                    return
                }

                match (m.whitelist.setEnabled(source, target, enabled)) {
                    case Some(rule) =>
                        ctx.json(JsonObject()
                            .putBool("success", true)
                            .putObj("rule", rule.toJson())
                            .toString())
                    case None =>
                        ctx.status(404).json(JsonObject()
                            .putBool("success", false)
                            .put("error", "规则不存在")
                            .toString())
                }
            }, option: RouteOption().withSummary("启用或禁用白名单规则").withTag("白名单"))

            whitelist.delete("/rules", { ctx: Ctx =>
                let body = ctx.bodyString()
                let source = parseJsonString(body, "sourceDevice") ?? "*"
                let target = parseJsonString(body, "targetDevice") ?? ""
                if (target.size == 0) {
                    ctx.status(400).json(JsonObject().putBool("success", false).put("error", "targetDevice 不能为空").toString())
                    return
                }

                let removed = m.whitelist.remove(source, target)
                ctx.status(if (removed) { 200 } else { 404 }).json(JsonObject()
                    .putBool("success", removed)
                    .put("message", if (removed) { "规则已删除" } else { "规则不存在" })
                    .toString())
            }, option: RouteOption().withSummary("删除白名单规则").withTag("白名单"))
        }

        if (s.profile.supportsFavorites) {
            let favorites = api.group("/favorites")

            favorites.get("/", { ctx: Ctx =>
                let entries = m.favorites.list()
                let arr = JsonArray()
                for (entry in entries) {
                    arr.addObj(entry.toJson())
                }
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .put("mode", m.favorites.mode())
                    .putArr("favorites", arr)
                    .toString())
            }, option: RouteOption().withSummary("获取收藏路径").withTag("收藏"))

            favorites.put("/", { ctx: Ctx =>
                let body = ctx.bodyString()
                let entries = parseFavoriteEntries(body)
                let updated = m.favorites.replace(entries)
                let arr = JsonArray()
                for (entry in updated) {
                    arr.addObj(entry.toJson())
                }
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .put("mode", m.favorites.mode())
                    .putArr("favorites", arr)
                    .toString())
            }, option: RouteOption().withSummary("替换收藏路径").withTag("收藏"))
        }

        // 文件系统相关
        let fs = api.group("/fs")

        fs.get("/list", { ctx: Ctx =>
            let deviceId = ctx.queryDefault("device", "")
            var path = ctx.queryDefault("path", "/")
            let limitStr = ctx.queryDefault("limit", "2000")
            let offsetStr = ctx.queryDefault("offset", "0")
            if (deviceId.size == 0) {
                ctx.status(400).json(JsonObject()
                    .put("error", "参数错误: device 参数不能为空")
                    .put("code", "INVALID_DEVICE")
                    .toString())
                return
            }
            if (path.size == 0) { path = "/" }
            let cacheKey = "${deviceId}|${path}"
            var cachedList: ?ArrayList<FileEntry> = None
            synchronized(listDirCacheMutex) {
                if (let Some(entry) <- listDirCache.get(cacheKey)) {
                    if (currentTimestamp() - entry.cachedAt < listDirCacheTTLSeconds) {
                        cachedList = Some(entry.entries)
                    }
                }
            }
            var filteredEntries: ArrayList<FileEntry> = ArrayList()
            try {
                if (let Some(list) <- cachedList) {
                    filteredEntries = list
                } else {
                    let entries = m.files.listDir(deviceId, path)
                    filteredEntries = filterVisibleEntries(entries, path)
                    synchronized(listDirCacheMutex) {
                        listDirCache.add(cacheKey, ListDirCacheEntry(filteredEntries, currentTimestamp()))
                    }
                }
            } catch (e: Exception) {
                ctx.status(403).json(JsonObject()
                    .put("error", e.message)
                    .put("code", "REMOTE_DEVICE_POLICY")
                    .toString())
                return
            }

            var limit: Int64 = 2000
            var offset: Int64 = 0
            try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
            try { offset = Int64.parse(offsetStr) } catch (_: Exception) {}
            if (limit <= 0) { limit = 2000 }
            if (limit > 5000) { limit = 5000 }
            if (offset < 0) { offset = 0 }

            let total = filteredEntries.size
            if (offset > total) { offset = total }
            var end = offset + limit
            if (end > total) { end = total }

            let arr = JsonArray()
            var i = offset
            while (i < end) {
                arr.addObj(filteredEntries[i].toJson())
                i += 1
            }

            let truncated = end < total
            let nextOffset = if (truncated) { end } else { -1 }

            ctx.json(JsonObject()
                .put("path", path)
                .putArr("files", arr)
                .put("device", deviceId)
                .putBool("success", true)
                .putInt("total", total)
                .putInt("limit", limit)
                .putInt("offset", offset)
                .putInt("nextOffset", nextOffset)
                .putBool("truncated", truncated)
                .toString())
        }, option: RouteOption()
            .withSummary("列出目录内容")
            .withTag("文件系统")
            .withParam(ParamSpec("device", Query, description: "设备ID", required: true))
            .withParam(ParamSpec("path", Query, description: "目录路径"))
        )

        fs.get("/info", { ctx: Ctx =>
            let deviceId = ctx.queryDefault("device", "")
            let path = ctx.queryDefault("path", "")
            try {
                match (m.files.getInfo(deviceId, path)) {
                    case Some(info) => ctx.json(info.toJson().toString())
                    case None => ctx.status(500).json(
                        JsonObject().put("error", "获取文件信息失败").toString())
                }
            } catch (e: Exception) {
                ctx.status(403).json(JsonObject()
                    .put("error", e.message)
                    .put("code", "REMOTE_DEVICE_POLICY")
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("获取文件信息")
            .withTag("文件系统")
            .withParam(ParamSpec("device", Query, description: "设备ID", required: true))
            .withParam(ParamSpec("path", Query, description: "文件路径", required: true))
        )

        fs.get("/summary", { ctx: Ctx =>
            let deviceId = ctx.queryDefault("device", "")
            let path = ctx.queryDefault("path", "")
            if (deviceId.size == 0 || path.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "device 与 path 不能为空")
                    .toString())
                return
            }
            try {
                ctx.json(m.files.summary(deviceId, path).toString())
            } catch (e: Exception) {
                ctx.status(500).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "summary failed: ${e.message}")
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("获取源项摘要")
            .withTag("文件系统")
            .withParam(ParamSpec("device", Query, description: "设备ID", required: true))
            .withParam(ParamSpec("path", Query, description: "文件或目录路径", required: true))
        )

        fs.get("/preview", { ctx: Ctx =>
            let deviceId = ctx.queryDefault("device", "")
            let path = ctx.queryDefault("path", "")
            if (deviceId.size == 0 || path.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "device 与 path 不能为空")
                    .toString())
                return
            }

            try {
                match (m.files.getInfo(deviceId, path)) {
                    case Some(info) =>
                        ctx.json(buildFilePreviewPayload(m, deviceId, path, info).toString())
                    case None =>
                        ctx.status(404).json(JsonObject()
                            .putBool("success", false)
                            .put("error", "文件不存在或不可读取")
                            .toString())
                }
            } catch (e: Exception) {
                ctx.status(500).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "preview failed: ${e.message}")
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("获取文件预览")
            .withTag("文件系统")
            .withParam(ParamSpec("device", Query, description: "设备ID", required: true))
            .withParam(ParamSpec("path", Query, description: "文件路径", required: true))
        )

        fs.get("/stream", { ctx: Ctx =>
            let deviceId = ctx.queryDefault("device", "")
            let path = ctx.queryDefault("path", "")
            if (deviceId.size == 0 || path.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "device 与 path 不能为空")
                    .toString())
                return
            }
            serveInlineResponse(ctx, s, m, deviceId, path)
        }, option: RouteOption()
            .withSummary("内联流式访问文件")
            .withTag("文件系统")
            .withParam(ParamSpec("device", Query, description: "设备ID", required: true))
            .withParam(ParamSpec("path", Query, description: "文件路径", required: true))
        )

        fs.post("/dirs", { ctx: Ctx =>
            let body = ctx.bodyString()
            let deviceId = parseJsonString(body, "device") ?? ""
            let path = parseJsonString(body, "path") ?? ""
            if (deviceId.size == 0 || path.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "device 与 path 不能为空")
                    .toString())
                return
            }
            try {
                let ok = m.files.createDir(deviceId, path)
                ctx.status(if (ok) { 200 } else { 400 }).json(JsonObject()
                    .putBool("success", ok)
                    .put("device", deviceId)
                    .put("path", path)
                    .toString())
            } catch (e: Exception) {
                ctx.status(403).json(JsonObject()
                    .putBool("success", false)
                    .put("error", e.message)
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("创建目录")
            .withTag("文件系统"))

        fs.get("/download", { ctx: Ctx =>
            let fileId = ctx.queryDefault("fileId", "")
            if (fileId.size > 0) {
                match (decodeChunkFileId(fileId)) {
                    case Some((deviceId, path)) =>
                        serveDownloadResponse(ctx, s, m, deviceId, path)
                    case None =>
                        ctx.status(400).json(JsonObject()
                            .put("error", "fileId 格式错误")
                            .toString())
                }
                return
            }

            let deviceIdRaw = ctx.queryDefault("device", "")
            let path = ctx.queryDefault("path", "")
            let deviceId = if (deviceIdRaw.size > 0) { deviceIdRaw } else { "local" }
            if (path.size == 0) {
                ctx.status(400).json(JsonObject()
                    .put("error", "参数 path 不能为空")
                    .toString())
                return
            }
            serveDownloadResponse(ctx, s, m, deviceId, path)
        }, option: RouteOption()
            .withSummary("旧版下载接口兼容层")
            .withTag("文件系统")
            .asHidden()
        )

        fs.post("/upload", { ctx: Ctx =>
            let targetDevice = firstNonEmpty([
                ctx.formValue("targetDevice") ?? "",
                ctx.formValue("device") ?? "",
                ctx.formValue("deviceId") ?? ""
            ])
            let targetPath = firstNonEmpty([
                ctx.formValue("targetPath") ?? "",
                ctx.formValue("path") ?? "",
                "/"
            ])
            let overrideFileName = ctx.formValue("fileName") ?? ""

            if (targetDevice.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "targetDevice 不能为空")
                    .toString())
                return
            }

            let uploads = collectLegacyUploadFiles(ctx)
            if (uploads.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "未收到文件，请使用字段名 file/files/chunk")
                    .toString())
                return
            }

            let arr = JsonArray()
            var successCount: Int64 = 0
            for (upload in uploads) {
                let effectiveName = if (overrideFileName.size > 0 && uploads.size == 1) {
                    overrideFileName
                } else if (upload.filename.size > 0) {
                    upload.filename
                } else {
                    "upload.bin"
                }
                let session = m.chunks.createSession(
                    "legacy-upload",
                    targetDevice,
                    targetPath,
                    effectiveName,
                    Int64(upload.data.size),
                    Int64(upload.data.size)
                )
                let chunkResult = m.chunks.writeChunk(session.id, 0, upload.data)
                if (!chunkResult.success) {
                    arr.addObj(JsonObject()
                        .putBool("success", false)
                        .put("fileName", effectiveName)
                        .put("message", chunkResult.message))
                    continue
                }
                let complete = m.chunks.complete(session.id)
                arr.addObj(complete.toJson())
                if (complete.success) {
                    successCount += 1
                }
            }

            let allSucceeded = successCount == uploads.size
            ctx.status(if (allSucceeded) { 200 } else { 207 }).json(JsonObject()
                .putBool("success", successCount > 0)
                .putInt("uploaded", successCount)
                .putInt("total", uploads.size)
                .putArr("files", arr)
                .put("message", "legacy upload compatibility path")
                .toString())
        }, option: RouteOption()
            .withSummary("旧版上传接口兼容层")
            .withTag("文件系统")
            .asHidden()
        )

        fs.get("/encoding", { ctx: Ctx =>
            let path = ctx.queryDefault("path", "")
            if (path.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "参数 path 不能为空")
                    .toString())
                return
            }

            let encoding = fileHelper.detectEncoding(path)
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("path", path)
                .put("encoding", encoding)
                .toString())
        }, option: RouteOption()
            .withSummary("检测文件编码")
            .withTag("文件系统")
        )

        fs.get("/line", { ctx: Ctx =>
            let path = ctx.queryDefault("path", "")
            let lineStr = ctx.queryDefault("line", "1")
            var lineNo: Int64 = 1
            try { lineNo = Int64.parse(lineStr) } catch (_: Exception) {}

            if (path.size == 0 || lineNo <= 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "参数 path 和 line 必须有效")
                    .toString())
                return
            }

            match (fileHelper.readLine(path, lineNo)) {
                case Some(line) =>
                    ctx.json(JsonObject()
                        .putBool("success", true)
                        .put("path", path)
                        .putInt("line", lineNo)
                        .put("content", line)
                        .toString())
                case None =>
                    ctx.status(404).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "未找到对应行或文件不可读")
                        .toString())
            }
        }, option: RouteOption()
            .withSummary("读取指定行")
            .withTag("文件系统")
        )

        // ── 分块传输API（替代旧 fs upload/download）──
        let chunk = api.group("/transfer/chunk")

        chunk.post("/session", { ctx: Ctx =>
            let body = ctx.bodyString()
            let sourceDevice = parseJsonString(body, "sourceDevice") ?? "local"
            let targetDevice = parseJsonString(body, "targetDevice") ?? ""
            let targetPath = parseJsonString(body, "targetPath") ?? "/"
            let fileName = parseJsonString(body, "fileName") ?? "upload.bin"
            let fileSizeStr = parseJsonString(body, "fileSize") ?? "0"
            let chunkSizeStr = parseJsonString(body, "chunkSize") ?? "2097152"
            var fileSize: Int64 = 0
            var chunkSize: Int64 = 2 * 1024 * 1024
            try { fileSize = Int64.parse(fileSizeStr) } catch (_: Exception) {}
            try { chunkSize = Int64.parse(chunkSizeStr) } catch (_: Exception) {}

            if (targetDevice.size == 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "targetDevice 不能为空")
                    .toString())
                return
            }

            let session = m.chunks.createSession(sourceDevice, targetDevice, targetPath, fileName, fileSize, chunkSize)
            ctx.json(JsonObject()
                .putBool("success", true)
                .putObj("session", session.toJson(0))
                .toString())
        }, option: RouteOption()
            .withSummary("创建分块上传会话")
            .withTag("分块传输"))

        chunk.put("/session/:id/chunks/:index", { ctx: Ctx =>
            let sessionId = ctx.params("id")
            let indexStr = ctx.params("index")
            var chunkIndex: Int64 = 0
            try { chunkIndex = Int64.parse(indexStr) } catch (_: Exception) { chunkIndex = -1 }

            if (chunkIndex < 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "invalid chunk index")
                    .toString())
                return
            }

            match (ctx.formFile("chunk")) {
                case Some(file) =>
                    let result = m.chunks.writeChunk(sessionId, chunkIndex, file.data)
                    ctx.status(if (result.success) { 200 } else { 400 }).json(result.toJson().toString())
                case None =>
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "未收到 chunk 文件，请使用字段名 chunk")
                        .toString())
            }
        }, option: RouteOption()
            .withSummary("上传分块")
            .withTag("分块传输"))

        chunk.post("/session/:id/chunks/:index", { ctx: Ctx =>
            let sessionId = ctx.params("id")
            let indexStr = ctx.params("index")
            var chunkIndex: Int64 = 0
            try { chunkIndex = Int64.parse(indexStr) } catch (_: Exception) { chunkIndex = -1 }

            if (chunkIndex < 0) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", "invalid chunk index")
                    .toString())
                return
            }

            match (ctx.formFile("chunk")) {
                case Some(file) =>
                    let result = m.chunks.writeChunk(sessionId, chunkIndex, file.data)
                    ctx.status(if (result.success) { 200 } else { 400 }).json(result.toJson().toString())
                case None =>
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "未收到 chunk 文件，请使用字段名 chunk")
                        .toString())
            }
        }, option: RouteOption()
            .withSummary("上传分块（POST兼容）")
            .withTag("分块传输"))

        chunk.get("/session/:id/manifest", { ctx: Ctx =>
            let sessionId = ctx.params("id")
            let manifest = m.chunks.manifest(sessionId)
            if ((parseJsonString(manifest.toString(), "success") ?? "false") == "true") {
                ctx.json(manifest.toString())
            } else {
                ctx.status(404).json(manifest.toString())
            }
        }, option: RouteOption()
            .withSummary("查询分块会话状态")
            .withTag("分块传输"))

        chunk.post("/session/:id/complete", { ctx: Ctx =>
            let sessionId = ctx.params("id")
            let result = m.chunks.complete(sessionId)
            ctx.status(if (result.success) { 200 } else { 400 }).json(result.toJson().toString())
        }, option: RouteOption()
            .withSummary("完成分块上传并合并")
            .withTag("分块传输"))

        chunk.get("/files/:fileId", { ctx: Ctx =>
            let fileId = ctx.params("fileId")
            match (decodeChunkFileId(fileId)) {
                case Some((deviceId, path)) =>
                    serveDownloadResponse(ctx, s, m, deviceId, path)
                case None =>
                    ctx.status(400).json(JsonObject().put("error", "fileId 格式错误").toString())
            }
        }, option: RouteOption()
            .withSummary("下载文件（支持Range）")
            .withTag("分块传输"))

        // 传输任务相关
        let tasksGroup = api.group("/tasks")

        tasksGroup.get("/", { ctx: Ctx =>
            let taskList = m.tasks.listTasks()
            let arr = JsonArray()
            for (t in taskList) {
                arr.addObj(t.toJson())
            }
            ctx.json(arr.toString())
        }, option: RouteOption()
            .withSummary("列出所有任务")
            .withTag("传输任务")
        )

        tasksGroup.get("/:id", { ctx: Ctx =>
            let id = ctx.params("id")
            match (m.tasks.getTask(id)) {
                case Some(task) => ctx.json(task.toJson().toString())
                case None => ctx.status(404).json(
                    JsonObject().put("error", "任务不存在").toString())
            }
        }, option: RouteOption()
            .withSummary("获取任务信息")
            .withTag("传输任务")
            .withParam(ParamSpec("id", Path, description: "任务ID", required: true))
        )

        tasksGroup.post("/", { ctx: Ctx =>
            let body = ctx.bodyString()
            let sourceDevice = parseJsonString(body, "sourceDevice") ?? ""
            let targetDevice = parseJsonString(body, "targetDevice") ?? ""
            let filePath = parseJsonString(body, "filePath") ?? ""
            let targetPath = parseJsonString(body, "targetPath") ?? ""

            if (sourceDevice.size == 0) {
                ctx.status(400).json(JsonObject()
                    .put("error", "源设备ID不能为空")
                    .put("code", "MISSING_SOURCE_DEVICE")
                    .toString())
                return
            }
            if (targetDevice.size == 0) {
                ctx.status(400).json(JsonObject()
                    .put("error", "目标设备ID不能为空")
                    .put("code", "MISSING_TARGET_DEVICE")
                    .toString())
                return
            }
            if (filePath.size == 0) {
                ctx.status(400).json(JsonObject()
                    .put("error", "文件路径不能为空")
                    .put("code", "MISSING_FILE_PATH")
                    .toString())
                return
            }

            match (m.devices.getDevice(sourceDevice)) {
                case None =>
                    ctx.status(404).json(JsonObject()
                        .put("error", "源设备不存在: ${sourceDevice}")
                        .put("code", "SOURCE_DEVICE_NOT_FOUND")
                        .toString())
                    return
                case _ => ()
            }

            match (m.devices.getDevice(targetDevice)) {
                case None =>
                    ctx.status(404).json(JsonObject()
                        .put("error", "目标设备不存在: ${targetDevice}")
                        .put("code", "TARGET_DEVICE_NOT_FOUND")
                        .toString())
                    return
                case _ => ()
            }

            try {
                let task = m.tasks.createTask(sourceDevice, targetDevice, filePath, targetPath)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putObj("task", task.toJson())
                    .put("message", "传输任务创建成功")
                    .toString())
            } catch (e: Exception) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", e.message)
                    .put("code", "TRANSFER_POLICY_REJECTED")
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("创建传输任务")
            .withTag("传输任务")
        )

        tasksGroup.post("/multi-thread", { ctx: Ctx =>
            let body = ctx.bodyString()
            let sourceDevice = parseJsonString(body, "sourceDevice") ?? ""
            let targetDevice = parseJsonString(body, "targetDevice") ?? ""
            let filePath = parseJsonString(body, "filePath") ?? ""
            let targetPath = parseJsonString(body, "targetPath") ?? ""
            let threadsStr = parseJsonString(body, "threads") ?? "4"
            var threads: Int64 = 4
            try { threads = Int64.parse(threadsStr) } catch (_: Exception) {}
            if (threads <= 0) { threads = 4 }
            if (threads > 16) { threads = 16 }

            if (sourceDevice.size == 0 || targetDevice.size == 0 || filePath.size == 0) {
                ctx.status(400).json(JsonObject()
                    .put("error", "源设备、目标设备和文件路径不能为空")
                    .put("code", "MISSING_REQUIRED_FIELDS")
                    .toString())
                return
            }

            try {
                let task = m.tasks.createTask(sourceDevice, targetDevice, filePath, targetPath)
                task.threads = threads

                ctx.json(JsonObject()
                    .putBool("success", true)
                    .putObj("task", task.toJson())
                    .put("message", "多线程传输任务创建成功")
                    .putInt("threads", threads)
                    .toString())
            } catch (e: Exception) {
                ctx.status(400).json(JsonObject()
                    .putBool("success", false)
                    .put("error", e.message)
                    .put("code", "TRANSFER_POLICY_REJECTED")
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("创建多线程传输任务")
            .withTag("传输任务")
        )

        tasksGroup.delete("/:id", { ctx: Ctx =>
            let id = ctx.params("id")
            let success = m.tasks.cancel(id)
            if (success) {
                ctx.json(JsonObject().putBool("success", true).toString())
            } else {
                ctx.status(500).json(JsonObject()
                    .put("error", "取消任务失败")
                    .toString())
            }
        }, option: RouteOption()
            .withSummary("取消传输任务")
            .withTag("传输任务")
            .withParam(ParamSpec("id", Path, description: "任务ID", required: true))
        )

        // ── P2P / Security API ──
        if (s.profile.supportsPeerTransfer) {
            let peer = api.group("/peer")

            peer.get("/security", { ctx: Ctx =>
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .put("mode", m.peers.securityMode())
                    .toString())
            }, option: RouteOption()
                .withSummary("获取P2P安全模式")
                .withTag("P2P")
            )

            peer.post("/security", { ctx: Ctx =>
                let body = ctx.bodyString()
                let mode = parseJsonString(body, "mode") ?? "plain"
                let current = m.peers.updateSecurityMode(mode)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .put("mode", current)
                    .put("message", "安全模式已更新")
                    .toString())
            }, option: RouteOption()
                .withSummary("更新P2P安全模式")
                .withTag("P2P")
            )

            peer.post("/handshake", { ctx: Ctx =>
                let body = ctx.bodyString()
                let peerId = parseJsonString(body, "peerId") ?? "anonymous"
                let token = m.peers.beginHandshake(peerId)
                ctx.json(JsonObject()
                    .putBool("success", true)
                    .put("peerId", peerId)
                    .put("token", token)
                    .toString())
            }, option: RouteOption()
                .withSummary("创建P2P握手令牌")
                .withTag("P2P")
            )

            peer.post("/upload", { ctx: Ctx =>
                let peerId = ctx.formValue("peerId") ?? "anonymous"
                let token = ctx.formValue("token") ?? ""
                let targetPath = ctx.formValue("targetPath") ?? ""
                if (targetPath.size == 0) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "targetPath 不能为空")
                        .toString())
                    return
                }

                match (ctx.formFile("file")) {
                    case Some(file) =>
                        let result = m.peers.upload(targetPath, peerId, token, file.data)
                        ctx.status(if (result.success) { 200 } else { 400 }).json(result.toJson().toString())
                    case None =>
                        ctx.status(400).json(JsonObject()
                            .putBool("success", false)
                            .put("error", "未收到文件，请使用字段名 file")
                            .toString())
                }
            }, option: RouteOption()
                .withSummary("接收P2P上传")
                .withTag("P2P")
            )

            peer.post("/pull", { ctx: Ctx =>
                let body = ctx.bodyString()
                let sourcePath = parseJsonString(body, "sourcePath") ?? ""
                let targetPath = parseJsonString(body, "targetPath") ?? ""
                let peerId = parseJsonString(body, "peerId") ?? "anonymous"
                let token = parseJsonString(body, "token") ?? ""

                if (sourcePath.size == 0) {
                    ctx.status(400).json(JsonObject()
                        .putBool("success", false)
                        .put("error", "sourcePath 不能为空")
                        .toString())
                    return
                }

                if (targetPath.size > 0) {
                    let result = m.peers.localPull(sourcePath, targetPath)
                    ctx.status(if (result.success) { 200 } else { 400 }).json(result.toJson().toString())
                    return
                }

                let output = m.peers.pull(sourcePath, peerId, token)
                if (!output.result.success) {
                    ctx.status(400).json(output.result.toJson().toString())
                    return
                }

                let _ = ctx.setHeader("Content-Type", "application/octet-stream")
                let _ = ctx.setHeader("Content-Length", "${output.data.size}")
                ctx.send(output.data)
            }, option: RouteOption()
                .withSummary("发起P2P拉取")
                .withTag("P2P")
            )
        }

        // ── Dashboard ──
        app.get("/dashboard", { ctx: Ctx =>
            try {
                let html = renderTemplate("./web/views/dashboard.html", [("Title", "SoonLink设备控制中心")])
                ctx.html(html)
            } catch (_: Exception) {
                ctx.html("<h1>SoonLink设备控制中心</h1>")
            }
        }, option: RouteOption().withTag("页面").asHidden())

        // ── 媒体控制API ──
        let media = api.group("/media")

        media.get("/status", { ctx: Ctx =>
            ctx.json(m.media.status().toString())
        }, option: RouteOption()
            .withSummary("获取媒体播放状态")
            .withTag("媒体控制")
        )

        media.post("/play", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "播放状态已更新")
                .putObj("status", m.media.play())
                .toString())
        }, option: RouteOption().withSummary("播放").withTag("媒体控制"))

        media.post("/pause", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "已暂停")
                .putObj("status", m.media.pause())
                .toString())
        }, option: RouteOption().withSummary("暂停").withTag("媒体控制"))

        media.post("/stop", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "已停止")
                .putObj("status", m.media.stop())
                .toString())
        }, option: RouteOption().withSummary("停止").withTag("媒体控制"))

        media.post("/next", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "切换到下一曲")
                .putObj("status", m.media.next())
                .toString())
        }, option: RouteOption().withSummary("下一曲").withTag("媒体控制"))

        media.post("/previous", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "切换到上一曲")
                .putObj("status", m.media.previous())
                .toString())
        }, option: RouteOption().withSummary("上一曲").withTag("媒体控制"))

        media.get("/volume", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putInt("volume", m.media.volume())
                .putBool("isMuted", m.media.isMuted())
                .toString())
        }, option: RouteOption().withSummary("获取音量").withTag("媒体控制"))

        media.post("/volume", { ctx: Ctx =>
            let body = ctx.bodyString()
            let volStr = parseJsonString(body, "volume") ?? "50"
            var vol: Int64 = 50
            try { vol = Int64.parse(volStr) } catch (_: Exception) {}
            let status = m.media.setVolume(vol)
            ctx.json(JsonObject()
                .putBool("success", true)
                .putInt("volume", m.media.volume())
                .put("message", "音量已设置")
                .putObj("status", status)
                .toString())
        }, option: RouteOption().withSummary("设置音量").withTag("媒体控制"))

        media.post("/mute", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "已静音")
                .putObj("status", m.media.mute())
                .toString())
        }, option: RouteOption().withSummary("静音").withTag("媒体控制"))

        media.post("/unmute", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "已取消静音")
                .putObj("status", m.media.unmute())
                .toString())
        }, option: RouteOption().withSummary("取消静音").withTag("媒体控制"))

        // ── 系统监控API ──
        let monitor = api.group("/monitor")

        monitor.get("/system", { ctx: Ctx =>
            ctx.json(m.monitor.system().toString())
        }, option: RouteOption()
            .withSummary("获取完整系统信息")
            .withTag("系统监控")
        )

        monitor.get("/cpu", { ctx: Ctx =>
            ctx.json(m.monitor.cpu().toString())
        }, option: RouteOption().withSummary("获取CPU信息").withTag("系统监控"))

        monitor.get("/memory", { ctx: Ctx =>
            ctx.json(m.monitor.memory().toString())
        }, option: RouteOption().withSummary("获取内存信息").withTag("系统监控"))

        monitor.get("/disk", { ctx: Ctx =>
            let path = ctx.queryDefault("path", "/")
            ctx.json(m.monitor.disk(path).toString())
        }, option: RouteOption()
            .withSummary("获取磁盘信息")
            .withTag("系统监控")
            .withParam(ParamSpec("path", Query, description: "磁盘路径"))
        )

        monitor.get("/temperature", { ctx: Ctx =>
            ctx.json(m.monitor.temperature().toString())
        }, option: RouteOption().withSummary("获取温度信息").withTag("系统监控"))

        monitor.get("/uptime", { ctx: Ctx =>
            ctx.json(m.monitor.uptime().toString())
        }, option: RouteOption().withSummary("获取运行时间").withTag("系统监控"))

        monitor.get("/network", { ctx: Ctx =>
            ctx.json(m.monitor.network().toString())
        }, option: RouteOption().withSummary("获取网络信息").withTag("系统监控"))

        // ── 日志API ──
        let logsGroup = api.group("/logs")

        logsGroup.get("/", { ctx: Ctx =>
            let limitStr = ctx.queryDefault("limit", "50")
            let levelStr = ctx.queryDefault("level", "")
            let category = ctx.queryDefault("category", "")
            var limit: Int64 = 50
            try { limit = Int64.parse(limitStr) } catch (_: Exception) {}
            if (limit <= 0) { limit = 50 }
            if (limit > 500) { limit = 500 }

            var logs: ArrayList<LogEntry> = ArrayList<LogEntry>()
            if (levelStr.size > 0) {
                let level = logLevelFromString(levelStr)
                logs = m.logs.listByLevel(level, limit)
            } else if (category.size > 0) {
                logs = m.logs.listByCategory(category, limit)
            } else {
                logs = m.logs.list(limit)
            }

            let arr = JsonArray()
            for (log in logs) {
                arr.addObj(log.toJson())
            }
            ctx.json(JsonObject()
                .putArr("logs", arr)
                .putInt("total", logs.size)
                .putInt("limit", limit)
                .toString())
        }, option: RouteOption()
            .withSummary("获取日志列表")
            .withTag("日志")
            .withParam(ParamSpec("limit", Query, description: "返回数量限制"))
            .withParam(ParamSpec("level", Query, description: "日志级别过滤"))
            .withParam(ParamSpec("category", Query, description: "分类过滤"))
        )

        logsGroup.get("/stats", { ctx: Ctx =>
            ctx.json(m.logs.stats().toString())
        }, option: RouteOption().withSummary("获取日志统计").withTag("日志"))

        logsGroup.delete("/", { ctx: Ctx =>
            m.logs.clear()
            s.logger.logInfo("admin", "日志已清空", "管理员执行了清空日志操作", "web/admin")
            ctx.json(JsonObject().putBool("success", true).put("message", "日志已清空").toString())
        }, option: RouteOption().withSummary("清空日志").withTag("日志"))

        logsGroup.post("/config", { ctx: Ctx =>
            let body = ctx.bodyString()
            let enabledStr = parseJsonString(body, "enabled")
            let showInUIStr = parseJsonString(body, "showInUI")

            if (let Some(v) <- enabledStr) {
                s.logger.setEnabled(v == "true")
            }
            if (let Some(v) <- showInUIStr) {
                s.logger.setShowInUI(v == "true")
            }

            ctx.json(JsonObject()
                .putBool("success", true)
                .put("message", "日志配置已更新")
                .putObj("config", JsonObject()
                    .putBool("enabled", s.logger.isEnabled())
                    .putBool("showInUI", s.logger.shouldShowInUI()))
                .toString())
        }, option: RouteOption().withSummary("更新日志配置").withTag("日志"))

        logsGroup.get("/config", { ctx: Ctx =>
            ctx.json(JsonObject()
                .putBool("enabled", s.logger.isEnabled())
                .putBool("showInUI", s.logger.shouldShowInUI())
                .toString())
        }, option: RouteOption().withSummary("获取日志配置").withTag("日志"))
    }
}

func buildSessionContextPayload(server: CoreServer, access: WebAccessContext): JsonObject {
    let auth = server.authProvider.descriptor()
    let authCaps = JsonArray()
    for (cap in auth.capabilities) {
        authCaps.addStr(cap)
    }

    JsonObject()
        .putBool("isLocalAdmin", access.isLocalAdmin)
        .put("accessMode", access.accessMode)
        .put("themeVariant", access.themeVariant)
        .putObj("product", productProfileToJson(server.profile))
        .putObj("auth", JsonObject()
            .put("policy", "local_trust")
            .put("provider", auth.provider)
            .put("edition", auth.edition)
            .putBool("supportsPassword", auth.supportsPassword)
            .putBool("passwordConfigured", auth.passwordConfigured)
            .putArr("capabilities", authCaps))
        .putObj("network", JsonObject()
            .put("clientIp", access.clientIP)
            .put("resolvedIp", access.resolvedIP)
            .putBool("trustedProxyHeaders", server.config.localAuthTrustProxyHeaders))
}

func productProfileToJson(profile: ProductProfile): JsonObject {
    JsonObject()
        .put("edition", profile.edition)
        .put("productName", profile.productName)
        .put("displayName", resolveRuntimeDisplayName(profile))
        .put("version", currentProductVersion())
        .putObj("capabilities", productCapabilitiesToJson(profile))
        .putArr("capabilityTags", productCapabilityTags(profile))
}

func appConfigToJson(config: AppConfig, profile: ProductProfile): JsonObject {
    let out = JsonObject()
    out.put("listenAddr", config.listenAddr)
    out.putInt("webPort", Int64(config.webPort))
    out.put("tempDir", config.tempDir)
    out.putInt("maxConnections", config.maxConnections)
    out.put("configFile", config.configFile)
    out.put("deviceRegistryFile", config.deviceRegistryFile)
    out.put("logDir", config.logDir)
    out.put("localRootDir", config.localRootDir)
    out.putBool("localAuthTrustProxyHeaders", config.localAuthTrustProxyHeaders)
    out.put("edition", profile.edition)
    out.put("productName", profile.productName)
    out.put("displayName", resolveRuntimeDisplayName(profile))
    out.put("version", currentProductVersion())
    out.putObj("capabilities", productCapabilitiesToJson(profile))
    if (profile.supportsPeerTransfer) {
        out.put("securityMode", config.securityMode)
    }
    if (profile.supportsActiveDiscovery) {
        out.putInt("discoveryUdpPort", config.discoveryUdpPort)
        out.putBool("enableMdns", config.enableMdns)
        out.putInt("discoveryHeartbeatSeconds", config.discoveryHeartbeatSeconds)
    }
    if (profile.supportsRelay) {
        out.putBool("relayEnabled", config.relayEnabled)
        out.put("relayCacheDir", config.relayCacheDir)
        out.putInt("relayRetentionHours", config.relayRetentionHours)
        out.put("relayLimitMode", config.relayLimitMode)
        out.putInt("relayLimitBytes", config.relayLimitBytes)
        out.putInt("relayLimitPercent", config.relayLimitPercent)
    }
    if (profile.supportsFavorites) {
        out.put("favoritesStoreMode", config.favoritesStoreMode)
        out.put("favoritesTomlFile", config.favoritesTomlFile)
    }
    if (profile.supportsWhitelist) {
        out.put("whitelistTomlFile", config.whitelistTomlFile)
    }
    out
}

func buildAdminSystemPayload(server: CoreServer, masters: MasterBundle): JsonObject {
    let system = masters.monitor.system()
    let disk = masters.monitor.disk(if (server.localRootDir.size > 0) { server.localRootDir } else { "/" })
    let network = masters.monitor.network()
    let logStats = masters.logs.stats()
    let devices = server.listDevices()

    var onlineDevices: Int64 = 0
    for (device in devices) {
        if (device.online) {
            onlineDevices += 1
        }
    }

    let cpuUsage = jsonObjectFloat(system, "cpuUsage")
    let memoryUsage = jsonObjectFloat(system, "memoryUsage")
    let diskUsage = jsonObjectFloat(disk, "usedPercent")
    let diskUsed = jsonObjectInt(disk, "used")
    let diskTotal = jsonObjectInt(disk, "total")
    let hostname = parseJsonString(system.toString(), "hostname") ?? "localhost"
    let primaryIp = parseJsonString(network.toString(), "primaryIp") ?? ""

    JsonObject()
        .putBool("success", true)
        .put("edition", server.profile.edition)
        .put("productName", server.profile.productName)
        .put("displayName", resolveRuntimeDisplayName(server.profile))
        .put("version", currentProductVersion())
        .putObj("capabilities", productCapabilitiesToJson(server.profile))
        .put("hostname", hostname)
        .put("primaryIp", primaryIp)
        .put("uptime", formatDurationHuman(server.uptimeSeconds()))
        .putInt("uptimeSeconds", server.uptimeSeconds())
        .put("cpu", "${roundPercent(cpuUsage)}%")
        .putFloat("cpuUsage", cpuUsage)
        .put("memory", "${roundPercent(memoryUsage)}%")
        .putFloat("memoryUsage", memoryUsage)
        .put("disk", "${formatBytesText(diskUsed)} / ${formatBytesText(diskTotal)}")
        .putFloat("diskUsage", diskUsage)
        .put("diskPath", parseJsonString(disk.toString(), "path") ?? "/")
        .putInt("tasks", server.listTasks().size)
        .putInt("devices", devices.size)
        .putInt("onlineDevices", onlineDevices)
        .putInt("logTotal", jsonObjectInt(logStats, "total"))
}

func buildAdminDrivesPayload(server: CoreServer): JsonObject {
    let arr = JsonArray()
    let seen = HashMap<String, Bool>()
    let defaultVisible = folderVisibilitySettings.get("/") ?? true

    addAdminDrive(arr, seen, "文件根目录", if (server.localRootDir.size > 0) { server.localRootDir } else { "/" }, defaultVisible, "/")
    addAdminDrive(arr, seen, "临时目录", server.config.tempDir, true, "")
    addAdminDrive(arr, seen, "日志目录", server.config.logDir, true, "")
    if (server.profile.supportsRelay) {
        addAdminDrive(arr, seen, "中继缓存", server.config.relayCacheDir, true, "")
    }

    JsonObject()
        .putBool("success", true)
        .putArr("drives", arr)
}

func addAdminDrive(arr: JsonArray, seen: HashMap<String, Bool>, name: String, path: String, visible: Bool, visibilityPath: String): Unit {
    if (path.size == 0) {
        return
    }
    if ((seen.get(path) ?? false)) {
        return
    }
    seen.add(path, true)

    let snap = DefaultDiskProbe().snapshot(path)
    let usedPercent = if (snap.totalBytes > 0) {
        Float64(snap.usedBytes) / Float64(snap.totalBytes) * 100.0
    } else {
        0.0
    }

    arr.addObj(JsonObject()
        .put("name", name)
        .put("path", path)
        .put("visibilityPath", visibilityPath)
        .put("used", formatBytesText(snap.usedBytes))
        .put("size", formatBytesText(snap.totalBytes))
        .put("free", formatBytesText(snap.freeBytes))
        .putFloat("usedPercent", usedPercent)
        .putBool("visible", visible))
}

func buildVisibilityFolders(masters: MasterBundle): JsonArray {
    let out = JsonArray()
    let nodes = ArrayList<VisibilityFolderNode>()
    collectVisibilityFolders(masters, "/", 1, 3, 240, nodes)
    for (node in nodes) {
        out.addObj(node.toJson())
    }
    out
}

func collectVisibilityFolders(
    masters: MasterBundle,
    currentPath: String,
    depth: Int64,
    maxDepth: Int64,
    maxCount: Int64,
    out: ArrayList<VisibilityFolderNode>
): Unit {
    if (depth > maxDepth || out.size >= maxCount) {
        return
    }

    let entries = masters.files.listDir("local", currentPath)
    for (entry in entries) {
        if (!entry.isDir) {
            continue
        }
        if (shouldHideEntryByName(entry.name)) {
            continue
        }
        if (out.size >= maxCount) {
            break
        }
        let normalized = normalizeFolderPath(entry.path)
        out.add(VisibilityFolderNode(
            normalized,
            entry.name,
            depth,
            folderVisibilitySettings.get(normalized) ?? true
        ))
        collectVisibilityFolders(masters, normalized, depth + 1, maxDepth, maxCount, out)
    }
}

func normalizeFolderPath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) {
        return "/"
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

func invalidateListDirCache(): Unit {
    synchronized(listDirCacheMutex) {
        listDirCache = HashMap<String, ListDirCacheEntry>()
    }
}

func shouldHideEntryByName(name: String): Bool {
    let trimmed = name.trimAscii()
    let lower = trimmed.toLower()
    if (hideDotEntriesInExplorer && strStartsWith(trimmed, ".")) {
        return true
    }
    if (hideCacheEntriesInExplorer && isCacheNoiseEntryName(lower)) {
        return true
    }
    false
}

func isCacheNoiseEntryName(lowerName: String): Bool {
    lowerName == ".ds_store" ||
        lowerName == "_ds.store" ||
        lowerName == "desktop.ini" ||
        lowerName == "thumbs.db" ||
        lowerName == "ehthumbs.db"
}

func roundPercent(value: Float64): Int64 {
    if (value <= 0.0) {
        return 0
    }
    Int64(value + 0.5)
}

func formatDurationHuman(seconds: Int64): String {
    if (seconds <= 0) {
        return "0秒"
    }
    let days = seconds / 86400
    let hours = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    var parts = ArrayList<String>()
    if (days > 0) { parts.add("${days}天") }
    if (hours > 0) { parts.add("${hours}小时") }
    if (minutes > 0) { parts.add("${minutes}分钟") }
    if (secs > 0 && parts.size < 2) { parts.add("${secs}秒") }
    if (parts.size == 0) {
        return "0秒"
    }

    var text = ""
    var i: Int64 = 0
    while (i < parts.size && i < 2) {
        text += parts[i]
        i += 1
    }
    text
}

func jsonObjectInt(obj: JsonObject, field: String): Int64 {
    let raw = parseJsonString(obj.toString(), field) ?? "0"
    try {
        return Int64.parse(raw)
    } catch (_: Exception) {
        return 0
    }
}

func jsonObjectFloat(obj: JsonObject, field: String): Float64 {
    let raw = parseJsonString(obj.toString(), field) ?? "0"
    try {
        return Float64.parse(raw)
    } catch (_: Exception) {
        return 0.0
    }
}

func formatBytesText(bytes: Int64): String {
    if (bytes < 1024) {
        return "${bytes} B"
    }
    if (bytes < 1024 * 1024) {
        return "${bytes / 1024} KB"
    }
    if (bytes < 1024 * 1024 * 1024) {
        return "${bytes / (1024 * 1024)} MB"
    }
    "${bytes / (1024 * 1024 * 1024)} GB"
}

func filterVisibleEntries(entries: ArrayList<FileEntry>, currentPath: String): ArrayList<FileEntry> {
    let filtered = ArrayList<FileEntry>()
    for (entry in entries) {
        if (shouldHideEntryByName(entry.name)) {
            continue
        }
        if (entry.isDir) {
            let fullPath = currentPath + "/" + entry.name
            let normalizedPath = if (strStartsWith(fullPath, "//")) {
                strTrimPrefix(fullPath, "/")
            } else {
                fullPath
            }
            var depth: Int64 = 1
            let trimmed = normalizedPath.trimAscii()
            for (ch in trimmed.toRuneArray()) {
                if (ch == r'/') { depth += 1 }
            }
            if (depth > 4) { continue }
            if (let Some(visible) <- folderVisibilitySettings.get(normalizedPath)) {
                if (!visible) { continue }
            }
        }
        filtered.add(entry)
    }
    filtered
}

func serveDownloadResponse(ctx: Ctx, s: CoreServer, m: MasterBundle, deviceId: String, path: String): Unit {
    match (m.files.getInfo(deviceId, path)) {
        case Some(info) => serveResolvedFileResponse(ctx, s, m, deviceId, path, info, true)
        case None =>
            ctx.status(404).json(JsonObject().put("error", "文件不存在").toString())
    }
}

func serveInlineResponse(ctx: Ctx, s: CoreServer, m: MasterBundle, deviceId: String, path: String): Unit {
    match (m.files.getInfo(deviceId, path)) {
        case Some(info) => serveResolvedFileResponse(ctx, s, m, deviceId, path, info, false)
        case None =>
            ctx.status(404).json(JsonObject()
                .putBool("success", false)
                .put("error", "文件不存在")
                .toString())
    }
}

func serveResolvedFileResponse(
    ctx: Ctx,
    s: CoreServer,
    m: MasterBundle,
    deviceId: String,
    path: String,
    info: FileMetadata,
    asAttachment: Bool
): Unit {
    if (info.isDir) {
        ctx.status(400).json(JsonObject()
            .putBool("success", false)
            .put("error", "目录不能作为单文件流返回")
            .toString())
        return
    }

    let contentType = resolvePreviewMimeType(info.mimeType, path, false)
    if (deviceId == "local") {
        let localRoot = s.localRootDir
        if (localRoot.size > 0) {
            let fullPath = joinLocalDownloadPath(localRoot, path)
            streamLocalFileResponse(ctx, fullPath, info.name, info.size, asAttachment, contentType)
            return
        }
    }

    let totalSize = info.size
    let rangeHeader = ctx.header("range") ?? ""
    if (asAttachment) {
        let _ = ctx.setHeader("Content-Disposition", "attachment; filename=${info.name}")
    } else {
        let _ = ctx.setHeader("Content-Disposition", "inline; filename=${info.name}")
    }
    if (rangeHeader.size > 0 && strStartsWith(rangeHeader.toLower(), "bytes=")) {
        match (parseRange(rangeHeader, totalSize)) {
            case Some((start, end)) =>
                let length = end - start + 1
                let data = m.files.read(deviceId, path, start, length)
                let _ = ctx.setHeader("Accept-Ranges", "bytes")
                let _ = ctx.setHeader("Content-Type", contentType)
                let _ = ctx.setHeader("Content-Range", "bytes ${start}-${end}/${totalSize}")
                let _ = ctx.setHeader("Content-Length", "${length}")
                ctx.status(206).send(data)
                return
            case None =>
                ctx.status(416).json(JsonObject()
                    .put("error", "Range Not Satisfiable")
                    .toString())
                return
        }
    }

    let data = m.files.read(deviceId, path, 0, totalSize)
    let _ = ctx.setHeader("Content-Type", contentType)
    let _ = ctx.setHeader("Accept-Ranges", "bytes")
    let _ = ctx.setHeader("Content-Length", "${totalSize}")
    ctx.send(data)
}

func buildManagedDeviceRecordFromJson(body: String, fallbackId: String, defaultPort: Int64): DeviceRegistryRecord {
    let record = DeviceRegistryRecord()
    let bodyId = (parseJsonString(body, "id") ?? "").trimAscii()
    record.id = if (bodyId.size > 0) { bodyId } else { fallbackId.trimAscii() }
    record.name = parseJsonString(body, "name") ?? ""
    record.deviceType = parseJsonString(body, "deviceType") ?? (parseJsonString(body, "type") ?? "")
    record.connectorType = parseJsonString(body, "connectorType") ?? (parseJsonString(body, "connector") ?? "")
    record.ip = parseJsonString(body, "ip") ?? (parseJsonString(body, "host") ?? "")

    let portRaw = parseJsonString(body, "port") ?? ""
    if (portRaw.trimAscii().size > 0) {
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

func logAccessUrls(server: CoreServer, localIP: String, port: UInt16): Unit {
    server.logger.logInfo("system", "Web控制台启动在:", "本地访问: http://localhost:${port}", "")
    if (localIP.size > 0 && localIP != "127.0.0.1") {
        server.logger.logInfo("system", "局域网访问:", "局域网访问: http://${localIP}:${port}", "")
    }
}

func resolveBindHost(listenAddr: String): String {
    let normalized = listenAddr.trimAscii()
    if (normalized.size == 0 || normalized == ":8080" || normalized == ":8081") {
        return "0.0.0.0"
    }
    let runes = normalized.toRuneArray()
    var lastColon: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r':') {
            lastColon = i
        }
    }
    if (lastColon <= 0) {
        if (normalized == "localhost") {
            return "127.0.0.1"
        }
        return normalized
    }
    let host = strSubstring(normalized, 0, lastColon).trimAscii()
    if (host.size == 0) {
        return "0.0.0.0"
    }
    if (host == "localhost") {
        return "127.0.0.1"
    }
    host
}

func currentProductVersion(): String {
    resolveProductVersion(GetData.GetDataClass.ModuleVer())
}

func firstNonEmpty(values: Array<String>): String {
    for (value in values) {
        if (value.trimAscii().size > 0) {
            return value
        }
    }
    ""
}

func buildConnectorBindingJson(server: CoreServer, device: Device): JsonObject {
    let resolvedType = defaultConnectorTypeForDevice(device)
    let out = JsonObject()
        .put("id", device.id)
        .put("name", device.name)
        .put("deviceType", device.deviceType)
        .put("connectorType", resolvedType)
        .put("ip", device.ip)
        .putInt("port", device.port)
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

func collectLegacyUploadFiles(ctx: Ctx): ArrayList<FormFile> {
    let out = ArrayList<FormFile>()

    let primary = ctx.formFiles("file")
    for (item in primary) {
        out.add(item)
    }

    let namedList = ctx.formFiles("files")
    for (item in namedList) {
        out.add(item)
    }

    let chunkList = ctx.formFiles("chunk")
    for (item in chunkList) {
        out.add(item)
    }

    if (out.size == 0) {
        match (ctx.formFile("file")) {
            case Some(file) => out.add(file)
            case None => ()
        }
    }
    if (out.size == 0) {
        match (ctx.formFile("files")) {
            case Some(file) => out.add(file)
            case None => ()
        }
    }
    if (out.size == 0) {
        match (ctx.formFile("chunk")) {
            case Some(file) => out.add(file)
            case None => ()
        }
    }

    out
}

func streamLocalFileResponse(
    ctx: Ctx,
    fullPath: String,
    fileName: String,
    totalSize: Int64,
    asAttachment: Bool,
    contentType: String
): Unit {
    let rangeHeader = ctx.header("range") ?? ""
    var start: Int64 = 0
    var end: Int64 = totalSize - 1
    var partial = false

    if (rangeHeader.size > 0 && strStartsWith(rangeHeader.toLower(), "bytes=")) {
        match (parseRange(rangeHeader, totalSize)) {
            case Some((rangeStart, rangeEnd)) =>
                start = rangeStart
                end = rangeEnd
                partial = true
            case None =>
                ctx.status(416).json(JsonObject()
                    .put("error", "Range Not Satisfiable")
                    .toString())
                return
        }
    }

    if (asAttachment) {
        let _ = ctx.setHeader("Content-Disposition", "attachment; filename=${fileName}")
    } else {
        let _ = ctx.setHeader("Content-Disposition", "inline; filename=${fileName}")
    }
    let _ = ctx.setHeader("Content-Type", contentType)
    let _ = ctx.setHeader("Accept-Ranges", "bytes")
    if (partial) {
        let _ = ctx.status(206)
        let _ = ctx.setHeader("Content-Range", "bytes ${start}-${end}/${totalSize}")
        let _ = ctx.setHeader("Content-Length", "${end - start + 1}")
    } else {
        let _ = ctx.setHeader("Content-Length", "${totalSize}")
    }

    try {
        let file = File(fullPath, OpenMode.Read)
        skipFileBytes(file, start)

        let writer = HttpResponseWriter(ctx.httpContext())
        var remaining = end - start + 1
        while (remaining > 0) {
            let chunkSize = if (remaining > 262144) { 262144 } else { remaining }
            let buf = Array<UInt8>(chunkSize, repeat: 0)
            let n = file.read(buf)
            if (n <= 0) {
                break
            }
            if (n == chunkSize) {
                writer.write(buf)
            } else {
                let actual = Array<UInt8>(n, repeat: 0)
                for (i in 0..n) {
                    actual[i] = buf[i]
                }
                writer.write(actual)
            }
            remaining -= n
        }
        file.close()
    } catch (e: Exception) {
        ctx.status(500).json(JsonObject()
            .put("error", "文件下载失败: ${e.message}")
            .toString())
    }
}

func skipFileBytes(file: File, offset: Int64): Unit {
    var remaining = offset
    while (remaining > 0) {
        let chunkSize = if (remaining > 262144) { 262144 } else { remaining }
        let skipBuf = Array<UInt8>(chunkSize, repeat: 0)
        let n = file.read(skipBuf)
        if (n <= 0) {
            break
        }
        remaining -= n
    }
}

func joinLocalDownloadPath(root: String, relative: String): String {
    if (relative.size == 0) {
        return root
    }
    let rootRunes = root.toRuneArray()
    let relativeRunes = relative.toRuneArray()
    let rootEndsSlash = rootRunes[rootRunes.size - 1] == r'/'
    let relativeStartsSlash = relativeRunes[0] == r'/'
    if (rootEndsSlash && relativeStartsSlash) {
        return root + strSubstring(relative, 1, relativeRunes.size)
    }
    if (!rootEndsSlash && !relativeStartsSlash) {
        return root + "/" + relative
    }
    return root + relative
}

func buildFilePreviewPayload(
    m: MasterBundle,
    deviceId: String,
    path: String,
    info: FileMetadata
): JsonObject {
    let mimeType = resolvePreviewMimeType(info.mimeType, path, info.isDir)
    let kind = resolvePreviewKind(path, mimeType, info.isDir)
    let canPreview = !info.isDir && kind != "unsupported"
    let payload = JsonObject()
        .putBool("success", true)
        .put("device", deviceId)
        .put("name", if (info.name.size > 0) { info.name } else { basenameFromPreviewPath(path) })
        .put("path", if (info.path.size > 0) { info.path } else { path })
        .putInt("size", info.size)
        .putInt("modified", info.modified)
        .putBool("isDir", info.isDir)
        .put("mimeType", mimeType)
        .put("kind", kind)
        .putBool("canPreview", canPreview)
        .put("downloadUrl", buildFsQueryUrl("/api/fs/download", deviceId, path))

    if (canPreview) {
        payload.put("previewUrl", buildFsQueryUrl("/api/fs/stream", deviceId, path))
    }

    if (info.isDir) {
        payload.put("message", "目录暂不提供内容预览")
        return payload
    }

    if (kind == "unsupported") {
        payload.put("message", "当前类型暂不支持预览")
        return payload
    }

    if (isTextPreviewKind(kind)) {
        let language = resolvePreviewLanguage(path, mimeType)
        let snippet = buildTextPreviewSnippet(m, deviceId, path, info.size)
        payload.put("encoding", snippet.encoding)
            .put("content", snippet.content)
            .putInt("lineCount", snippet.lineCount)
            .putBool("truncated", snippet.truncated)
        if (language.size > 0) {
            payload.put("language", language)
        }
    }

    payload
}

func buildTextPreviewSnippet(m: MasterBundle, deviceId: String, path: String, totalSize: Int64): TextPreviewSnippet {
    let out = TextPreviewSnippet()
    if (totalSize <= 0) {
        return out
    }

    let readSize = if (totalSize > previewTextMaxBytes) { previewTextMaxBytes } else { totalSize }
    let bytes = m.files.read(deviceId, path, 0, readSize)
    out.truncated = totalSize > readSize
    if (bytes.size == 0) {
        return out
    }

    out.encoding = detectTextEncoding(bytes)
    try {
        out.content = decodeTextBytes(bytes, out.encoding)
    } catch (_: Exception) {
        out.encoding = "utf-8"
        out.content = String.fromUtf8(bytes)
    }
    out.lineCount = countPreviewLines(out.content)
    out
}

func countPreviewLines(text: String): Int64 {
    if (text.size == 0) {
        return 0
    }
    var count: Int64 = 1
    for (r in text.toRuneArray()) {
        if (r == r'\n') {
            count += 1
        }
    }
    count
}

func basenameFromPreviewPath(path: String): String {
    let normalized = path.trimAscii()
    if (normalized.size == 0 || normalized == "/") {
        return "/"
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

func buildFsQueryUrl(base: String, deviceId: String, path: String): String {
    "${base}?device=${urlEncodePreviewQueryValue(deviceId)}&path=${urlEncodePreviewQueryValue(path)}"
}

func urlEncodePreviewQueryValue(input: String): String {
    let out = ArrayList<UInt8>()
    for (b in input.toArray()) {
        if (isPreviewSafeQueryByte(UInt8(b))) {
            out.add(UInt8(b))
            continue
        }
        if (b == 32) {
            out.add(UInt8(43))
            continue
        }
        let byteValue = Int64(b)
        let high = UInt8(byteValue / 16)
        let low = UInt8(byteValue % 16)
        let encoded = "%${hexPreviewDigit(high)}${hexPreviewDigit(low)}".toArray()
        for (c in encoded) {
            out.add(UInt8(c))
        }
    }
    String.fromUtf8(out.toArray())
}

func isPreviewSafeQueryByte(b: UInt8): Bool {
    (b >= 48 && b <= 57) ||
    (b >= 65 && b <= 90) ||
    (b >= 97 && b <= 122) ||
    b == 45 || b == 46 || b == 95 || b == 126 || b == 47
}

func hexPreviewDigit(v: UInt8): String {
    match (v) {
        case 0 => "0"
        case 1 => "1"
        case 2 => "2"
        case 3 => "3"
        case 4 => "4"
        case 5 => "5"
        case 6 => "6"
        case 7 => "7"
        case 8 => "8"
        case 9 => "9"
        case 10 => "A"
        case 11 => "B"
        case 12 => "C"
        case 13 => "D"
        case 14 => "E"
        case _ => "F"
    }
}

func parseRange(rangeHeader: String, totalSize: Int64): ?(Int64, Int64) {
    if (totalSize <= 0) {
        return None
    }
    let normalized = rangeHeader.trimAscii().toLower()
    if (!strStartsWith(normalized, "bytes=")) {
        return None
    }
    let raw = strSubstring(normalized, 6, normalized.size)
    let runes = raw.toRuneArray()
    var dash: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'-') {
            dash = i
            break
        }
    }
    if (dash < 0) {
        return None
    }
    let left = strSubstring(raw, 0, dash).trimAscii()
    let right = strSubstring(raw, dash + 1, raw.size).trimAscii()

    var start: Int64 = 0
    var end: Int64 = totalSize - 1

    if (left.size == 0) {
        var suffixLen: Int64 = 0
        try { suffixLen = Int64.parse(right) } catch (_: Exception) { return None }
        if (suffixLen <= 0) { return None }
        if (suffixLen >= totalSize) {
            start = 0
        } else {
            start = totalSize - suffixLen
        }
    } else {
        try { start = Int64.parse(left) } catch (_: Exception) { return None }
        if (right.size > 0) {
            try { end = Int64.parse(right) } catch (_: Exception) { return None }
        }
    }

    if (start < 0 || start >= totalSize) {
        return None
    }
    if (end < start) {
        return None
    }
    if (end >= totalSize) {
        end = totalSize - 1
    }
    Some((start, end))
}

func parseFavoriteEntries(body: String): ArrayList<FavoriteEntry> {
    let entries = ArrayList<FavoriteEntry>()
    let objectList = extractJsonArrayObjects(body, "favorites")
    for (raw in objectList) {
        let deviceId = parseJsonString(raw, "deviceId") ?? ""
        let path = parseJsonString(raw, "path") ?? ""
        if (deviceId.size == 0 || path.size == 0) {
            continue
        }
        let item = FavoriteEntry()
        item.deviceId = deviceId
        item.path = path
        item.name = parseJsonString(raw, "name") ?? ""
        let createdAtStr = parseJsonString(raw, "createdAt") ?? "0"
        try {
            item.createdAt = Int64.parse(createdAtStr)
        } catch (_: Exception) {
            item.createdAt = currentTimestamp()
        }
        entries.add(item)
    }
    entries
}

func parseJsonStringArray(json: String, field: String): ArrayList<String> {
    let out = ArrayList<String>()
    let key = "\"${field}\""
    let runes = json.toRuneArray()
    let keyRunes = key.toRuneArray()
    var keyStart: Int64 = -1

    var i: Int64 = 0
    while (i <= runes.size - keyRunes.size) {
        var matched = true
        for (j in 0..keyRunes.size) {
            if (runes[i + j] != keyRunes[j]) {
                matched = false
                break
            }
        }
        if (matched) {
            keyStart = i + keyRunes.size
            break
        }
        i += 1
    }

    if (keyStart < 0) {
        return out
    }

    while (keyStart < runes.size && runes[keyStart] != r'[') {
        keyStart += 1
    }
    if (keyStart >= runes.size) {
        return out
    }

    var depth: Int64 = 0
    var inString = false
    var escaped = false
    var startValue: Int64 = -1
    var index = keyStart
    while (index < runes.size) {
        let ch = runes[index]
        if (inString) {
            if (escaped) {
                escaped = false
                index += 1
                continue
            }
            if (ch == r'\\') {
                escaped = true
                index += 1
                continue
            }
            if (ch == r'"') {
                let value = strSubstring(json, startValue, index)
                out.add(value)
                inString = false
                startValue = -1
            }
            index += 1
            continue
        }

        if (ch == r'[') {
            depth += 1
        } else if (ch == r']') {
            depth -= 1
            if (depth == 0) {
                break
            }
        } else if (ch == r'"') {
            inString = true
            startValue = index + 1
        }
        index += 1
    }
    out
}

func extractJsonArrayObjects(json: String, field: String): ArrayList<String> {
    let out = ArrayList<String>()
    let key = "\"${field}\""
    let runes = json.toRuneArray()
    let keyRunes = key.toRuneArray()
    var startIdx: Int64 = -1

    var i: Int64 = 0
    while (i <= runes.size - keyRunes.size) {
        var ok = true
        for (j in 0..keyRunes.size) {
            if (runes[i + j] != keyRunes[j]) {
                ok = false
                break
            }
        }
        if (ok) {
            startIdx = i + keyRunes.size
            break
        }
        i += 1
    }

    if (startIdx < 0) {
        return out
    }

    while (startIdx < runes.size && runes[startIdx] != r'[') {
        startIdx += 1
    }
    if (startIdx >= runes.size) {
        return out
    }

    var depth: Int64 = 0
    var endIdx: Int64 = -1
    var inString = false
    var escaped = false
    var k = startIdx
    while (k < runes.size) {
        let ch = runes[k]
        if (inString) {
            if (escaped) {
                escaped = false
            } else if (ch == r'\\') {
                escaped = true
            } else if (ch == r'"') {
                inString = false
            }
            k += 1
            continue
        }

        if (ch == r'"') {
            inString = true
            k += 1
            continue
        }
        if (ch == r'[') {
            depth += 1
        } else if (ch == r']') {
            depth -= 1
            if (depth == 0) {
                endIdx = k
                break
            }
        }
        k += 1
    }

    if (endIdx <= startIdx) {
        return out
    }

    let arrayRaw = strSubstring(json, startIdx + 1, endIdx)
    splitJsonObjectsLoose(arrayRaw)
}

func splitJsonObjectsLoose(raw: String): ArrayList<String> {
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
            if (depth == 0) { start = i }
            depth += 1
            continue
        }
        if (ch == r'}') {
            depth -= 1
            if (depth == 0 && start >= 0) {
                result.add(strSubstring(raw, start, i + 1))
                start = -1
            }
        }
    }
    result
}
