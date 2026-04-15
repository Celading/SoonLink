package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
import std.net.{UdpSocket, IPSocketAddress}
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class CoreServer_test {
    @TestCase
    public func registerAndHeartbeatDevice(): Unit {
        let scope = testTempToken("soonlink_test_registry")
        var cfg = AppConfig()
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: defaultRuntimeProfile())

        let record = DeviceRegistryRecord()
        record.id = "node-x"
        record.name = "Node-X"
        record.deviceType = "remote"
        record.ip = "10.0.0.2"
        record.port = 8088

        let device = server.registerDeviceRecord(record)
        @Assert(device.id, "node-x")
        @Assert(device.remembered)
        @Assert(deviceTrustStateToString(device.trustState), "unknown")

        match (server.heartbeatDevice("node-x")) {
            case Some(d) => @Assert(d.online)
            case None => @Assert(false)
        }
    }

    @TestCase
    public func registerDeviceDefaultsToSoonLinkConnector(): Unit {
        let scope = testTempToken("soonlink_test_connector_registry")
        var cfg = AppConfig()
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: defaultRuntimeProfile())

        let record = DeviceRegistryRecord()
        record.id = "node-y"
        record.name = "Node-Y"
        record.deviceType = "remote"
        record.ip = "10.0.0.3"
        record.port = 18081

        let device = server.registerDeviceRecord(record)
        @Assert(device.connectorType, "soonlink-http")
        @Assert(device.remembered)
        @Assert(deviceTrustStateToString(device.trustState), "unknown")

        let descriptors = server.listConnectors()
        var foundLocal = false
        var foundSoonLink = false
        for (descriptor in descriptors) {
            if (descriptor.id == "local-fs") {
                foundLocal = true
            }
            if (descriptor.id == "soonlink-http") {
                foundSoonLink = true
            }
        }
        @Assert(foundLocal)
        @Assert(foundSoonLink)
    }

    @TestCase
    public func upsertAndRemoveManagedDeviceRecord(): Unit {
        let scope = testTempToken("soonlink_test_manual_device")
        var cfg = AppConfig()
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: defaultRuntimeProfile())

        let createRecord = DeviceRegistryRecord()
        createRecord.id = "office-node"
        createRecord.name = "Office Node"
        createRecord.deviceType = "remote"
        createRecord.ip = "10.10.0.8"
        createRecord.port = 19110
        createRecord.endpointScheme = "tls"
        createRecord.endpointBasePath = "gateway/manual/"

        let created = server.upsertManagedDeviceRecord(createRecord)
        @Assert(created.id, "office-node")
        @Assert(created.connectorType, "soonlink-http")
        @Assert(created.endpointScheme, "https")
        @Assert(created.endpointBasePath, "/gateway/manual")
        @Assert(!created.online)
        @Assert(created.remembered)
        @Assert(deviceTrustStateToString(created.trustState), "unknown")

        let updateRecord = DeviceRegistryRecord()
        updateRecord.id = "office-node"
        updateRecord.name = "Office Node 2"
        updateRecord.deviceType = "desktop"
        updateRecord.connectorType = "future-sync"
        updateRecord.ip = "office.example.internal"
        updateRecord.port = 22440
        updateRecord.endpointScheme = "https"
        updateRecord.endpointBasePath = "/edge/api"

        let updated = server.upsertManagedDeviceRecord(updateRecord)
        @Assert(updated.name, "Office Node 2")
        @Assert(updated.deviceType, "desktop")
        @Assert(updated.connectorType, "future-sync")
        @Assert(updated.ip, "office.example.internal")
        @Assert(updated.port, 22440)
        @Assert(updated.endpointScheme, "https")
        @Assert(updated.endpointBasePath, "/edge/api")

        @Assert(server.removeManagedDeviceRecord("office-node"))
        match (server.getDevice("office-node")) {
            case Some(_) => @Assert(false)
            case None => @Assert(true)
        }
    }

    @TestCase
    public func rejectsInvalidSoonLinkSchemeWhenConnectorFallsBackFromEndpoint(): Unit {
        let scope = testTempToken("soonlink_test_manual_device_scheme")
        var cfg = AppConfig()
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: defaultRuntimeProfile())

        let record = DeviceRegistryRecord()
        record.id = "proxy-node"
        record.name = "Proxy Node"
        record.deviceType = "remote"
        record.ip = "proxy.example.internal"
        record.port = 19091
        record.endpointScheme = "ftp"

        var failed = false
        try {
            server.upsertManagedDeviceRecord(record)
        } catch (_: Exception) {
            failed = true
        }
        @Assert(failed)
    }

    @TestCase
    public func simpleDiscoveryRuntimeReceivesUdpDiscoveryPacketAndIgnoresSelfNodeId(): Unit {
        let scope = testTempToken("soonlink_test_simple_discovery")
        let discoveryPort = UInt16(pickTestPortSeed())
        var cfg = AppConfig()
        cfg.nodeId = "self-node"
        cfg.discoveryUdpPort = Int64(discoveryPort)
        cfg.enableMdns = false
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: defaultRuntimeProfile())
        server.setConsoleOutputEnabled(false)

        try {
            server.start()

            let selfPacket = DiscoveryPacket()
            selfPacket.deviceId = cfg.nodeId
            selfPacket.name = "Self"
            selfPacket.deviceType = "node"
            selfPacket.ip = "127.0.0.1"
            selfPacket.port = 19091
            sendDiscoveryPacket(discoveryPort, selfPacket)

            let packet = DiscoveryPacket()
            packet.deviceId = "peer-node"
            packet.name = "Peer Node"
            packet.deviceType = "node"
            packet.ip = "10.0.0.8"
            packet.port = 19092
            sendDiscoveryPacket(discoveryPort, packet)

            let device = waitForDevice(server, "peer-node")
            @Assert(device.connectorType, "soonlink-http")
            @Assert(device.deviceType, "node")
            @Assert(device.endpointScheme, "http")
            @Assert(!device.remembered)
            @Assert(!deviceHasCapability(device, "peer"))

            match (server.getDevice(cfg.nodeId)) {
                case Some(_) => @Assert(false)
                case None => @Assert(true)
            }
        } finally {
            server.stop()
        }
    }

    @TestCase
    public func discoveredDeviceDoesNotPersistUntilRemembered(): Unit {
        let scope = testTempToken("soonlink_test_discovery_ephemeral")
        let discoveryPort = UInt16(pickTestPortSeed())
        var cfg = AppConfig()
        cfg.nodeId = "self-node-ephemeral"
        cfg.discoveryUdpPort = Int64(discoveryPort)
        cfg.enableMdns = false
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let first = CoreServer(cfg, profile: defaultRuntimeProfile())
        first.setConsoleOutputEnabled(false)
        try {
            first.start()

            let packet = DiscoveryPacket()
            packet.deviceId = "peer-ephemeral"
            packet.name = "Peer Ephemeral"
            packet.deviceType = "node"
            packet.ip = "10.0.0.18"
            packet.port = 19093
            sendDiscoveryPacket(discoveryPort, packet)

            let device = waitForDevice(first, "peer-ephemeral")
            @Assert(!device.remembered)
        } finally {
            first.stop()
        }

        let second = CoreServer(cfg, profile: defaultRuntimeProfile())
        second.setConsoleOutputEnabled(false)
        try {
            second.start()
            match (second.getDevice("peer-ephemeral")) {
                case Some(_) => @Assert(false)
                case None => @Assert(true)
            }
        } finally {
            second.stop()
        }
    }

    @TestCase
    public func rememberedDiscoveredDeviceSurvivesRestart(): Unit {
        let scope = testTempToken("soonlink_test_discovery_remembered")
        let discoveryPort = UInt16(pickTestPortSeed())
        var cfg = AppConfig()
        cfg.nodeId = "self-node-remembered"
        cfg.discoveryUdpPort = Int64(discoveryPort)
        cfg.enableMdns = false
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let first = CoreServer(cfg, profile: defaultRuntimeProfile())
        first.setConsoleOutputEnabled(false)
        try {
            first.start()

            let packet = DiscoveryPacket()
            packet.deviceId = "peer-remembered"
            packet.name = "Peer Remembered"
            packet.deviceType = "node"
            packet.ip = "10.0.0.28"
            packet.port = 19094
            sendDiscoveryPacket(discoveryPort, packet)

            let device = waitForDevice(first, "peer-remembered")
            @Assert(!device.remembered)

            let remembered = first.rememberDiscoveredDevice("peer-remembered")
            @Assert(remembered.remembered)
        } finally {
            first.stop()
        }

        let second = CoreServer(cfg, profile: defaultRuntimeProfile())
        second.setConsoleOutputEnabled(false)
        try {
            second.start()
            let device = waitForDevice(second, "peer-remembered")
            @Assert(device.remembered)
            @Assert(device.ip, "10.0.0.28")
        } finally {
            second.stop()
        }
    }
}

func sendDiscoveryPacket(port: UInt16, packet: DiscoveryPacket): Unit {
    try (udpSocket = UdpSocket(bindAt: 0)) {
        udpSocket.sendTimeout = Duration.second * 1
        udpSocket.bind()
        udpSocket.sendTo(
            IPSocketAddress("127.0.0.1", port),
            stringToBytes(packet.toJson().toString())
        )
    }
}

func waitForDevice(server: CoreServer, deviceId: String): Device {
    var loops: Int64 = 0
    while (loops < 40) {
        match (server.getDevice(deviceId)) {
            case Some(device) => return device
            case None => ()
        }
        sleep(Duration.millisecond * 50)
        loops += 1
    }
    throw Exception("device timeout: ${deviceId}")
}

func deviceHasCapability(device: Device, target: String): Bool {
    for (capability in device.capability) {
        if (capability == target) {
            return true
        }
    }
    false
}
