package soonlnk.commons

import std.unicode.*

public class DeviceEndpoint {
    public var scheme: String = ""
    public var host: String = ""
    public var port: Int64 = 0
    public var basePath: String = ""
    public var origin: String = ""

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("scheme", scheme)
            .put("host", host)
            .putInt("port", port)
            .put("basePath", basePath)
            .put("origin", origin)
    }
}

public func normalizeEndpointScheme(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    match (normalized) {
        case "tls" => "https"
        case "ssl" => "https"
        case _ => normalized
    }
}

public func normalizeEndpointBasePath(raw: String): String {
    var out = raw.trimAscii()
    if (out.size == 0 || out == "/") {
        return ""
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

public func defaultEndpointSchemeForDevice(device: Device): String {
    let explicit = normalizeEndpointScheme(device.endpointScheme)
    if (explicit.size > 0) {
        return explicit
    }

    let connectorType = device.connectorType.trimAscii().toLower()
    if (connectorType == "local-fs" || device.id == "local" || device.deviceType == "local") {
        return "local"
    }
    if (
        connectorType == "soonlink-http" ||
        connectorType == "soonlink" ||
        connectorType == "soonlink-node" ||
        connectorType == "soonlnk-http"
    ) {
        return "http"
    }
    if (device.ip.trimAscii().size > 0 && device.port > 0) {
        return "http"
    }
    ""
}

public func defaultEndpointBasePathForDevice(device: Device): String {
    normalizeEndpointBasePath(device.endpointBasePath)
}

public func applyDefaultDeviceEndpoint(device: Device): Unit {
    device.endpointScheme = defaultEndpointSchemeForDevice(device)
    device.endpointBasePath = defaultEndpointBasePathForDevice(device)
}

public func resolveDeviceEndpointOrigin(device: Device): String {
    let scheme = defaultEndpointSchemeForDevice(device)
    let host = device.ip.trimAscii()
    let basePath = defaultEndpointBasePathForDevice(device)
    let port = device.port

    if (scheme == "local") {
        return "local://"
    }
    if (host.size == 0) {
        return ""
    }

    let portPart = if (port > 0) { ":${port}" } else { "" }
    if (scheme.size > 0) {
        return "${scheme}://${host}${portPart}${basePath}"
    }
    "${host}${portPart}${basePath}"
}

public func buildDeviceEndpoint(device: Device): DeviceEndpoint {
    let endpoint = DeviceEndpoint()
    endpoint.scheme = defaultEndpointSchemeForDevice(device)
    endpoint.host = device.ip.trimAscii()
    endpoint.port = device.port
    endpoint.basePath = defaultEndpointBasePathForDevice(device)
    endpoint.origin = resolveDeviceEndpointOrigin(device)
    endpoint
}
