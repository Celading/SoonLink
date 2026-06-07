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
    public func encryptedModeFailsClosedWithoutProvider(): Unit {
        let channel = SecurityChannel(Encrypted)
        let token = channel.beginHandshake("peer-b")
        @Assert(channel.verifyHandshake(token))

        let src = stringToBytes("hello-soonlink")
        try {
            _ = channel.protectPayload(src)
            @Fail("encrypted mode without provider should fail closed")
        } catch (_: Exception) {}
    }

    @TestCase
    public func payloadProtectRoundTripWithJinguiSslContractProvider(): Unit {
        let provider = payloadProtectionProviderFromEncryptionKey("0123456789abcdef0123456789abcdef")
        let channel = SecurityChannel(Encrypted, provider)

        let src = stringToBytes("hello-soonlink")
        let enc = channel.protectPayload(src)
        @Assert(enc.size, src.size + 28)

        let dec = channel.unprotectPayload(enc)
        @Assert(String.fromUtf8(dec), "hello-soonlink")
    }
}
