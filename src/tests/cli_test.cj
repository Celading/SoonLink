package soonlnk.tests

import soonlnk.commons.*
import soonlnk.product.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class Cli_test {
    @TestCase
    public func flagsOnlyStillResolveToServe(): Unit {
        let argv = Array<String>(3, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "--port"
        argv[2] = "9090"

        let action = resolveCliAction(argv)
        @Assert(action.command, "serve")
        @Assert(action.effectiveCommandLine.size, 3)
        @Assert(action.effectiveCommandLine[1], "--port")
    }

    @TestCase
    public func explicitServeStripsSubcommand(): Unit {
        let argv = Array<String>(4, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "serve"
        argv[2] = "--port"
        argv[3] = "9091"

        let action = resolveCliAction(argv)
        @Assert(action.command, "serve")
        @Assert(action.effectiveCommandLine.size, 3)
        @Assert(action.effectiveCommandLine[1], "--port")
        @Assert(action.effectiveCommandLine[2], "9091")
    }

    @TestCase
    public func versionPayloadIncludesNameAndVersion(): Unit {
        let payload = buildVersionPayload(defaultRuntimeProfile())
        @Assert(parseJsonString(payload, "name") ?? "", "SoonLink")
        @Assert((parseJsonString(payload, "version") ?? "").size > 0)
    }

    @TestCase
    public func capabilitiesPayloadReflectsPublicSlice(): Unit {
        let payload = buildCapabilitiesPayload(defaultRuntimeProfile())
        @Assert(parseJsonString(payload, "relay") ?? "", "false")
        @Assert(parseJsonString(payload, "activeDiscovery") ?? "", "true")
        @Assert(parseJsonString(payload, "mdnsDiscovery") ?? "", "false")
        @Assert(payload.contains("\"relay\":false"))
        @Assert(payload.contains("\"activeDiscovery\":true"))
        @Assert(payload.contains("\"udp-discovery-only\""))
    }

    @TestCase
    public func configPayloadNormalizesPublicRuntimeFlags(): Unit {
        var cfg = AppConfig()
        cfg.nodeId = "public-node"
        cfg.securityMode = "encrypted"
        cfg.enableMdns = true
        cfg.relayEnabled = true
        cfg.discoveryUdpPort = 19190
        cfg.discoveryHeartbeatSeconds = 45
        cfg.discoveryAdvertiseIp = "192.168.1.23"
        cfg.discoveryBroadcastEnabled = true
        cfg.localRootDir = "/tmp/data"

        let payload = buildConfigPayload(cfg, defaultRuntimeProfile())
        @Assert(parseJsonString(payload, "nodeId") ?? "", "public-node")
        @Assert(parseJsonString(payload, "securityMode") ?? "", "plain")
        @Assert(payload.contains("\"discoveryUdpPort\":19190"))
        @Assert(payload.contains("\"discoveryHeartbeatSeconds\":45"))
        @Assert(parseJsonString(payload, "discoveryAdvertiseIp") ?? "", "192.168.1.23")
        @Assert(payload.contains("\"enableMdns\":false"))
        @Assert(payload.contains("\"discoveryBroadcastEnabled\":true"))
        @Assert(payload.contains("\"relayEnabled\":false"))
        @Assert(parseJsonString(payload, "rootDir") ?? "", "/tmp/data")
    }

    @TestCase
    public func helpFlagResolvesToHelpCommand(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "--help"

        let action = resolveCliAction(argv)
        @Assert(action.command, "help")
        let help = renderCliHelp()
        @Assert(help.contains("soonlnk serve"))
        @Assert(help.contains("--node-id"))
        @Assert(help.contains("--discovery-port"))
        @Assert(help.contains("--advertise-ip"))
        @Assert(help.contains("--enable-discovery-broadcast"))
        @Assert(help.contains("--disable-discovery-broadcast"))
        @Assert(help.contains("remember-device"))
        @Assert(help.contains("--scheme"))
        @Assert(help.contains("--base-path"))
    }

    @TestCase
    public func statusSubcommandResolvesAndStripsArgs(): Unit {
        let argv = Array<String>(4, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "status"
        argv[2] = "--config"
        argv[3] = "./config/custom.toml"

        let action = resolveCliAction(argv)
        @Assert(action.command, "status")
        @Assert(action.effectiveCommandLine.size, 3)
        @Assert(action.effectiveCommandLine[1], "--config")
    }

    @TestCase
    public func statusPayloadExposesPassiveDiscoverySummaryAndRegisterCommand(): Unit {
        let scope = testTempToken("soonlink_public_status")
        var cfg = AppConfig()
        cfg.nodeId = "public-status-node"
        cfg.localRootDir = "/tmp/${scope}"
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"
        cfg.discoveryAdvertiseIp = "192.168.1.23"
        cfg.discoveryBroadcastEnabled = true
        cfg.enableMdns = true
        cfg.webPort = 18081

        let runtime = AutomationRuntime(cfg, profile: defaultRuntimeProfile())
        try {
            runtime.start()
            let payload = buildStatusPayload(runtime)
            @Assert(payload.contains("\"discovery\":"))
            @Assert(payload.contains("\"mode\":\"active\""))
            @Assert(payload.contains("\"supportsActiveDiscovery\":true"))
            @Assert(payload.contains("\"supportsMdnsDiscovery\":false"))
            @Assert(payload.contains("\"discoverable\":true"))
            @Assert(payload.contains("\"channels\":[\"udp-broadcast\"]"))
            @Assert(payload.contains("\"rememberRequiresConfirmation\":true"))
            @Assert(payload.contains("\"effectiveAdvertiseIp\":\"192.168.1.23\""))
            @Assert(payload.contains("\"localEndpoint\":\"192.168.1.23:18081\""))
            @Assert(payload.contains("\"registerDeviceCommand\":\"soonlnk register-device --id public-status-node --ip 192.168.1.23 --port 18081 --connector soonlink-http --scheme http\""))
        } finally {
            runtime.stop()
        }
    }

    @TestCase
    public func mcpSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "mcp"

        let action = resolveCliAction(argv)
        @Assert(action.command, "mcp")
    }

    @TestCase
    public func connectorsSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "connectors"

        let action = resolveCliAction(argv)
        @Assert(action.command, "connectors")
    }

    @TestCase
    public func registerDeviceSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "register-device"

        let action = resolveCliAction(argv)
        @Assert(action.command, "register-device")
    }

    @TestCase
    public func removeDeviceSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "remove-device"

        let action = resolveCliAction(argv)
        @Assert(action.command, "remove-device")
    }

    @TestCase
    public func rememberDeviceSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "remember-device"

        let action = resolveCliAction(argv)
        @Assert(action.command, "remember-device")
    }

    @TestCase
    public func trustDeviceSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "trust-device"

        let action = resolveCliAction(argv)
        @Assert(action.command, "trust-device")
    }

    @TestCase
    public func pairDevicePinSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "pair-device-pin"

        let action = resolveCliAction(argv)
        @Assert(action.command, "pair-device-pin")
    }

    @TestCase
    public func confirmDevicePinSubcommandResolves(): Unit {
        let argv = Array<String>(2, repeat: "")
        argv[0] = "soonlnk"
        argv[1] = "confirm-device-pin"

        let action = resolveCliAction(argv)
        @Assert(action.command, "confirm-device-pin")
    }
}
