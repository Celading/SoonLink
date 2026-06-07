package soonlnk.tests

import soonlnk.commons.*
import soonlnk.master.*
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class AuthProvider_test {
    @TestCase
    public func defaultProviderKeepsLocalTrustFallbackUnconfigured(): Unit {
        let provider = CorePlaceholderAuthProvider(defaultRuntimeProfile())
        let descriptor = provider.descriptor()

        @Assert(!descriptor.passwordConfigured)
        @Assert(!provider.verifyPassword("anything"))
        @Assert(!provider.verifyBearerToken("anything"))
    }

    @TestCase
    public func configuredProviderVerifiesPasswordBearerAndSession(): Unit {
        let provider = CorePlaceholderAuthProvider(defaultRuntimeProfile(), "admin-pass", "bearer-token", 60)
        let descriptor = provider.descriptor()

        @Assert(descriptor.passwordConfigured)
        @Assert(provider.verifyPassword("admin-pass"))
        @Assert(!provider.verifyPassword("wrong-pass"))
        @Assert(provider.verifyBearerToken("bearer-token"))
        @Assert(!provider.verifyBearerToken("wrong-token"))

        let session = provider.issueSessionToken()
        @Assert(session.size > 0)
        @Assert(provider.verifySessionToken(session))
        provider.revokeSessionToken(session)
        @Assert(!provider.verifySessionToken(session))
    }

    @TestCase
    public func adminAccessRequiresTokenWhenAuthConfigured(): Unit {
        let access = resolveWebAccessContext("127.0.0.1", "", false)
        let provider = CorePlaceholderAuthProvider(defaultRuntimeProfile(), "admin-pass", "bearer-token", 60)

        let denied = resolveAdminAccessDecision(access, provider, "", "")
        @Assert(!denied.allowed)
        @Assert(denied.statusCode, 401)
        @Assert(denied.code, "ADMIN_AUTH_REQUIRED")

        let bearer = resolveAdminAccessDecision(access, provider, "Bearer bearer-token", "")
        @Assert(bearer.allowed)
        @Assert(bearer.authenticated)
        @Assert(bearer.policy, "bearer_token")

        let session = provider.issueSessionToken()
        let cookie = "foo=bar; soonlink_admin_session=${session}; theme=light"
        let sessionDecision = resolveAdminAccessDecision(access, provider, "", cookie)
        @Assert(sessionDecision.allowed)
        @Assert(sessionDecision.authenticated)
        @Assert(sessionDecision.policy, "admin_session")
    }

    @TestCase
    public func unconfiguredProviderKeepsLocalOnlyCompatibility(): Unit {
        let provider = CorePlaceholderAuthProvider(defaultRuntimeProfile())

        let local = resolveAdminAccessDecision(resolveWebAccessContext("127.0.0.1", "", false), provider, "", "")
        @Assert(local.allowed)
        @Assert(!local.authenticated)
        @Assert(local.policy, "local_trust")

        let remote = resolveAdminAccessDecision(resolveWebAccessContext("192.168.1.8", "", false), provider, "", "")
        @Assert(!remote.allowed)
        @Assert(remote.statusCode, 403)
    }
}
