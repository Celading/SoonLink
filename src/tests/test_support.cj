package soonlnk.tests

import soonlnk.commons.*
import soonlnk.product.*
import std.random.Random

func testTempToken(label: String): String {
    let chars = "0123456789abcdef".toRuneArray()
    let random = Random()
    let runtimeLabel = "runtime"
    var suffix = ""
    for (_ in 0..8) {
        var raw = random.nextInt64()
        if (raw < 0) {
            raw = -raw
        }
        suffix += chars[raw % Int64(chars.size)].toString()
    }
    "${label}_${runtimeLabel}_${currentTimestamp()}_${suffix}"
}

func testTempPath(label: String): String {
    "/tmp/" + testTempToken(label)
}

func featureRichTestRuntime(): RuntimeProfile {
    var profile = defaultRuntimeProfile()
    profile.supportsActiveDiscovery = true
    profile.supportsMdnsDiscovery = true
    profile.supportsPeerTransfer = true
    profile.supportsRelay = true
    profile.supportsWhitelist = true
    profile.supportsFavorites = true
    profile.supportsAdvancedSecurity = true
    profile
}
