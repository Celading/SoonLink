package soonlnk.commons

import std.unicode.*

public struct RuntimeProfile {
    public var productName: String = "SoonLink"
    public var supportsPassiveDiscovery: Bool = true
    public var supportsActiveDiscovery: Bool = false
    public var supportsMdnsDiscovery: Bool = false
    public var supportsPeerTransfer: Bool = false
    public var supportsRelay: Bool = false
    public var supportsWhitelist: Bool = false
    public var supportsFavorites: Bool = false
    public var supportsAdvancedSecurity: Bool = false
    public var supportsMcp: Bool = true

    public init() {}
}

public func defaultRuntimeProfile(): RuntimeProfile {
    var out = RuntimeProfile()
    out.productName = "SoonLink"
    out.supportsPassiveDiscovery = true
    out.supportsActiveDiscovery = true
    out.supportsMdnsDiscovery = false
    out.supportsPeerTransfer = false
    out.supportsRelay = true
    out.supportsWhitelist = false
    out.supportsFavorites = false
    out.supportsAdvancedSecurity = false
    out.supportsMcp = true
    out
}

public func normalizeAppConfigForRuntime(config: AppConfig, profile: RuntimeProfile): AppConfig {
    var out = config
    if (!profile.supportsPeerTransfer) {
        out.securityMode = "plain"
    }
    if (!profile.supportsActiveDiscovery) {
        out.enableMdns = false
        out.discoveryBroadcastEnabled = false
    } else if (!profile.supportsMdnsDiscovery) {
        out.enableMdns = false
    }
    if (!profile.supportsRelay) {
        out.relayEnabled = false
    }
    out
}

public func applyDefaultDeviceCapabilities(device: Device, profile: RuntimeProfile): Unit {
    if (device.capability.size > 0) {
        return
    }
    device.capability.add("fs")
    device.capability.add("transfer")
    if (profile.supportsPeerTransfer) {
        device.capability.add("peer")
    }
}

public func runtimeCapabilitiesToJson(profile: RuntimeProfile): JsonObject {
    JsonObject()
        .putBool("passiveDiscovery", profile.supportsPassiveDiscovery)
        .putBool("activeDiscovery", profile.supportsActiveDiscovery)
        .putBool("mdnsDiscovery", profile.supportsMdnsDiscovery)
        .putBool("peerTransfer", profile.supportsPeerTransfer)
        .putBool("relay", profile.supportsRelay)
        .putBool("whitelist", profile.supportsWhitelist)
        .putBool("favorites", profile.supportsFavorites)
        .putBool("advancedSecurity", profile.supportsAdvancedSecurity)
        .putBool("mcp", profile.supportsMcp)
}

public func runtimeCapabilityTags(profile: RuntimeProfile): JsonArray {
    let arr = JsonArray()
    arr.addStr("local-device")
    arr.addStr("register-heartbeat")
    arr.addStr("manual-target-config")
    arr.addStr("chunk-transfer")
    arr.addStr("task-transfer")
    if (profile.supportsActiveDiscovery) {
        arr.addStr("active-discovery")
        if (profile.supportsMdnsDiscovery) {
            arr.addStr("mdns-discovery")
        } else {
            arr.addStr("udp-discovery-only")
        }
    } else {
        arr.addStr("passive-discovery-only")
    }
    if (profile.supportsPeerTransfer) {
        arr.addStr("peer-transfer")
    }
    if (profile.supportsRelay) {
        arr.addStr("relay-cache")
        arr.addStr("text-cache-records")
    }
    if (profile.supportsWhitelist) {
        arr.addStr("whitelist")
    }
    if (profile.supportsFavorites) {
        arr.addStr("favorites")
    }
    if (profile.supportsAdvancedSecurity) {
        arr.addStr("advanced-security")
    } else {
        arr.addStr("lite-security")
    }
    if (profile.supportsMcp) {
        arr.addStr("mcp-stdio")
    }
    arr
}

public func resolveTechnicalPackageName(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.size > 0) {
        return trimmed
    }
    "soonlnk"
}

public func resolveProductVersion(raw: String): String {
    let trimmed = raw.trimAscii()
    if (trimmed.size > 0) {
        return trimmed
    }
    "0.0.5"
}

public func resolveRuntimeDisplayName(profile: RuntimeProfile): String {
    let trimmed = profile.productName.trimAscii()
    if (trimmed.size > 0) {
        return trimmed
    }
    "SoonLink"
}
