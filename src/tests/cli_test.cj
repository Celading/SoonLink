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
    public func versionPayloadIncludesEditionAndVersion(): Unit {
        let payload = buildVersionPayload(coreProductProfile())
        @Assert(parseJsonString(payload, "edition") ?? "", "core")
        @Assert(parseJsonString(payload, "name") ?? "", "SoonLink")
        @Assert((parseJsonString(payload, "version") ?? "").size > 0)
    }

    @TestCase
    public func capabilitiesPayloadReflectsCoreSlice(): Unit {
        let payload = buildCapabilitiesPayload(coreProductProfile())
        @Assert(parseJsonString(payload, "edition") ?? "", "core")
        @Assert(parseJsonString(payload, "relay") ?? "", "false")
        @Assert(parseJsonString(payload, "activeDiscovery") ?? "", "false")
        @Assert(payload.contains("\"relay\":false"))
        @Assert(payload.contains("\"activeDiscovery\":false"))
        @Assert(payload.contains("\"lite-security\""))
    }

    @TestCase
    public func configPayloadNormalizesCorePreviewFlags(): Unit {
        var cfg = AppConfig()
        cfg.securityMode = "encrypted"
        cfg.enableMdns = true
        cfg.relayEnabled = true
        cfg.localRootDir = "/tmp/data"

        let payload = buildConfigPayload(cfg, coreProductProfile())
        @Assert(parseJsonString(payload, "edition") ?? "", "core")
        @Assert(parseJsonString(payload, "securityMode") ?? "", "plain")
        @Assert(payload.contains("\"enableMdns\":false"))
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
