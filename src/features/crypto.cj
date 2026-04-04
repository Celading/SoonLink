package soonlnk.features

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.time.MonoTime
import std.random.Random
import soonlnk.commons.*

public class CryptoSession {
    public var id: String = ""
    public var createdAt: Int64 = 0
    public var expireAt: Int64 = 0

    public init(id: String) {
        this.id = id
        this.createdAt = currentTimestamp()
        this.expireAt = this.createdAt + 86400
    }
}

public class CryptoManager {
    var sessions: HashMap<String, CryptoSession> = HashMap<String, CryptoSession>()
    let mutex: Mutex = Mutex()

    public init(_encryptionKey: String) {}

    public func start(): Unit {
        spawn { cleanupLoop() }
    }

    public func createSession(): CryptoSession {
        let id = generateId()
        let session = CryptoSession(id)
        synchronized(mutex) {
            sessions.add(id, session)
        }
        session
    }

    public func getSession(sessionId: String): ?CryptoSession {
        synchronized(mutex) {
            sessions.get(sessionId)
        }
    }

    func cleanupLoop(): Unit {
        while (true) {
            sleep(Duration.minute * 10)
            let now = currentTimestamp()
            synchronized(mutex) {
                let expired = ArrayList<String>()
                for ((id, session) in sessions) {
                    if (now > session.expireAt) {
                        expired.add(id)
                    }
                }
                for (id in expired) {
                    sessions.remove(id)
                }
            }
        }
    }
}

public func generateId(): String {
    let r = Random()
    var id = ""
    let chars = "0123456789abcdef"
    let charArray = chars.toRuneArray()
    for (_ in 0..32) {
        var raw = r.nextInt64()
        if (raw < 0) { raw = -raw }
        let idx = raw % 16
        id += charArray[idx].toString()
    }
    id
}
