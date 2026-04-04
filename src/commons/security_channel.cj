package soonlnk.commons

import std.collection.HashMap
import std.sync.Mutex
import std.random.Random
import std.unicode.*

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

public class DefaultHandshakeAdapter <: HandshakeAdapter {
    let mutex: Mutex = Mutex()
    var activeTokens: HashMap<String, Int64> = HashMap<String, Int64>()

    public init() {}

    public func beginHandshake(peerId: String): String {
        let token = "hs-${peerId}-${randomToken(12)}"
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

public class SecurityChannel {
    let mutex: Mutex = Mutex()
    var mode: SecurityMode = Plain
    var handshakeAdapter: HandshakeAdapter = DefaultHandshakeAdapter()

    public init() {}

    public init(mode: SecurityMode) {
        this.mode = mode
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
        xorPayload(payload)
    }

    public func unprotectPayload(payload: Array<UInt8>): Array<UInt8> {
        if (isPlain(getMode())) {
            return payload
        }
        xorPayload(payload)
    }
}

func xorPayload(payload: Array<UInt8>): Array<UInt8> {
    let result = Array<UInt8>(payload.size, repeat: 0)
    let key = UInt8(0x5A)
    for (i in 0..payload.size) {
        result[i] = payload[i] ^ key
    }
    result
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
