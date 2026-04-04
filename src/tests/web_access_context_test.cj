package soonlnk.tests

import soonlnk.master.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class WebAccessContext_test {
    @TestCase
    public func loopbackIsAdminByDefault(): Unit {
        let access = resolveWebAccessContext("127.0.0.1", "", false)
        @Assert(access.isLocalAdmin)
        @Assert(access.accessMode, "local-admin")
        @Assert(access.themeVariant, "admin")
    }

    @TestCase
    public func lanAddressIsRemote(): Unit {
        let access = resolveWebAccessContext("192.168.1.8", "", false)
        @Assert(!access.isLocalAdmin)
        @Assert(access.accessMode, "remote")
        @Assert(access.themeVariant, "remote")
    }

    @TestCase
    public func forwardedHeaderRespectsTrustSetting(): Unit {
        let untrusted = resolveWebAccessContext("10.0.0.9", "127.0.0.1", false)
        @Assert(!untrusted.isLocalAdmin)

        let trusted = resolveWebAccessContext("10.0.0.9", "127.0.0.1, 10.0.0.7", true)
        @Assert(trusted.isLocalAdmin)
        @Assert(trusted.resolvedIP, "127.0.0.1")
    }
}
