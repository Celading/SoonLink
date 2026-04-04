package soonlnk.commons

import std.collection.ArrayList
import std.fs.{File, OpenMode}

public func strEndsWith(s: String, suffix: String): Bool {
    let sRunes = s.toRuneArray()
    let suffRunes = suffix.toRuneArray()
    if (suffRunes.size > sRunes.size) {
        return false
    }
    let offset = sRunes.size - suffRunes.size
    for (i in 0..suffRunes.size) {
        if (sRunes[offset + i] != suffRunes[i]) {
            return false
        }
    }
    true
}

public func strStartsWith(s: String, prefix: String): Bool {
    let sRunes = s.toRuneArray()
    let prefRunes = prefix.toRuneArray()
    if (prefRunes.size > sRunes.size) {
        return false
    }
    for (i in 0..prefRunes.size) {
        if (sRunes[i] != prefRunes[i]) {
            return false
        }
    }
    true
}

public func strContains(s: String, substr: String): Bool {
    let sRunes = s.toRuneArray()
    let subRunes = substr.toRuneArray()
    if (subRunes.size > sRunes.size) {
        return false
    }
    let limit = sRunes.size - subRunes.size + 1
    for (i in 0..limit) {
        var found = true
        for (j in 0..subRunes.size) {
            if (sRunes[i + j] != subRunes[j]) {
                found = false
                break
            }
        }
        if (found) {
            return true
        }
    }
    false
}

public func strReplace(s: String, old: String, new: String): String {
    let sRunes = s.toRuneArray()
    let oldRunes = old.toRuneArray()
    if (oldRunes.size == 0 || oldRunes.size > sRunes.size) {
        return s
    }
    var result = ""
    var i: Int64 = 0
    while (i <= sRunes.size - oldRunes.size) {
        var found = true
        for (j in 0..oldRunes.size) {
            if (sRunes[i + j] != oldRunes[j]) {
                found = false
                break
            }
        }
        if (found) {
            result += new
            i += oldRunes.size
        } else {
            result += sRunes[i].toString()
            i += 1
        }
    }
    while (i < sRunes.size) {
        result += sRunes[i].toString()
        i += 1
    }
    result
}

public func strTrimPrefix(s: String, prefix: String): String {
    if (strStartsWith(s, prefix)) {
        let runes = s.toRuneArray()
        var result = ""
        for (i in prefix.size..runes.size) {
            result += runes[i].toString()
        }
        return result
    }
    s
}

public func strSubstring(s: String, start: Int64, end: Int64): String {
    let runes = s.toRuneArray()
    let actualEnd = if (end > runes.size) { runes.size } else { end }
    let actualStart = if (start < 0) { 0 } else { start }
    var result = ""
    for (i in actualStart..actualEnd) {
        result += runes[i].toString()
    }
    result
}

public func stringToBytes(s: String): Array<UInt8> {
    let runes = s.toRuneArray()
    let bytes = Array<UInt8>(runes.size, repeat: 0)
    for (i in 0..runes.size) {
        let code = UInt32(runes[i])
        bytes[i] = if (code <= UInt32(255)) { UInt8(code) } else { UInt8(63) }
    }
    bytes
}

public func readFileAsString(path: String): String {
    let file = File(path, OpenMode.Read)
    let buf = ArrayList<UInt8>()
    let tmp = Array<UInt8>(8192, repeat: 0)
    while (true) {
        let n = file.read(tmp)
        if (n <= 0) { break }
        for (i in 0..n) {
            buf.add(tmp[i])
        }
    }
    file.close()
    String.fromUtf8(buf.toArray())
}

public func renderTemplate(templatePath: String, data: Array<(String, String)>): String {
    var content = readFileAsString(templatePath)
    for ((key, value) in data) {
        content = strReplace(content, "{{.${key}}}", value)
    }
    content
}

public func escapeJsonString(s: String): String {
    var result = ""
    for (ch in s.toRuneArray()) {
        match (ch) {
            case r'"' => result += "\\\""
            case r'\\' => result += "\\\\"
            case r'\n' => result += "\\n"
            case r'\r' => result += "\\r"
            case r'\t' => result += "\\t"
            case _ => result += ch.toString()
        }
    }
    result
}

public func formatBytes(bytes: Int64): String {
    if (bytes < 1024) {
        return "${bytes} B"
    }
    if (bytes < 1024 * 1024) {
        let kb = bytes / 1024
        return "${kb} KB"
    }
    if (bytes < 1024 * 1024 * 1024) {
        let mb = bytes / (1024 * 1024)
        return "${mb} MB"
    }
    let gb = bytes / (1024 * 1024 * 1024)
    "${gb} GB"
}
