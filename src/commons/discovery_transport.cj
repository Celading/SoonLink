package soonlnk.commons

import std.collection.ArrayList
import std.convert.*
import std.net.{UdpSocket, IPSocketAddress}
import std.unicode.*

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
        if (running) {
            return
        }
        this.onPacket = onPacket
        this.running = true
        println("[Discovery][UDP] transport started on port ${listenPort}")

        spawn {
            try (serverSocket = UdpSocket(bindAt: resolveDiscoveryPort(listenPort))) {
                serverSocket.bind()

                let buf = Array<UInt8>(4096, repeat: 0)
                while (running) {
                    let (clientAddr, count) = serverSocket.receiveFrom(buf)
                    if (!running) {
                        break
                    }
                    if (count <= 0) {
                        continue
                    }

                    let raw = decodeDiscoveryPayload(buf, count)
                    if (raw.size == 0) {
                        continue
                    }
                    match (discoveryPacketFromJson(raw)) {
                        case Some(packet) =>
                            hydratePacketSourceIp(packet, clientAddr)
                            if (let Some(cb) <- this.onPacket) {
                                cb(packet)
                            }
                        case None => ()
                    }
                }
            } catch (e: Exception) {
                println("[Discovery][UDP] transport failed on port ${listenPort}: ${e.message}")
            }
        }
    }

    public func stop(): Unit {
        if (!running) {
            return
        }
        running = false
        wakeListener()
    }

    public func publishHeartbeat(packet: DiscoveryPacket): Unit {
        if (!running) { return }
        let payload = stringToBytes(packet.toJson().toString())
        let port = resolveDiscoveryPort(listenPort)
        let targets = buildBroadcastTargets(packet.ip)

        try (udpSocket = UdpSocket(bindAt: 0)) {
            udpSocket.sendTimeout = Duration.second * 2
            udpSocket.bind()
            for (target in targets) {
                try {
                    udpSocket.sendTo(IPSocketAddress(target, port), payload)
                } catch (_: Exception) {}
            }
        } catch (_: Exception) {}
    }

    func wakeListener(): Unit {
        try (udpSocket = UdpSocket(bindAt: 0)) {
            udpSocket.sendTimeout = Duration.second * 1
            udpSocket.bind()
            udpSocket.sendTo(IPSocketAddress("127.0.0.1", resolveDiscoveryPort(listenPort)), [UInt8(0)])
        } catch (_: Exception) {}
    }

    func buildBroadcastTargets(localIp: String): Array<String> {
        let targets = ArrayList<String>()
        addDiscoveryTarget(targets, "127.0.0.1")
        addDiscoveryTarget(targets, "255.255.255.255")

        let directed = deriveDirectedBroadcast(localIp)
        if (directed.size > 0) {
            addDiscoveryTarget(targets, directed)
        }

        targets.toArray()
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

func resolveDiscoveryPort(raw: Int64): UInt16 {
    if (raw <= 0 || raw > 65535) {
        return UInt16(19090)
    }
    UInt16(raw)
}

func decodeDiscoveryPayload(buffer: Array<UInt8>, count: Int64): String {
    if (count <= 0) {
        return ""
    }

    let actual = Array<UInt8>(count, repeat: 0)
    for (i in 0..count) {
        actual[i] = buffer[i]
    }

    try {
        String.fromUtf8(actual)
    } catch (_: Exception) {
        ""
    }
}

public func selectDiscoveryAdvertiseIp(explicit: String, candidates: Array<String>): String {
    let manual = normalizeDiscoveryIpCandidate(explicit)
    if (manual.size > 0) {
        return manual
    }

    var bestNonLoopbackIpv4 = ""
    var bestNonLoopback = ""
    var bestLoopbackIpv4 = ""
    var bestAny = ""
    for (candidate in candidates) {
        let normalized = normalizeDiscoveryIpCandidate(candidate)
        if (normalized.size == 0) {
            continue
        }
        if (bestAny.size == 0) {
            bestAny = normalized
        }

        let loopback = isLoopbackDiscoveryIp(normalized)
        if (isIpv4DiscoveryIp(normalized)) {
            if (loopback) {
                if (bestLoopbackIpv4.size == 0) {
                    bestLoopbackIpv4 = normalized
                }
            } else if (isLanDiscoveryIp(normalized)) {
                return normalized
            } else if (bestNonLoopbackIpv4.size == 0) {
                bestNonLoopbackIpv4 = normalized
            }
            continue
        }

        if (!loopback && bestNonLoopback.size == 0) {
            bestNonLoopback = normalized
        }
    }

    if (bestNonLoopbackIpv4.size > 0) {
        return bestNonLoopbackIpv4
    }
    if (bestNonLoopback.size > 0) {
        return bestNonLoopback
    }
    if (bestLoopbackIpv4.size > 0) {
        return bestLoopbackIpv4
    }
    bestAny
}

func hydratePacketSourceIp(packet: DiscoveryPacket, clientAddr: Object): Unit {
    match (clientAddr) {
        case sa: IPSocketAddress =>
            let sender = sa.address.toString()
            if (packet.ip.trimAscii().size == 0 || isLoopbackDiscoveryIp(packet.ip)) {
                packet.ip = sender
            }
        case _ => ()
    }
}

func addDiscoveryTarget(targets: ArrayList<String>, raw: String): Unit {
    let target = raw.trimAscii()
    if (target.size == 0) {
        return
    }
    for (existing in targets) {
        if (existing == target) {
            return
        }
    }
    targets.add(target)
}

public func deriveDirectedBroadcast(ip: String): String {
    let normalized = ip.trimAscii()
    if (normalized.size == 0 || isLoopbackDiscoveryIp(normalized) || !isLanDiscoveryIp(normalized)) {
        return ""
    }

    let runes = normalized.toRuneArray()
    var lastDot: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'.') {
            lastDot = i
        }
    }
    if (lastDot <= 0) {
        return ""
    }
    strSubstring(normalized, 0, lastDot + 1) + "255"
}

