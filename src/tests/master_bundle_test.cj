package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class MasterBundle_test {
    @TestCase
    public func coreKeepsMonitorButNotPeerCapability(): Unit {
        let scope = testTempToken("soonlink_test_devices")
        var cfg = AppConfig()
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: coreProductProfile())
        let masters = MasterBundle(server)

        let system = masters.monitor.system().toString()
        @Assert(parseJsonString(system, "os") ?? "", "cangjie")
        @Assert(!server.profile.supportsPeerTransfer)
        @Assert(server.getSecurityMode(), "plain")
    }

    @TestCase
    public func capabilityCompleteProfileKeepsPeerMaster(): Unit {
        let scope = testTempToken("soonlink_test_devices_full")
        var cfg = AppConfig()
        cfg.deviceRegistryFile = "/tmp/${scope}.json"
        cfg.logDir = "/tmp/${scope}_logs"

        let server = CoreServer(cfg, profile: capabilityCompleteTestProfile())
        let masters = MasterBundle(server)
        let mode = masters.peers.updateSecurityMode("encrypted")
        @Assert(mode, "encrypted")

        let token = masters.peers.beginHandshake("peer-master-test")
        @Assert(token.size > 0)
    }
}
