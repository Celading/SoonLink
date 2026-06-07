package soonlnk.commons

import std.collection.HashMap
import std.unicode.*

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
        var lineNo: Int64 = 1
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0) {
                lineNo += 1
                continue
            }
            if (strStartsWith(trimmed, "#") || strStartsWith(trimmed, "[")) {
                lineNo += 1
                continue
            }
            if (let Some((k, v)) <- parseTomlLine(trimmed)) {
                values.add(normalizeConfigKey(k), v)
            } else {
                throw Exception("TOML config parse error at ${path}:${lineNo}: expected key = \"value\", got `${trimmed}`")
            }
            lineNo += 1
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

public class YamlConfigStore <: ConfigStore {
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
        var lineNo: Int64 = 1
        for (line in lines) {
            let trimmed = line.trimAscii()
            if (trimmed.size == 0 || strStartsWith(trimmed, "#")) {
                lineNo += 1
                continue
            }
            if (trimmed == "soonlink:") {
                lineNo += 1
                continue
            }
            if (let Some((k, v)) <- parseYamlLine(trimmed)) {
                values.add(normalizeConfigKey(k), v)
            } else {
                throw Exception("YAML config parse error at ${path}:${lineNo}: expected key: \"value\", got `${trimmed}`")
            }
            lineNo += 1
        }
        values
    }

    public func save(values: HashMap<String, String>): Unit {
        var text = "soonlink:\n"
        for ((k, v) in values) {
            text += "  ${k}: \"${escapeConfigValue(v)}\"\n"
        }
        fileMgr.writeText(path, text, false)
    }
}

public func configStoreFor(path: String): ConfigStore {
    let lower = path.trimAscii().toLower()
    if (strEndsWith(lower, ".yaml") || strEndsWith(lower, ".yml")) {
        return YamlConfigStore(path)
    }
    TomlConfigStore(path)
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

    if (key.size == 0) {
        return None
    }
    Some((key, unquoteConfigValue(value)))
}

func parseYamlLine(line: String): ?(String, String) {
    let runes = line.toRuneArray()
    var sep: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r':') {
            sep = i
            break
        }
    }
    if (sep <= 0 || sep >= runes.size - 1) {
        return None
    }

    let key = strSubstring(line, 0, sep).trimAscii()
    var value = strSubstring(line, sep + 1, runes.size).trimAscii()
    if (key.size == 0 || value.size == 0) {
        return None
    }
    Some((key, unquoteConfigValue(value)))
}

func normalizeConfigKey(raw: String): String {
    var text = raw.trimAscii()
    if (strStartsWith(text, "--")) {
        text = strSubstring(text, 2, text.size)
    }

    var out = ""
    for (r in text.toRuneArray()) {
        if (r == r'-') {
            out += "_"
        } else {
            out += r.toString()
        }
    }
    out
}

func unquoteConfigValue(raw: String): String {
    var value = raw.trimAscii()
    let valueRunes = value.toRuneArray()
    if (valueRunes.size >= 2 && valueRunes[0] == r'"' && valueRunes[valueRunes.size - 1] == r'"') {
        value = strSubstring(value, 1, valueRunes.size - 1)
    }
    value
}

func escapeToml(s: String): String {
    escapeConfigValue(s)
}

func escapeConfigValue(s: String): String {
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
