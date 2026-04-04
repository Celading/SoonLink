package soonlnk.commons

import std.collection.ArrayList

public class JsonEntry {
    public let key: String
    public let raw: String

    public init(key: String, raw: String) {
        this.key = key
        this.raw = raw
    }
}

public class JsonObject {
    var entries: ArrayList<JsonEntry> = ArrayList<JsonEntry>()

    public init() {}

    public func put(key: String, value: String): JsonObject {
        entries.add(JsonEntry(key, "\"${escapeJsonString(value)}\""))
        this
    }

    public func putInt(key: String, value: Int64): JsonObject {
        entries.add(JsonEntry(key, "${value}"))
        this
    }

    public func putUInt(key: String, value: UInt64): JsonObject {
        entries.add(JsonEntry(key, "${value}"))
        this
    }

    public func putFloat(key: String, value: Float64): JsonObject {
        entries.add(JsonEntry(key, "${value}"))
        this
    }

    public func putBool(key: String, value: Bool): JsonObject {
        let v = if (value) { "true" } else { "false" }
        entries.add(JsonEntry(key, v))
        this
    }

    public func putNull(key: String): JsonObject {
        entries.add(JsonEntry(key, "null"))
        this
    }

    public func putObj(key: String, value: JsonObject): JsonObject {
        entries.add(JsonEntry(key, value.toString()))
        this
    }

    public func putArr(key: String, value: JsonArray): JsonObject {
        entries.add(JsonEntry(key, value.toString()))
        this
    }

    public func putRaw(key: String, raw: String): JsonObject {
        entries.add(JsonEntry(key, raw))
        this
    }

    public func toString(): String {
        var result = "{"
        for (i in 0..entries.size) {
            if (i > 0) { result += "," }
            let e = entries[i]
            result += "\"${escapeJsonString(e.key)}\":${e.raw}"
        }
        result += "}"
        result
    }
}

public class JsonArray {
    var items: ArrayList<String> = ArrayList<String>()

    public init() {}

    public func addStr(value: String): JsonArray {
        items.add("\"${escapeJsonString(value)}\"")
        this
    }

    public func addInt(value: Int64): JsonArray {
        items.add("${value}")
        this
    }

    public func addFloat(value: Float64): JsonArray {
        items.add("${value}")
        this
    }

    public func addBool(value: Bool): JsonArray {
        let v = if (value) { "true" } else { "false" }
        items.add(v)
        this
    }

    public func addObj(value: JsonObject): JsonArray {
        items.add(value.toString())
        this
    }

    public func addArr(value: JsonArray): JsonArray {
        items.add(value.toString())
        this
    }

    public func addRaw(raw: String): JsonArray {
        items.add(raw)
        this
    }

    public func toString(): String {
        var result = "["
        for (i in 0..items.size) {
            if (i > 0) { result += "," }
            result += items[i]
        }
        result += "]"
        result
    }
}

public func parseJsonString(json: String, field: String): ?String {
    let searchKey = "\"${field}\""
    let runes = json.toRuneArray()
    let keyRunes = searchKey.toRuneArray()
    var i: Int64 = 0
    while (i <= runes.size - keyRunes.size) {
        var found = true
        for (j in 0..keyRunes.size) {
            if (runes[i + j] != keyRunes[j]) {
                found = false
                break
            }
        }
        if (found) {
            var k = i + keyRunes.size
            while (k < runes.size && (runes[k] == r' ' || runes[k] == r':')) {
                k += 1
            }
            if (k < runes.size) {
                if (runes[k] == r'"') {
                    k += 1
                    var value = ""
                    while (k < runes.size && runes[k] != r'"') {
                        if (runes[k] == r'\\' && k + 1 < runes.size) {
                            k += 1
                        }
                        value += runes[k].toString()
                        k += 1
                    }
                    return value
                }
                var value = ""
                while (k < runes.size && runes[k] != r',' && runes[k] != r'}' && runes[k] != r']') {
                    value += runes[k].toString()
                    k += 1
                }
                return value.trimAscii()
            }
        }
        i += 1
    }
    None
}
