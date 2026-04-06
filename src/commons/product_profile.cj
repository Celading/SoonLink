package soonlnk.commons

import std.unicode.*

public struct ProductProfile {
    public var edition: String = "core"
    public var productName: String = "SoonLink"
    public var supportsPassiveDiscovery: Bool = true
    public var supportsActiveDiscovery: Bool = false
    public var supportsPeerTransfer: Bool = false
    public var supportsRelay: Bool = false
    public var supportsWhitelist: Bool = false
    public var supportsFavorites: Bool = false
    public var supportsAdvancedSecurity: Bool = false
    public var supportsMcp: Bool = true

    public init() {}
}

public func defaultProductProfile(): ProductProfile {
    coreProductProfile()
}

public func coreProductProfile(): ProductProfile {
    var out = ProductProfile()
    out.edition = "core"
    out.productName = "SoonLink"
    out.supportsPassiveDiscovery = true
    out.supportsActiveDiscovery = false
    out.supportsPeerTransfer = false
    out.supportsRelay = false
    out.supportsWhitelist = false
    out.supportsFavorites = false
    out.supportsAdvancedSecurity = false
    out.supportsMcp = true
    out
}

public func normalizeAppConfigForProfile(config: AppConfig, profile: ProductProfile): AppConfig {
    var out = config
    if (!profile.supportsPeerTransfer) {
        out.securityMode = "plain"
    }
    if (!profile.supportsActiveDiscovery) {
        out.enableMdns = false
    }
    if (!profile.supportsRelay) {
        out.relayEnabled = false
    }
    out
}

public func applyDefaultDeviceCapabilities(device: Device, profile: ProductProfile): Unit {
    if (device.capability.size > 0) {
        return
    }
    device.capability.add("fs")
    device.capability.add("transfer")
    if (profile.supportsPeerTransfer) {
        device.capability.add("peer")
    }
}

public func productCapabilitiesToJson(profile: ProductProfile): JsonObject {
    JsonObject()
        .putBool("passiveDiscovery", profile.supportsPassiveDiscovery)
        .putBool("activeDiscovery", profile.supportsActiveDiscovery)
        .putBool("peerTransfer", profile.supportsPeerTransfer)
        .putBool("relay", profile.supportsRelay)
        .putBool("whitelist", profile.supportsWhitelist)
        .putBool("favorites", profile.supportsFavorites)
        .putBool("advancedSecurity", profile.supportsAdvancedSecurity)
        .putBool("mcp", profile.supportsMcp)
}

public func productCapabilityTags(profile: ProductProfile): JsonArray {
    let arr = JsonArray()
    arr.addStr("local-device")
    arr.addStr("register-heartbeat")
    arr.addStr("manual-target-config")
    arr.addStr("chunk-transfer")
    arr.addStr("task-transfer")
    if (profile.supportsActiveDiscovery) {
        arr.addStr("active-discovery")
    } else {
        arr.addStr("passive-discovery-only")
    }
    if (profile.supportsPeerTransfer) {
        arr.addStr("peer-transfer")
    }
    if (profile.supportsRelay) {
        arr.addStr("relay-cache")
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
    "0.5.21"
}

public func resolveRuntimeDisplayName(profile: ProductProfile): String {
    let trimmed = profile.productName.trimAscii()
    if (trimmed.size > 0) {
        return trimmed
    }
    "SoonLink"
}
