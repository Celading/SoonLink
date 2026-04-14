package soonlnk.tests

import soonlnk.commons.*
import soonlnk.product.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class RuntimeIdentity_test {
    @TestCase
    public func buildProductUsesCurrentRuntimeIdentity(): Unit {
        let profile = currentRuntimeProfile()
        let product = buildProduct(AppConfig())
        @Assert(product.name(), profile.productName)
    }

    @TestCase
    public func selectDiscoveryAdvertiseIpPrefersLanIpv4OverLoopback(): Unit {
        let selected = selectDiscoveryAdvertiseIp("", ["127.0.0.1", "192.168.1.10"])
        @Assert(selected, "192.168.1.10")
    }

    @TestCase
    public func selectDiscoveryAdvertiseIpKeepsExplicitOverride(): Unit {
        let selected = selectDiscoveryAdvertiseIp("10.0.0.9", ["127.0.0.1", "192.168.1.10"])
        @Assert(selected, "10.0.0.9")
    }

    @TestCase
    public func directedBroadcastOnlyTargetsLanIpv4Ranges(): Unit {
        @Assert(deriveDirectedBroadcast("192.168.1.10"), "192.168.1.255")
        @Assert(deriveDirectedBroadcast("8.8.8.8"), "")
        @Assert(deriveDirectedBroadcast("127.0.0.1"), "")
    }
}
