package soonlnk.tests

import soonlnk.commons.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class RuntimeProfile_test {
    @TestCase
    public func defaultRuntimeKeepsStableCapabilitiesByDefault(): Unit {
        let profile = defaultRuntimeProfile()
        @Assert(defaultRuntimeProfile().productName, "SoonLink")
        @Assert(profile.supportsActiveDiscovery)
        @Assert(!profile.supportsMdnsDiscovery)
        @Assert(!profile.supportsPeerTransfer)
        @Assert(profile.supportsRelay)
        @Assert(!profile.supportsWhitelist)
        @Assert(!profile.supportsFavorites)
        @Assert(profile.supportsMcp)
    }

    @TestCase
    public func defaultRuntimeNormalizesExtendedConfigBackToDefaults(): Unit {
        var cfg = AppConfig()
        cfg.securityMode = "encrypted"
        cfg.enableMdns = true
        cfg.discoveryBroadcastEnabled = true
        cfg.relayEnabled = true

        let normalized = normalizeAppConfigForRuntime(cfg, defaultRuntimeProfile())
        @Assert(normalized.securityMode, "plain")
        @Assert(!normalized.enableMdns)
        @Assert(normalized.discoveryBroadcastEnabled)
        @Assert(normalized.relayEnabled)
    }

    @TestCase
    public func featureRichTestRuntimeCanExerciseExtendedPaths(): Unit {
        let profile = featureRichTestRuntime()
        @Assert(profile.supportsActiveDiscovery)
        @Assert(profile.supportsMdnsDiscovery)
        @Assert(profile.supportsPeerTransfer)
        @Assert(profile.supportsRelay)
        @Assert(profile.supportsWhitelist)
        @Assert(profile.supportsFavorites)
        @Assert(profile.supportsMcp)
    }

    @TestCase
    public func runtimeIdentityHelpersPreferStableNamesAndFallbacks(): Unit {
        @Assert(resolveRuntimeDisplayName(featureRichTestRuntime()), "SoonLink")
        @Assert(resolveRuntimeDisplayName(defaultRuntimeProfile()), "SoonLink")
        @Assert(resolveRuntimeDisplayName(RuntimeProfile()), "SoonLink")
        @Assert(resolveProductVersion(""), "0.5.29")
        @Assert(resolveTechnicalPackageName(""), "soonlnk")
    }
}