func isLoopbackDiscoveryIp(raw: String): Bool {
    let normalized = raw.trimAscii().toLower()
    normalized == "localhost" ||
        normalized == "::1" ||
        normalized == "0.0.0.0" ||
        strStartsWith(normalized, "127.")
}

public func isLanDiscoveryIp(raw: String): Bool {
    let normalized = normalizeDiscoveryIpCandidate(raw)
    if (!isIpv4DiscoveryIp(normalized) || isLoopbackDiscoveryIp(normalized)) {
        return false
    }

    let first = ipv4OctetValue(normalized, 0)
    let second = ipv4OctetValue(normalized, 1)
    if (first == 10) {
        return true
    }
    if (first == 192 && second == 168) {
        return true
    }
    if (first == 172 && second >= 16 && second <= 31) {
        return true
    }
    if (first == 169 && second == 254) {
        return true
    }
    false
}

func normalizeDiscoveryIpCandidate(raw: String): String {
    raw.trimAscii()
}

func isIpv4DiscoveryIp(raw: String): Bool {
    let normalized = normalizeDiscoveryIpCandidate(raw)
    if (normalized.size == 0 || strContains(normalized, ":")) {
        return false
    }

    var dots: Int64 = 0
    for (ch in normalized.toRuneArray()) {
        if (ch == r'.') {
            dots += 1
            continue
        }
        if (ch < r'0' || ch > r'9') {
            return false
        }
    }
    if (dots != 3) {
        return false
    }

    for (index in 0..4) {
        let value = ipv4OctetValue(normalized, index)
        if (value < 0 || value > 255) {
            return false
        }
    }
    true
}

func ipv4OctetValue(ip: String, index: Int64): Int64 {
    let runes = ip.toRuneArray()
    var current: Int64 = 0
    var out = ""
    for (ch in runes) {
        if (ch == r'.') {
            if (current == index) {
                break
            }
            current += 1
            continue
        }
        if (current == index) {
            out += ch.toString()
        }
    }

    if (out.size == 0) {
        return -1
    }
    try {
        Int64.parse(out)
    } catch (_: Exception) {
        -1
    }
}
