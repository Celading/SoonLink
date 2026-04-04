package soonlnk.commons

import std.collection.HashMap

public interface ConfigStore {
    func load(): HashMap<String, String>
    func save(values: HashMap<String, String>): Unit
}

public class TomlConfigStore <: ConfigStore {
    public let path: String
    let fileMgr: FileMgr

    public init(path: String) {
        this.path = path
        this.fileMgr = LocalFileMgr()
    }

    public init(path: String, fileMgr: FileMgr) {
        this.path = path
        this.fileMgr = fileMgr
    }

    public func load(): HashMap<String, String> {
        let values = HashMap<String, String>()
        if (!fileMgr.exists(path)) {
            return values
        }

        let lines = fileMgr.readLines(path)
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0) { continue }
            if (strStartsWith(trimmed, "#") || strStartsWith(trimmed, "[")) {
                continue
            }
            if (let Some((k, v)) <- parseTomlLine(trimmed)) {
                values.add(k, v)
            }
        }
        values
    }

    public func save(values: HashMap<String, String>): Unit {
        var text = "[soonlink]\n"
        for ((k, v) in values) {
            text += "${k} = \"${escapeToml(v)}\"\n"
        }
        fileMgr.writeText(path, text, false)
    }
}

func parseTomlLine(line: String): ?(String, String) {
    let runes = line.toRuneArray()
    var sep: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'=') {
            sep = i
            break
        }
    }
    if (sep <= 0 || sep >= runes.size - 1) {
        return None
    }

    let key = strSubstring(line, 0, sep).trimAscii()
    var value = strSubstring(line, sep + 1, runes.size).trimAscii()
    let valueRunes = value.toRuneArray()
    if (valueRunes.size >= 2 && valueRunes[0] == r'"' && valueRunes[valueRunes.size - 1] == r'"') {
        value = strSubstring(value, 1, valueRunes.size - 1)
    }

    if (key.size == 0) {
        return None
    }
    Some((key, value))
}

func escapeToml(s: String): String {
    var result = ""
    for (r in s.toRuneArray()) {
        match (r) {
            case r'\\' => result += "\\\\"
            case r'"' => result += "\\\""
            case _ => result += r.toString()
        }
    }
    result
}
