package soonlnk.commons

import std.collection.HashMap
import std.sync.Mutex
import std.random.Random
import std.unicode.*
import JinguiSSL.jinguissl.contract.{contractChacha20Poly1305Encrypt, contractChacha20Poly1305Decrypt}

public enum SecurityMode {
    | Plain
    | Encrypted
}

func isPlain(mode: SecurityMode): Bool {
    match (mode) {
        case Plain => true
        case _ => false
    }
}

public func securityModeToString(mode: SecurityMode): String {
    match (mode) {
        case Plain => "plain"
        case Encrypted => "encrypted"
    }
}

public func securityModeFromString(raw: String): SecurityMode {
    if (raw.toLower() == "encrypted") {
        return Encrypted
    }
    Plain
}

public interface HandshakeAdapter {
    func beginHandshake(peerId: String): String
    func verifyHandshake(token: String): Bool
}

public interface PayloadProtectionProvider {
    func protect(payload: Array<UInt8>): Array<UInt8>
    func unprotect(payload: Array<UInt8>): Array<UInt8>
    func describe(): String
}

public class DefaultHandshakeAdapter <: HandshakeAdapter {
    let mutex: Mutex = Mutex()
    var activeTokens: HashMap<String, Int64> = HashMap<String, Int64>()

    public init() {}

    public func beginHandshake(peerId: String): String {
        let token = "hs-v1-${randomToken(32)}"
        synchronized(mutex) {
            activeTokens.add(token, currentTimestamp() + 300)
        }
        token
    }

    public func verifyHandshake(token: String): Bool {
        synchronized(mutex) {
            if (let Some(expireAt) <- activeTokens.get(token)) {
                if (currentTimestamp() <= expireAt) {
                    return true
                }
                activeTokens.remove(token)
            }
        }
        false
    }
}

public class FailClosedPayloadProtectionProvider <: PayloadProtectionProvider {
    public init() {}

    public func protect(payload: Array<UInt8>): Array<UInt8> {
        throw Exception("Encrypted mode requires a real payload protection provider")
    }

    public func unprotect(payload: Array<UInt8>): Array<UInt8> {
        throw Exception("Encrypted mode requires a real payload protection provider")
    }

    public func describe(): String {
        "fail-closed"
    }
}

public class JinguiSslContractPayloadProvider <: PayloadProtectionProvider {
    let key: Array<UInt8>

    public init(key: Array<UInt8>) {
        if (key.size != 32) {
            throw Exception("JinguiSSL contract ChaCha20-Poly1305 requires a 32-byte key")
        }
        this.key = key.clone()
    }

    public func protect(payload: Array<UInt8>): Array<UInt8> {
        let nonce = randomBytes(12)
        let aad = "soonlink-security-channel-v1".toArray()
        let (ciphertext, tag) = contractChacha20Poly1305Encrypt(key, nonce, payload, aad: aad)
        let out = Array<UInt8>(nonce.size + tag.size + ciphertext.size, repeat: 0)
        var index: Int64 = 0
        for (b in nonce) {
            out[index] = b
            index += 1
        }
        for (b in tag) {
            out[index] = b
            index += 1
        }
        for (b in ciphertext) {
            out[index] = b
            index += 1
        }
        out
    }

    public func unprotect(payload: Array<UInt8>): Array<UInt8> {
        if (payload.size < 28) {
            throw Exception("Encrypted payload is too short")
        }
        let nonce = Array<UInt8>(12, repeat: 0)
        let tag = Array<UInt8>(16, repeat: 0)
        let ciphertext = Array<UInt8>(payload.size - 28, repeat: 0)
        for (i in 0..12) {
            nonce[i] = payload[i]
        }
        for (i in 0..16) {
            tag[i] = payload[12 + i]
        }
        for (i in 0..ciphertext.size) {
            ciphertext[i] = payload[28 + i]
        }
        let aad = "soonlink-security-channel-v1".toArray()
        contractChacha20Poly1305Decrypt(key, nonce, ciphertext, tag, aad: aad)
    }

    public func describe(): String {
        "jinguissl-contract-chacha20-poly1305"
    }
}

public class SecurityChannel {
    let mutex: Mutex = Mutex()
    var mode: SecurityMode = Plain
    var handshakeAdapter: HandshakeAdapter = DefaultHandshakeAdapter()
    var payloadProvider: PayloadProtectionProvider = FailClosedPayloadProtectionProvider()

    public init() {}

    public init(mode: SecurityMode) {
        this.mode = mode
    }

    public init(mode: SecurityMode, payloadProvider: PayloadProtectionProvider) {
        this.mode = mode
        this.payloadProvider = payloadProvider
    }

    public func setMode(raw: String): SecurityMode {
        synchronized(mutex) {
            mode = securityModeFromString(raw)
            mode
        }
    }

    public func getMode(): SecurityMode {
        synchronized(mutex) { mode }
    }

    public func getModeString(): String {
        securityModeToString(getMode())
    }

    public func setHandshakeAdapter(adapter: HandshakeAdapter): Unit {
        synchronized(mutex) {
            handshakeAdapter = adapter
        }
    }

    public func setPayloadProtectionProvider(provider: PayloadProtectionProvider): Unit {
        synchronized(mutex) {
            payloadProvider = provider
        }
    }

    public func getPayloadProtectionProviderDescription(): String {
        synchronized(mutex) {
            payloadProvider.describe()
        }
    }

    public func beginHandshake(peerId: String): String {
        synchronized(mutex) {
            if (isPlain(mode)) {
                return "plain"
            }
            handshakeAdapter.beginHandshake(peerId)
        }
    }

    public func verifyHandshake(token: String): Bool {
        synchronized(mutex) {
            if (isPlain(mode)) {
                return true
            }
            handshakeAdapter.verifyHandshake(token)
        }
    }

    public func protectPayload(payload: Array<UInt8>): Array<UInt8> {
        if (isPlain(getMode())) {
            return payload
        }
        synchronized(mutex) {
            payloadProvider.protect(payload)
        }
    }

    public func unprotectPayload(payload: Array<UInt8>): Array<UInt8> {
        if (isPlain(getMode())) {
            return payload
        }
        synchronized(mutex) {
            payloadProvider.unprotect(payload)
        }
    }
}

public func payloadProtectionProviderFromEncryptionKey(raw: String): PayloadProtectionProvider {
    let bytes = stringToBytes(raw)
    if (bytes.size < 32) {
        return FailClosedPayloadProtectionProvider()
    }
    let key = Array<UInt8>(32, repeat: 0)
    for (i in 0..32) {
        key[i] = bytes[i]
    }
    JinguiSslContractPayloadProvider(key)
}

func randomToken(length: Int64): String {
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

func randomBytes(length: Int64): Array<UInt8> {
    let r = Random()
    let out = Array<UInt8>(length, repeat: 0)
    for (i in 0..length) {
        var raw = r.nextInt64()
        if (raw < 0) { raw = -raw }
        out[i] = UInt8(raw % 256)
    }
    out
}
