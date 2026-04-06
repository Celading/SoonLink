package soonlnk.tests

import soonlnk.commons.*
import soonlnk.master.*
import soonlnk.product.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class DeviceTrust_test {
    @TestCase
    public func manualDeviceStartsUnknownAndPinPairingPromotesToTrusted(): Unit {
        let scope = testTempToken("soonlink_trust_pin")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}_root"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let server = CoreServer(cfg, profile: coreProductProfile())
        let record = DeviceRegistryRecord()
        record.id = "edge-node"
        record.name = "Edge Node"
        record.deviceType = "remote"
        record.ip = "10.0.0.44"
        record.port = 19090

        let device = server.upsertManagedDeviceRecord(record)
        @Assert(deviceTrustStateToString(device.trustState), "unknown")

        let session = server.startPinPairing("edge-node")
        @Assert(session.deviceId, "edge-node")
        @Assert(session.pin.size, 6)

        let paired = server.confirmPinPairing("edge-node", session.pin)
        @Assert(deviceTrustStateToString(paired.trustState), "trusted")
        @Assert(paired.trustSource, "pin")
    }

    @TestCase
    public func untrustedRemoteDeviceIsRejectedBeforeTransferStarts(): Unit {
        let scope = testTempToken("soonlink_trust_transfer")
        let rootDir = "/tmp/${scope}_root"
        let fileMgr = LocalFileMgr()
        fileMgr.ensureDir(rootDir + "/docs")
        fileMgr.writeText(rootDir + "/docs/readme.txt", "hello", false)

        var cfg = AppConfig()
        cfg.localRootDir = rootDir
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let server = CoreServer(cfg, profile: coreProductProfile())
        let record = DeviceRegistryRecord()
        record.id = "peer-node"
        record.name = "Peer Node"
        record.deviceType = "remote"
        record.ip = "10.0.0.66"
        record.port = 19091

        try {
            server.start()
            server.upsertManagedDeviceRecord(record)

            var rejected = false
            try {
                let _ = server.createTransferTask("local", "peer-node", "/docs/readme.txt", "/incoming")
            } catch (e: Exception) {
                rejected = e.message.contains("尚未授信")
            }
            @Assert(rejected)

            let trusted = server.setDeviceTrustState("peer-node", "trusted", source: "test")
            @Assert(deviceTrustStateToString(trusted.trustState), "trusted")
        } finally {
            server.stop()
        }
    }

    @TestCase
    public func blockedDeviceCannotEnterWhitelist(): Unit {
        let scope = testTempToken("soonlink_trust_whitelist")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}_root"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"
        cfg.whitelistTomlFile = "/tmp/${scope}_whitelist.toml"

        let server = CoreServer(cfg, profile: capabilityCompleteTestProfile())
        let record = DeviceRegistryRecord()
        record.id = "relay-node"
        record.name = "Relay Node"
        record.deviceType = "remote"
        record.ip = "10.0.0.77"
        record.port = 19100

        let _ = server.upsertManagedDeviceRecord(record)
        let _blocked = server.setDeviceTrustState("relay-node", "blocked", source: "test")

        var rejected = false
        try {
            let _ = server.upsertWhitelistRule("*", "relay-node", true)
        } catch (e: Exception) {
            rejected = e.message.contains("已拉黑")
        }
        @Assert(rejected)
    }
}
