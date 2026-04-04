package soonlnk.commons

import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.sync.Mutex
import std.unicode.*

public class MemoryFavoriteStore <: FavoriteStore {
    var entries: ArrayList<FavoriteEntry> = ArrayList<FavoriteEntry>()
    let mutex: Mutex = Mutex()

    public init() {}

    public func mode(): String { "cache" }

    public func load(): ArrayList<FavoriteEntry> {
        let out = ArrayList<FavoriteEntry>()
        synchronized(mutex) {
            for (entry in entries) {
                out.add(entry)
            }
        }
        out
    }

    public func save(next: ArrayList<FavoriteEntry>): Unit {
        synchronized(mutex) {
            entries = ArrayList<FavoriteEntry>()
            for (entry in next) {
                entries.add(entry)
            }
        }
    }
}

public class TomlFavoriteStore <: FavoriteStore {
    let filePath: String
    let store: TomlConfigStore

    public init(filePath: String) {
        this.filePath = filePath
        this.store = TomlConfigStore(filePath)
    }

    public func mode(): String { "toml" }

    public func load(): ArrayList<FavoriteEntry> {
        let values = store.load()
        let out = ArrayList<FavoriteEntry>()
        var index: Int64 = 0
        while (true) {
            let key = "favorite_${index}"
            var raw = ""
            var found = false
            match (values.get(key)) {
                case Some(v) =>
                    raw = v
                    found = true
                case None => ()
            }
            if (!found) { break }
            if (raw.size == 0) {
                index += 1
                continue
            }
            match (parseFavoriteLine(raw)) {
                case Some(entry) => out.add(entry)
                case None => ()
            }
            index += 1
        }
        out
    }

    public func save(entries: ArrayList<FavoriteEntry>): Unit {
        let values = HashMap<String, String>()
        var index: Int64 = 0
        for (entry in entries) {
            values.add("favorite_${index}", encodeFavoriteLine(entry))
            index += 1
        }
        store.save(values)
    }
}

func parseFavoriteLine(raw: String): ?FavoriteEntry {
    let parts = splitByChar(raw, r'|')
    if (parts.size < 4) {
        return None
    }

    let entry = FavoriteEntry()
    entry.deviceId = unescapePipe(parts[0])
    entry.path = unescapePipe(parts[1])
    entry.name = unescapePipe(parts[2])
    try {
        entry.createdAt = Int64.parse(parts[3])
    } catch (_: Exception) {
        entry.createdAt = currentTimestamp()
    }

    if (entry.deviceId.size == 0 || entry.path.size == 0) {
        return None
    }
    Some(entry)
}

func encodeFavoriteLine(entry: FavoriteEntry): String {
    "${escapePipe(entry.deviceId)}|${escapePipe(entry.path)}|${escapePipe(entry.name)}|${entry.createdAt}"
}

func escapePipe(raw: String): String {
    strReplace(strReplace(raw, "\\", "\\\\"), "|", "\\|")
}

func unescapePipe(raw: String): String {
    var out = ""
    let runes = raw.toRuneArray()
    var escaped = false
    for (ch in runes) {
        if (escaped) {
            out += ch.toString()
            escaped = false
            continue
        }
        if (ch == r'\\') {
            escaped = true
            continue
        }
        out += ch.toString()
    }
    out
}

func splitByChar(raw: String, sep: Rune): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    var escaped = false
    for (ch in raw.toRuneArray()) {
        if (escaped) {
            current += ch.toString()
            escaped = false
            continue
        }
        if (ch == r'\\') {
            escaped = true
            continue
        }
        if (ch == sep) {
            out.add(current)
            current = ""
            continue
        }
        current += ch.toString()
    }
    out.add(current)
    out
}
