package soonlnk.tests

import soonlnk.commons.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DiscoveryTransport_test {
    @TestCase
    public func hmacSignedDiscoveryPacketVerifiesWithSameKey(): Unit {
        let packet = sampleDiscoveryPacket()
        discoveryPacketSign(packet, "shared-discovery-secret")

        @Assert(packet.authScheme, "hmac-sha256-v1")
        @Assert(packet.signature.size > 0, true)
        @Assert(discoveryPacketVerify(packet, "shared-discovery-secret"), true)
        @Assert(discoveryPacketVerify(packet, "wrong-secret"), false)
    }

    @TestCase
    public func hmacSignedDiscoveryPacketRejectsTampering(): Unit {
        let packet = sampleDiscoveryPacket()
        discoveryPacketSign(packet, "shared-discovery-secret")

        packet.ip = "192.168.1.99"
        @Assert(discoveryPacketVerify(packet, "shared-discovery-secret"), false)
    }

    @TestCase
    public func discoveryPacketAuthGateKeepsNoKeyCompatibility(): Unit {
        let packet = sampleDiscoveryPacket()

        @Assert(discoveryPacketVerify(packet, ""), true)
        @Assert(discoveryPacketVerify(packet, "shared-discovery-secret"), false)
    }

    @TestCase
    public func discoverySigningPayloadEscapesDelimiters(): Unit {
        let packet = sampleDiscoveryPacket()
        packet.name = "lab|node\\one"

        let payload = discoveryPacketSigningPayload(packet)
        @Assert(payload.contains("lab\\|node\\\\one"), true)
    }

    @TestCase
    public func localSendUdpDiscoveryPayloadNormalizesPeerEndpoint(): Unit {
        @Assert(localSendUdpMulticastAddress(), "224.0.0.167")
        @Assert(localSendDefaultPort(), 53317)

        let payload = localSendDiscoveryPayload(
            "Cool Carrot",
            "2.1",
            "macOS",
            "desktop",
            "fp-local",
            "https",
            53317,
            true
        )
        match (parseLocalSendDiscoveryPayload(payload, "192.168.1.44")) {
            case Some(peer) =>
                @Assert(peer.alias, "Cool Carrot")
                @Assert(peer.protocol, "https")
                @Assert(peer.port, 53317)
                @Assert(peer.download, true)
                @Assert(peer.announcement, true)
                @Assert(peer.endpoint, "https://192.168.1.44:53317")
            case None => @Assert(false)
        }
    }

    @TestCase
    public func localSendUdpAnnouncerBuildsStableMulticastPayload(): Unit {
        let announcer = LocalSendUdpAnnouncer()
        @Assert(announcer.targetAddress(), "224.0.0.167")
        @Assert(announcer.targetPort(), 53317)

        let payload = announcer.buildPayload(
            "SoonLink Lab",
            "",
            "SoonLink",
            "desktop",
            "fp-soonlink",
            "http",
            19058,
            false
        )

        match (parseLocalSendDiscoveryPayload(payload, "192.168.1.70")) {
            case Some(peer) =>
                @Assert(peer.alias, "SoonLink Lab")
                @Assert(peer.version, "2.1")
                @Assert(peer.deviceModel, "SoonLink")
                @Assert(peer.protocol, "http")
                @Assert(peer.port, 19058)
                @Assert(peer.download, false)
                @Assert(peer.announcement, true)
                @Assert(peer.endpoint, "http://192.168.1.70:19058")
            case None => @Assert(false)
        }
    }

    @TestCase
    public func localSendAnnounceTargetsFallbackToDirectedBroadcast(): Unit {
        let targets = buildLocalSendAnnounceTargets("224.0.0.167", "192.168.0.76")
        @Assert(targets.size, 3)
        @Assert(targets[0], "224.0.0.167")
        @Assert(targets[1], "192.168.0.255")
        @Assert(targets[2], "255.255.255.255")
    }
}

func sampleDiscoveryPacket(): DiscoveryPacket {
    let packet = DiscoveryPacket()
    packet.deviceId = "peer-device-1"
    packet.name = "Lab Node"
    packet.deviceType = "desktop"
    packet.ip = "192.168.1.10"
    packet.port = 8081
    packet.timestamp = 1710000000
    packet
}
