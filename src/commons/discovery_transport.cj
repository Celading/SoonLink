package soonlnk.commons

import std.convert.*

public class DiscoveryPacket {
    public var deviceId: String = ""
    public var name: String = ""
    public var deviceType: String = ""
    public var ip: String = ""
    public var port: Int64 = 0
    public var timestamp: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .put("deviceId", deviceId)
            .put("name", name)
            .put("deviceType", deviceType)
            .put("ip", ip)
            .putInt("port", port)
            .putInt("timestamp", timestamp)
    }
}

func discoveryPacketFromJson(raw: String): ?DiscoveryPacket {
    let id = parseJsonString(raw, "deviceId") ?? ""
    if (id.size == 0) {
        return None
    }

    let packet = DiscoveryPacket()
    packet.deviceId = id
    packet.name = parseJsonString(raw, "name") ?? ""
    packet.deviceType = parseJsonString(raw, "deviceType") ?? ""
    packet.ip = parseJsonString(raw, "ip") ?? ""

    let portStr = parseJsonString(raw, "port") ?? "0"
    try {
        packet.port = Int64.parse(portStr)
    } catch (_: Exception) {
        packet.port = 0
    }

    let tsStr = parseJsonString(raw, "timestamp") ?? "0"
    try {
        packet.timestamp = Int64.parse(tsStr)
    } catch (_: Exception) {
        packet.timestamp = currentTimestamp()
    }

    Some(packet)
}

public interface DiscoveryTransport {
    func mode(): String
    func start(onPacket: (DiscoveryPacket) -> Unit): Unit
    func stop(): Unit
    func publishHeartbeat(packet: DiscoveryPacket): Unit
}

public class UdpDiscoveryTransport <: DiscoveryTransport {
    let listenPort: Int64
    var running: Bool = false
    var onPacket: ?(DiscoveryPacket) -> Unit = None

    public init(listenPort: Int64) {
        this.listenPort = listenPort
    }

    public func mode(): String { "udp" }

    public func start(onPacket: (DiscoveryPacket) -> Unit): Unit {
        this.onPacket = onPacket
        this.running = true
        println("[Discovery][UDP] transport started on port ${listenPort}")

        spawn {
            while (running) {
                // TODO: replace loopback heartbeat with real UDP broadcast/multicast transport.
                sleep(Duration.second * 30)
            }
        }
    }

    public func stop(): Unit {
        running = false
    }

    public func publishHeartbeat(packet: DiscoveryPacket): Unit {
        if (!running) { return }
        // current phase: loopback callback to keep pipeline executable.
        if (let Some(cb) <- onPacket) {
            cb(packet)
        }
    }
}

public class MdnsDiscoveryTransport <: DiscoveryTransport {
    var running: Bool = false
    var onPacket: ?(DiscoveryPacket) -> Unit = None

    public init() {}

    public func mode(): String { "mdns" }

    public func start(onPacket: (DiscoveryPacket) -> Unit): Unit {
        this.onPacket = onPacket
        this.running = true
        println("[Discovery][mDNS] skeleton started (TODO: publish/query service records)")

        spawn {
            while (running) {
                sleep(Duration.minute * 5)
            }
        }
    }

    public func stop(): Unit {
        running = false
    }

    public func publishHeartbeat(_packet: DiscoveryPacket): Unit {
        if (!running) { return }
        // TODO: advertise service over mDNS.
    }
}

public class NoopDiscoveryTransport <: DiscoveryTransport {
    let name: String

    public init() {
        this.name = "noop"
    }

    public init(name: String) {
        this.name = name
    }

    public func mode(): String { name }

    public func start(_onPacket: (DiscoveryPacket) -> Unit): Unit {}
    public func stop(): Unit {}
    public func publishHeartbeat(_packet: DiscoveryPacket): Unit {}
}
