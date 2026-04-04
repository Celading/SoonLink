package soonlnk.features

import soonlnk.api2.*
import soonlnk.commons.*
import lisi.getNetworkInfo
import std.collection.ArrayList
import std.convert.*
import std.env.getVariable
import std.unicode.*

public class MonitorFeature {
    let defaultPath: String
    let diskProbe: DiskProbe
    let networkProbeEnabled: Bool
    var primaryIpProvider: ?() -> String = None

    public init(
        defaultPath!: String = "/",
        diskProbe!: DiskProbe = DefaultDiskProbe(),
        networkProbeEnabled!: Bool = false
    ) {
        this.defaultPath = if (defaultPath.size > 0) { defaultPath } else { "/" }
        this.diskProbe = diskProbe
        let envEnabled = (getVariable("SOONLINK_ENABLE_NETWORK_PROBE") ?? "").toLower() == "true"
        this.networkProbeEnabled = networkProbeEnabled || envEnabled
    }

    public func setPrimaryIpProvider(provider: () -> String): Unit {
        primaryIpProvider = Some(provider)
    }

    public func systemSnapshot(uptime: Int64): JsonObject {
        let disk = diskSnapshot(defaultPath)
        let network = networkSnapshot()
        JsonObject()
            .put("os", "cangjie")
            .put("platform", "native")
            .put("hostname", resolveHostname())
            .putInt("uptime", uptime)
            .putFloat("cpuUsage", 0.0)
            .putFloat("memoryUsage", 0.0)
            .putFloat("diskUsage", parseJsonFloat(disk, "usedPercent"))
            .putFloat("temperature", 0.0)
            .putInt("networkRx", parseJsonInt(network, "bytesRecv"))
            .putInt("networkTx", parseJsonInt(network, "bytesSent"))
            .put("primaryIp", parseJsonString(network.toString(), "primaryIp") ?? "")
            .put("gateway", parseJsonString(network.toString(), "gateway") ?? "")
            .putInt("timestamp", currentTimestamp())
    }

    public func cpuSnapshot(): JsonObject {
        JsonObject()
            .putFloat("usage", 0.0)
            .putInt("timestamp", currentTimestamp())
    }

    public func memorySnapshot(): JsonObject {
        JsonObject()
            .putInt("total", 0)
            .putInt("used", 0)
            .putInt("free", 0)
            .putFloat("usedPercent", 0.0)
            .putInt("timestamp", currentTimestamp())
    }

    public func diskSnapshot(path: String): JsonObject {
        let snap = diskProbe.snapshot(if (path.size > 0) { path } else { defaultPath })
        let usedPercent = if (snap.totalBytes > 0) {
            Float64(snap.usedBytes) / Float64(snap.totalBytes) * 100.0
        } else {
            0.0
        }
        JsonObject()
            .putInt("total", snap.totalBytes)
            .putInt("used", snap.usedBytes)
            .putInt("free", snap.freeBytes)
            .putFloat("usedPercent", usedPercent)
            .put("path", if (path.size > 0) { path } else { snap.mountPoint })
            .putInt("timestamp", currentTimestamp())
    }

    public func networkSnapshot(): JsonObject {
        var primaryIp = ""
        let ipArr = JsonArray()
        var gateway = ""
        let dnsArr = JsonArray()
        if (let Some(provider) <- primaryIpProvider) {
            try {
                primaryIp = provider()
            } catch (_: Exception) {}
        }
        if (primaryIp.size > 0) {
            ipArr.addStr(primaryIp)
        }
        if (networkProbeEnabled) {
            try {
                let info = getNetworkInfo()
                if (primaryIp.size == 0 && info.ips.size > 0) {
                    primaryIp = info.ips[0]
                }
                for (ip in info.ips) {
                    ipArr.addStr(ip)
                }
                match (info.gateway) {
                    case Some(v) => gateway = v
                    case None => ()
                }
                for (dns in info.dns) {
                    dnsArr.addStr(dns)
                }
            } catch (_: Exception) {}
        }
        JsonObject()
            .putInt("bytesRecv", 0)
            .putInt("bytesSent", 0)
            .putInt("packetsRecv", 0)
            .putInt("packetsSent", 0)
            .put("primaryIp", primaryIp)
            .put("gateway", gateway)
            .putArr("ips", ipArr)
            .putArr("dns", dnsArr)
            .putInt("timestamp", currentTimestamp())
    }

    public func temperatureSnapshot(): JsonObject {
        JsonObject()
            .putFloat("temperature", 0.0)
            .put("unit", "°C")
            .putInt("timestamp", currentTimestamp())
    }

    public func uptimeSnapshot(uptime: Int64): JsonObject {
        JsonObject()
            .putInt("uptime", uptime)
            .putInt("bootTime", currentTimestamp() - uptime)
            .putInt("timestamp", currentTimestamp())
    }
}

func resolveHostname(): String {
    let hostname = getVariable("HOSTNAME") ?? getVariable("HOST") ?? ""
    if (hostname.size > 0) {
        return hostname
    }
    "localhost"
}

func parseJsonInt(obj: JsonObject, field: String): Int64 {
    let raw = parseJsonString(obj.toString(), field) ?? "0"
    try {
        return Int64.parse(raw)
    } catch (_: Exception) {
        return 0
    }
}

func parseJsonFloat(obj: JsonObject, field: String): Float64 {
    let raw = parseJsonString(obj.toString(), field) ?? "0"
    try {
        return Float64.parse(raw)
    } catch (_: Exception) {
        return 0.0
    }
}
