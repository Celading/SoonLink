package soonlnk.commons

public struct AuthDescriptor {
    public var provider: String = "placeholder"
    public var supportsPassword: Bool = true
    public var passwordConfigured: Bool = false
    public var capabilities: Array<String> = Array<String>(0, repeat: "")

    public init() {}
}

public interface AuthProvider {
    func name(): String
    func descriptor(): AuthDescriptor
}

public class CorePlaceholderAuthProvider <: AuthProvider {
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

    public func descriptor(): AuthDescriptor {
        var out = AuthDescriptor()
        out.provider = name()
        out.supportsPassword = true
        out.passwordConfigured = false
        if (profile.supportsPeerTransfer) {
            out.capabilities = ["login-entry", "local-trust-admin", "peer-transfer", "relay", "favorites"]
        } else if (profile.supportsRelay) {
            out.capabilities = ["login-entry", "local-trust-admin", "udp-discovery", "manual-remember", "relay-cache", "text-record-cache"]
        } else if (profile.supportsActiveDiscovery) {
            out.capabilities = ["login-entry", "local-trust-admin", "udp-discovery", "manual-remember"]
        } else {
            out.capabilities = ["login-entry", "local-trust-admin", "passive-discovery-only"]
        }
        out
    }
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
