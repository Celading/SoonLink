package soonlnk.commons

import std.collection.*
import std.fs.*
import std.unicode.*

public interface FileMgr {
    func exists(path: String): Bool
    func ensureDir(path: String): Unit
    func readBytes(path: String): Array<UInt8>
    func writeBytes(path: String, data: Array<UInt8>, append: Bool): Unit
    func readText(path: String): String
    func writeText(path: String, content: String, append: Bool): Unit
    func readLines(path: String): ArrayList<String>
}

public class LocalFileMgr <: FileMgr {
    public init() {}

    public func exists(path: String): Bool {
        try {
            let _ = FileInfo(path)
            return true
        } catch (_: Exception) {
            false
        }
    }

    public func ensureDir(path: String): Unit {
        if (path.size == 0) { return }
        try {
            Directory.create(path, recursive: true)
        } catch (_: Exception) {}
    }

    public func readBytes(path: String): Array<UInt8> {
        let file = File(path, OpenMode.Read)
        let data = ArrayList<UInt8>()
        let buf = Array<UInt8>(8192, repeat: 0)
        while (true) {
            let n = file.read(buf)
            if (n <= 0) { break }
            for (i in 0..n) {
                data.add(buf[i])
            }
        }
        file.close()
        data.toArray()
    }

    public func writeBytes(path: String, data: Array<UInt8>, append: Bool): Unit {
        ensureWritableFileTarget(path)
        ensureParentDirForFileMgr(path)
        let mode = if (append) { OpenMode.Append } else { OpenMode.Write }
        let file = File(path, mode)
        file.write(data)
        file.close()
    }

    public func readText(path: String): String {
        let bytes = readBytes(path)
        String.fromUtf8(bytes)
    }

    public func writeText(path: String, content: String, append: Bool): Unit {
        writeBytes(path, stringToBytes(content), append)
    }

    public func readLines(path: String): ArrayList<String> {
        let lines = ArrayList<String>()
        if (!exists(path)) {
            return lines
        }

        let text = readText(path)
        var current = ""
        for (r in text.toRuneArray()) {
            if (r == r'\n') {
                lines.add(current)
                current = ""
                continue
            }
            if (r != r'\r') {
                current += r.toString()
            }
        }
        if (current.size > 0 || text.size == 0) {
            lines.add(current)
        }
        lines
    }
}

func ensureParentDirForFileMgr(path: String): Unit {
    let runes = path.toRuneArray()
    var lastSlash: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'/' || runes[i] == r'\\') {
            lastSlash = i
        }
    }
    if (lastSlash > 0) {
        let dir = strSubstring(path, 0, lastSlash)
        try {
            Directory.create(dir, recursive: true)
        } catch (_: Exception) {}
    }
}

func ensureWritableFileTarget(path: String): Unit {
    if (pathIsDirectoryForFileMgr(path)) {
        throw Exception("target path is a directory")
    }
}

func pathIsDirectoryForFileMgr(path: String): Bool {
    try {
        FileInfo(path).isDirectory()
    } catch (_: Exception) {
        false
    }
}
