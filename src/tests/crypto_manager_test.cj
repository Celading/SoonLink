package soonlnk.tests

import soonlnk.features.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class CryptoManager_test {
    @TestCase
    public func cleanupExpiredSessionsRemovesOnlyExpiredEntries(): Unit {
        let manager = CryptoManager("")
        let expired = manager.createSession()
        let active = manager.createSession()

        expired.expireAt = 100
        active.expireAt = 1000

        let removed = manager.cleanupExpiredSessionsAt(200)

        @Assert(removed, 1)
        @Assert(manager.getSession(expired.id).isNone(), true)
        @Assert(manager.getSession(active.id).isSome(), true)
    }
}
