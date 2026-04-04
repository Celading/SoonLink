package soonlnk.features

import soonlnk.commons.*
import std.collection.*
import std.unicode.*
public class FileReadResult {
    public var ok: Bool = false
    public var content: String = ""
    public var encoding: String = "unknown"
    public var error: String = ""

    public init() {}
}

public class FileHelper {
    let fileMgr: FileMgr

    public init() {
        this.fileMgr = LocalFileMgr()
    }

    public init(fileMgr: FileMgr) {
        this.fileMgr = fileMgr
    }

    public func detectEncoding(path: String): String {
        if (!fileMgr.exists(path)) {
            return "unknown"
        }
        let bytes = fileMgr.readBytes(path)
        detectEncodingByBytes(bytes)
    }

    public func readTextAuto(path: String): FileReadResult {
        let result = FileReadResult()
        if (!fileMgr.exists(path)) {
            result.ok = false
            result.error = "file not found"
            return result
        }

        try {
            let bytes = fileMgr.readBytes(path)
            result.encoding = detectEncodingByBytes(bytes)
            result.content = decodeBytes(bytes, result.encoding)
            result.ok = true
            result
        } catch (e: Exception) {
            result.ok = false
            result.error = e.message
            result
        }
    }

    public func readLine(path: String, lineNumber: Int64): ?String {
        if (lineNumber <= 0) {
            return None
        }
        let readResult = readTextAuto(path)
        if (!readResult.ok) {
            return None
        }

        var currentLine: Int64 = 1
        var current = ""
        for (r in readResult.content.toRuneArray()) {
            if (r == r'\n') {
                if (currentLine == lineNumber) {
                    return Some(current)
                }
                currentLine += 1
                current = ""
            } else if (r != r'\r') {
                current += r.toString()
            }
        }

        if (currentLine == lineNumber) {
            return Some(current)
        }
        None
    }

    public func writeText(path: String, content: String, encoding: String): Unit {
        let normalized = normalizeEncoding(encoding)
        let bytes = encodeText(content, normalized)
        fileMgr.writeBytes(path, bytes, false)
    }

    public func appendText(path: String, content: String, encoding: String): Unit {
        let normalized = normalizeEncoding(encoding)
        let bytes = encodeText(content, normalized)
        fileMgr.writeBytes(path, bytes, true)
    }
}

public func detectTextEncoding(bytes: Array<UInt8>): String {
    detectEncodingByBytes(bytes)
}

public func decodeTextBytes(bytes: Array<UInt8>, encoding: String): String {
    decodeBytes(bytes, encoding)
}

func normalizeEncoding(raw: String): String {
    let x = raw.trimAscii().toLower()
    if (x == "utf8" || x == "utf-8") {
        return "utf-8"
    }
    if (x == "gbk" || x == "gb2312") {
        return "gbk"
    }
    "utf-8"
}

func detectEncodingByBytes(bytes: Array<UInt8>): String {
    if (bytes.size >= 3) {
        if (bytes[0] == UInt8(0xEF) && bytes[1] == UInt8(0xBB) && bytes[2] == UInt8(0xBF)) {
            return "utf-8"
        }
    }
    if (looksLikeUtf8(bytes)) {
        return "utf-8"
    }
    "gbk"
}

func looksLikeUtf8(bytes: Array<UInt8>): Bool {
    var i: Int64 = 0
    while (i < bytes.size) {
        let b = bytes[i]
        if (b < UInt8(0x80)) {
            i += 1
            continue
        }

        var need: Int64 = 0
        if ((b & UInt8(0xE0)) == UInt8(0xC0)) {
            need = 1
        } else if ((b & UInt8(0xF0)) == UInt8(0xE0)) {
            need = 2
        } else if ((b & UInt8(0xF8)) == UInt8(0xF0)) {
            need = 3
        } else {
            return false
        }

        if (i + need >= bytes.size) {
            return false
        }

        var j: Int64 = 1
        while (j <= need) {
            if ((bytes[i + j] & UInt8(0xC0)) != UInt8(0x80)) {
                return false
            }
            j += 1
        }

        i += need + 1
    }
    true
}

func decodeBytes(bytes: Array<UInt8>, encoding: String): String {
    if (encoding == "utf-8") {
        return String.fromUtf8(bytes)
    }
    // current phase: GBK fallback keeps raw bytes mapped as UTF-8 best effort.
    String.fromUtf8(bytes)
}

func encodeText(text: String, encoding: String): Array<UInt8> {
    if (encoding == "utf-8") {
        return stringToBytes(text)
    }
    // current phase: GBK fallback uses UTF-8 bytes; upgrade with real codec later.
    stringToBytes(text)
}
