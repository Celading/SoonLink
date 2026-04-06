package soonlnk.tests

import soonlnk.commons.*
import soonlnk.product.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class Mcp_test {
    @TestCase
    public func initializeRequestReturnsProtocolAndServerInfo(): Unit {
        let scope = testTempToken("soonlink_mcp_initialize")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let runtime = AutomationRuntime(cfg, profile: coreProductProfile())
        try {
            runtime.start()
            let response = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
            ) ?? ""
            @Assert(response.contains("\"protocolVersion\":\"2024-11-05\""))
            @Assert(response.contains("\"SoonLink MCP\""))
        } finally {
            runtime.stop()
        }
    }

    @TestCase
    public func toolsListIncludesSoonLinkCoreTools(): Unit {
        let scope = testTempToken("soonlink_mcp_tools")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let runtime = AutomationRuntime(cfg, profile: coreProductProfile())
        try {
            runtime.start()
            let response = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":\"tools-1\",\"method\":\"tools/list\",\"params\":{}}"
            ) ?? ""
            @Assert(response.contains("\"soonlink_list_dir\""))
            @Assert(response.contains("\"soonlink_create_transfer_task\""))
            @Assert(response.contains("\"soonlink_list_connectors\""))
            @Assert(response.contains("\"soonlink_register_device\""))
            @Assert(response.contains("\"soonlink_remove_device\""))
            @Assert(response.contains("\"soonlink_set_device_trust\""))
            @Assert(response.contains("\"soonlink_start_device_pin_pairing\""))
            @Assert(response.contains("\"soonlink_confirm_device_pin_pairing\""))
        } finally {
            runtime.stop()
        }
    }

    @TestCase
    public func listDirToolCallReturnsLocalEntries(): Unit {
        let scope = testTempToken("soonlink_mcp_list_dir")
        let rootDir = "/tmp/${scope}"
        let fileMgr = LocalFileMgr()
        fileMgr.ensureDir(rootDir + "/docs")
        fileMgr.writeText(rootDir + "/docs/readme.txt", "hello", false)

        var cfg = AppConfig()
        cfg.localRootDir = rootDir
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let runtime = AutomationRuntime(cfg, profile: coreProductProfile())
        try {
            runtime.start()
            let response = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_list_dir\",\"arguments\":{\"device\":\"local\",\"path\":\"/docs\"}}}"
            ) ?? ""
            @Assert(response.contains("\"success\":true"))
            @Assert(response.contains("\"readme.txt\""))
        } finally {
            runtime.stop()
        }
    }

    @TestCase
    public func listConnectorsToolCallReturnsConnectorBindings(): Unit {
        let scope = testTempToken("soonlink_mcp_connectors")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let runtime = AutomationRuntime(cfg, profile: coreProductProfile())
        try {
            runtime.start()
            let response = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_list_connectors\",\"arguments\":{}}}"
            ) ?? ""
            @Assert(response.contains("\"local-fs\""))
            @Assert(response.contains("\"soonlink-http\""))
            @Assert(response.contains("\"driverAvailable\":true"))
        } finally {
            runtime.stop()
        }
    }

    @TestCase
    public func registerAndRemoveDeviceToolsManageEndpoint(): Unit {
        let scope = testTempToken("soonlink_mcp_manage_device")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let runtime = AutomationRuntime(cfg, profile: coreProductProfile())
        try {
            runtime.start()
            let registerResponse = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_register_device\",\"arguments\":{\"deviceId\":\"edge-node\",\"name\":\"Edge Node\",\"deviceType\":\"remote\",\"connectorType\":\"soonlink-http\",\"scheme\":\"tls\",\"basePath\":\"gateway/core/\",\"ip\":\"10.0.0.44\",\"port\":19090}}}"
            ) ?? ""
            @Assert(registerResponse.contains("\"success\":true"))
            @Assert(registerResponse.contains("\"edge-node\""))
            @Assert(registerResponse.contains("\"endpointScheme\":\"https\""))
            @Assert(registerResponse.contains("\"endpointBasePath\":\"/gateway/core\""))

            let removeResponse = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_remove_device\",\"arguments\":{\"deviceId\":\"edge-node\"}}}"
            ) ?? ""
            @Assert(removeResponse.contains("\"success\":true"))
            @Assert(removeResponse.contains("\"deviceId\":\"edge-node\""))
        } finally {
            runtime.stop()
        }
    }

    @TestCase
    public func trustToolsPromoteDeviceViaPin(): Unit {
        let scope = testTempToken("soonlink_mcp_trust")
        var cfg = AppConfig()
        cfg.localRootDir = "/tmp/${scope}"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let runtime = AutomationRuntime(cfg, profile: coreProductProfile())
        try {
            runtime.start()
            let registerResponse = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_register_device\",\"arguments\":{\"deviceId\":\"peer-node\",\"name\":\"Peer Node\",\"deviceType\":\"remote\",\"connectorType\":\"soonlink-http\",\"ip\":\"10.0.0.66\",\"port\":19100}}}"
            ) ?? ""
            @Assert(registerResponse.contains("\"success\":true"))

            let pairingResponse = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_start_device_pin_pairing\",\"arguments\":{\"deviceId\":\"peer-node\"}}}"
            ) ?? ""
            @Assert(pairingResponse.contains("\"success\":true"))
            let pin = parseJsonString(pairingResponse, "pin") ?? ""
            @Assert(pin.size, 6)

            let confirmResponse = dispatchMcpRequest(
                runtime,
                "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"soonlink_confirm_device_pin_pairing\",\"arguments\":{\"deviceId\":\"peer-node\",\"pin\":\"${pin}\"}}}"
            ) ?? ""
            @Assert(confirmResponse.contains("\"success\":true"))
            @Assert(confirmResponse.contains("\"trustState\":\"trusted\""))
        } finally {
            runtime.stop()
        }
    }
}
