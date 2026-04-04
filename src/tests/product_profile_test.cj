package soonlnk.tests

import soonlnk.commons.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class ProductProfile_test {
    @TestCase
    public func coreProfileSlicesPreviewCapabilities(): Unit {
        let profile = coreProductProfile()
        @Assert(profile.edition, "core")
        @Assert(!profile.supportsActiveDiscovery)
        @Assert(!profile.supportsPeerTransfer)
        @Assert(!profile.supportsRelay)
        @Assert(!profile.supportsWhitelist)
        @Assert(!profile.supportsFavorites)
        @Assert(profile.supportsMcp)
    }

    @TestCase
    public func coreProfileNormalizesPreviewConfig(): Unit {
        var cfg = AppConfig()
        cfg.securityMode = "encrypted"
        cfg.enableMdns = true
        cfg.relayEnabled = true

        let normalized = normalizeAppConfigForProfile(cfg, coreProductProfile())
        @Assert(normalized.securityMode, "plain")
        @Assert(!normalized.enableMdns)
        @Assert(!normalized.relayEnabled)
    }

    @TestCase
    public func fullProfileKeepsAdvancedCapabilities(): Unit {
        let profile = fullProductProfile()
        @Assert(profile.edition, "full")
        @Assert(profile.supportsActiveDiscovery)
        @Assert(profile.supportsPeerTransfer)
        @Assert(profile.supportsRelay)
        @Assert(profile.supportsWhitelist)
        @Assert(profile.supportsFavorites)
        @Assert(profile.supportsMcp)
    }

    @TestCase
    public func runtimeIdentityHelpersPreferPublicNamesAndStableFallbacks(): Unit {
        @Assert(resolveRuntimeDisplayName(fullProductProfile()), "SoonLink Full")
        @Assert(resolveRuntimeDisplayName(proProductProfile()), "SuLink")
        @Assert(resolveRuntimeDisplayName(coreProductProfile()), "SoonLink")
        @Assert(resolveProductVersion(""), "0.5.17")
        @Assert(resolveTechnicalPackageName(""), "soonlnk")
    }
}
