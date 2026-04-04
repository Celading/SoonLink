package soonlnk.commons

public struct AuthDescriptor {
    public var provider: String = "placeholder"
    public var edition: String = "core"
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
    let profile: ProductProfile

    public init() {
        this.profile = coreProductProfile()
    }

    public init(profile: ProductProfile) {
        this.profile = profile
    }

    public func name(): String {
        if (profile.edition == "pro") {
            return "pro-placeholder"
        }
        if (profile.edition == "full") {
            return "full-placeholder"
        }
        "core-placeholder"
    }

    public func descriptor(): AuthDescriptor {
        var out = AuthDescriptor()
        out.provider = name()
        out.edition = profile.edition
        out.supportsPassword = true
        out.passwordConfigured = false
        if (profile.supportsPeerTransfer) {
            out.capabilities = ["login-entry", "local-trust-admin", "peer-transfer", "relay", "favorites"]
        } else {
            out.capabilities = ["login-entry", "local-trust-admin", "passive-discovery-only"]
        }
        out
    }
}

public struct CryptoDescriptor {
    public var provider: String = "placeholder"
    public var edition: String = "core"
    public var mode: String = "plain"

    public init() {}
}

public interface CryptoProvider {
    func name(): String
    func descriptor(): CryptoDescriptor
}

public class CorePlaceholderCryptoProvider <: CryptoProvider {
    let profile: ProductProfile

    public init() {
        this.profile = coreProductProfile()
    }

    public init(profile: ProductProfile) {
        this.profile = profile
    }

    public func name(): String {
        if (profile.edition == "pro") {
            return "pro-placeholder"
        }
        if (profile.edition == "full") {
            return "full-placeholder"
        }
        "core-placeholder"
    }

    public func descriptor(): CryptoDescriptor {
        var out = CryptoDescriptor()
        out.provider = name()
        out.edition = profile.edition
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
