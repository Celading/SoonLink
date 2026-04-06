package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
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

        let server = CoreServer(cfg, profile: coreProductProfile())

        let record = DeviceRegistryRecord()
        record.id = "node-x"
        record.name = "Node-X"
        record.deviceType = "remote"
        record.ip = "10.0.0.2"
        record.port = 8088

        let device = server.registerDeviceRecord(record)
        @Assert(device.id, "node-x")
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

        let server = CoreServer(cfg, profile: coreProductProfile())

        let record = DeviceRegistryRecord()
        record.id = "node-y"
        record.name = "Node-Y"
        record.deviceType = "remote"
        record.ip = "10.0.0.3"
        record.port = 18081

        let device = server.registerDeviceRecord(record)
        @Assert(device.connectorType, "soonlink-http")
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

        let server = CoreServer(cfg, profile: coreProductProfile())

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

        let server = CoreServer(cfg, profile: coreProductProfile())

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
}
