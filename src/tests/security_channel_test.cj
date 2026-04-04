package soonlnk.tests

import soonlnk.commons.*
import soonlnk.features.*
import soonlnk.master.*
import soonlnk.product.*
import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class SecurityChannel_test {
    @TestCase
    public func modeSwitchAndHandshake(): Unit {
        let channel = SecurityChannel()
        @Assert(channel.getModeString(), "plain")

        channel.setMode("encrypted")
        @Assert(channel.getModeString(), "encrypted")

        let token = channel.beginHandshake("peer-a")
        @Assert(token.size > 0)
        @Assert(channel.verifyHandshake(token))
        @Assert(!channel.verifyHandshake("bad-token"))
    }

    @TestCase
    public func payloadProtectRoundTrip(): Unit {
        let channel = SecurityChannel(Encrypted)
        let token = channel.beginHandshake("peer-b")
        @Assert(channel.verifyHandshake(token))

        let src = stringToBytes("hello-soonlink")
        let enc = channel.protectPayload(src)
        @Assert(enc.size, src.size)

        let dec = channel.unprotectPayload(enc)
        @Assert(String.fromUtf8(dec), "hello-soonlink")
    }
}
