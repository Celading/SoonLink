package soonlnk.commons

import std.collection.HashMap
import std.random.Random
import std.sync.Mutex
import std.unicode.*

public struct AuthDescriptor {
    public var provider: String = "admin-auth"
    public var supportsPassword: Bool = true
    public var passwordConfigured: Bool = false
    public var capabilities: Array<String> = Array<String>(0, repeat: "")

    public init() {}
}

public interface AuthProvider {
    func name(): String
    func descriptor(): AuthDescriptor
    func verifyPassword(password: String): Bool
    func issueSessionToken(): String
    func verifySessionToken(token: String): Bool
    func revokeSessionToken(token: String): Unit
    func verifyBearerToken(token: String): Bool
    func sessionTtlSeconds(): Int64
}

public class CorePlaceholderAuthProvider <: AuthProvider {
    let profile: RuntimeProfile
    let adminPassword: String
    let adminBearerToken: String
    let ttlSeconds: Int64
    let mutex: Mutex = Mutex()
    var sessionTokens: HashMap<String, Int64> = HashMap<String, Int64>()

    public init() {
        this.profile = defaultRuntimeProfile()
        this.adminPassword = ""
        this.adminBearerToken = ""
        this.ttlSeconds = 43200
    }

    public init(profile: RuntimeProfile) {
        this.profile = profile
        this.adminPassword = ""
        this.adminBearerToken = ""
        this.ttlSeconds = 43200
    }

    public init(profile: RuntimeProfile, adminPassword: String, adminBearerToken: String, adminSessionTtlSeconds: Int64) {
        this.profile = profile
        this.adminPassword = adminPassword.trimAscii()
        this.adminBearerToken = adminBearerToken.trimAscii()
        this.ttlSeconds = if (adminSessionTtlSeconds > 0) { adminSessionTtlSeconds } else { 43200 }
    }

    public func name(): String {
        "admin-auth"
    }

    public func descriptor(): AuthDescriptor {
        var out = AuthDescriptor()
        out.provider = name()
        out.supportsPassword = true
        out.passwordConfigured = authConfigured()
        if (profile.supportsPeerTransfer) {
            out.capabilities = ["login-entry", "admin-session-token", "admin-bearer-token", "local-trust-fallback", "peer-transfer", "relay", "favorites"]
        } else if (profile.supportsRelay) {
            out.capabilities = ["login-entry", "admin-session-token", "admin-bearer-token", "local-trust-fallback", "udp-discovery", "manual-remember", "relay-cache", "text-record-cache"]
        } else if (profile.supportsActiveDiscovery) {
            out.capabilities = ["login-entry", "admin-session-token", "admin-bearer-token", "local-trust-fallback", "udp-discovery", "manual-remember"]
        } else {
            out.capabilities = ["login-entry", "admin-session-token", "admin-bearer-token", "local-trust-fallback", "passive-discovery-only"]
        }
        out
    }

    public func verifyPassword(password: String): Bool {
        if (adminPassword.size == 0) {
            return false
        }
        password == adminPassword
    }

    public func issueSessionToken(): String {
        let token = "sl-admin-v1-${randomAuthToken(64)}"
        synchronized(mutex) {
            sessionTokens.add(token, currentTimestamp() + ttlSeconds)
        }
        token
    }

    public func verifySessionToken(token: String): Bool {
        let normalized = token.trimAscii()
        if (normalized.size == 0) {
            return false
        }
        synchronized(mutex) {
            if (let Some(expiresAt) <- sessionTokens.get(normalized)) {
                if (currentTimestamp() <= expiresAt) {
                    return true
                }
                let _ = sessionTokens.remove(normalized)
            }
        }
        false
    }

    public func revokeSessionToken(token: String): Unit {
        let normalized = token.trimAscii()
        if (normalized.size == 0) {
            return
        }
        synchronized(mutex) {
            let _ = sessionTokens.remove(normalized)
        }
    }

    public func verifyBearerToken(token: String): Bool {
        if (adminBearerToken.size == 0) {
            return false
        }
        token.trimAscii() == adminBearerToken
    }

    public func sessionTtlSeconds(): Int64 {
        ttlSeconds
    }

    func authConfigured(): Bool {
        adminPassword.size > 0 || adminBearerToken.size > 0
    }
}

func randomAuthToken(length: Int64): String {
    let chars = "0123456789abcdef".toRuneArray()
    let r = Random()
    var out = ""
    var i: Int64 = 0
    while (i < length) {
        var raw = r.nextInt64()
        if (raw < 0) { raw = -raw }
        out += chars[raw % chars.size].toString()
        i += 1
    }
    out
}

public struct CryptoDescriptor {
    public var provider: String = "placeholder"
    public var mode: String = "plain"

    public init() {}
}

public interface CryptoProvider {
    func name(): String
    func descriptor(): CryptoDescriptor
}

public class CorePlaceholderCryptoProvider <: CryptoProvider {
    let profile: RuntimeProfile

    public init() {
        this.profile = defaultRuntimeProfile()
    }

    public init(profile: RuntimeProfile) {
        this.profile = profile
    }

    public func name(): String {
        "placeholder"
    }

    public func descriptor(): CryptoDescriptor {
        var out = CryptoDescriptor()
        out.provider = name()
        out.mode = if (profile.supportsAdvancedSecurity) {
            "encrypted"
        } else if (profile.supportsPeerTransfer) {
            "lite"
        } else {
            "plain"
        }
        out
    }
}
