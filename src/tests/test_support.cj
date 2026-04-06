package soonlnk.tests

import soonlnk.commons.*
import soonlnk.product.*
import std.random.Random

func testTempToken(label: String): String {
    let chars = "0123456789abcdef".toRuneArray()
    let random = Random()
    let edition = resolveProductProfile().edition
    var suffix = ""
    for (_ in 0..8) {
        var raw = random.nextInt64()
        if (raw < 0) {
            raw = -raw
        }
        suffix += chars[raw % Int64(chars.size)].toString()
    }
    "${label}_${edition}_${currentTimestamp()}_${suffix}"
}

func testTempPath(label: String): String {
    "/tmp/" + testTempToken(label)
}

func capabilityCompleteTestProfile(): ProductProfile {
    var profile = coreProductProfile()
    profile.supportsActiveDiscovery = true
    profile.supportsPeerTransfer = true
    profile.supportsRelay = true
    profile.supportsWhitelist = true
    profile.supportsFavorites = true
    profile.supportsAdvancedSecurity = true
    profile
}
