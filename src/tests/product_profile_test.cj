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
        @Assert(defaultProductProfile().edition, "core")
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
    public func capabilityCompleteProfileKeepsAdvancedCapabilities(): Unit {
        let profile = capabilityCompleteTestProfile()
        @Assert(profile.edition, "core")
        @Assert(profile.supportsActiveDiscovery)
        @Assert(profile.supportsPeerTransfer)
        @Assert(profile.supportsRelay)
        @Assert(profile.supportsWhitelist)
        @Assert(profile.supportsFavorites)
        @Assert(profile.supportsMcp)
    }

    @TestCase
    public func runtimeIdentityHelpersPreferPublicNamesAndStableFallbacks(): Unit {
        @Assert(resolveRuntimeDisplayName(capabilityCompleteTestProfile()), "SoonLink")
        @Assert(resolveRuntimeDisplayName(coreProductProfile()), "SoonLink")
        @Assert(resolveRuntimeDisplayName(ProductProfile()), "SoonLink")
        @Assert(resolveProductVersion(""), "0.5.21")
        @Assert(resolveTechnicalPackageName(""), "soonlnk")
    }
}
