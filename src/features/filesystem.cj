package soonlnk.features

import std.collection.{ArrayList, HashMap}
import std.fs.*
import std.sync.Mutex
import soonlnk.commons.*

public interface FileSystemProvider {
    func listDir(path: String): ArrayList<FileEntry>
    func readFile(path: String, offset: Int64, length: Int64): Array<UInt8>
    func writeFile(path: String, data: Array<UInt8>, offset: Int64): Unit
    func getFileInfo(path: String): FileMetadata
    func deleteFile(path: String): Unit
    func createDir(path: String): Unit
}

public class LocalFileSystem <: FileSystemProvider {
    public let rootDir: String
    public let consoleEnabled: Bool

    public init(rootDir: String, consoleEnabled!: Bool = true) {
        this.rootDir = rootDir
        this.consoleEnabled = consoleEnabled
    }

    public func listDir(dirPath: String): ArrayList<FileEntry> {
        let entries = ArrayList<FileEntry>()
        let fullPath = joinPaths(rootDir, dirPath)
        try {
            let items: Array<FileInfo> = Directory.readFrom(fullPath)
            for (item in items) {
                let fe = FileEntry()
                let p = item.path
                fe.name = p.fileName.toString()
                fe.path = joinPaths(dirPath, fe.name)
                fe.isDir = item.isDirectory()
                fe.size = if (fe.isDir) { 0 } else { item.size }
                fe.mimeType = resolvePreviewMimeType("", fe.path, fe.isDir)
                entries.add(fe)
            }
        } catch (e: Exception) {
            if (consoleEnabled) {
                println("[FileSystem] 列出目录失败: ${fullPath} - ${e.message}")
            }
        }
        entries
    }

    public func readFile(filePath: String, offset: Int64, length: Int64): Array<UInt8> {
        let fullPath = joinPaths(rootDir, filePath)
        let file = File(fullPath, OpenMode.Read)
        if (offset > 0) {
            var remainingSkip = offset
            while (remainingSkip > 0) {
                let chunk = if (remainingSkip > 8192) { 8192 } else { remainingSkip }
                let skipBuf = Array<UInt8>(chunk, repeat: 0)
                let n = file.read(skipBuf)
                if (n <= 0) {
                    break
                }
                remainingSkip -= n
            }
        }

        let data = ArrayList<UInt8>()
        var remaining = length
        while (remaining > 0) {
            let chunk = if (remaining > 8192) { 8192 } else { remaining }
            let readBuf = Array<UInt8>(chunk, repeat: 0)
            let n = file.read(readBuf)
            if (n <= 0) {
                break
            }
            for (i in 0..n) {
                data.add(readBuf[i])
            }
            remaining -= n
        }
        file.close()
        data.toArray()
    }

    public func writeFile(filePath: String, data: Array<UInt8>, offset: Int64): Unit {
        let fullPath = joinPaths(rootDir, filePath)
        ensureFileTargetPath(fullPath)
        ensureParentDir(fullPath)
        let mode = if (offset == 0) { OpenMode.Write } else { OpenMode.Append }
        let file = File(fullPath, mode)
        file.write(data)
        file.close()
    }

    public func getFileInfo(filePath: String): FileMetadata {
        let fullPath = joinPaths(rootDir, filePath)
        let info = FileInfo(fullPath)
        let metadata = FileMetadata()
        metadata.name = extractFileName(filePath)
        metadata.path = filePath
        metadata.size = info.size
        metadata.isDir = info.isDirectory()
        metadata.mimeType = resolvePreviewMimeType("", filePath, metadata.isDir)
        metadata
    }

    public func deleteFile(filePath: String): Unit {
        let fullPath = joinPaths(rootDir, filePath)
        remove(fullPath)
    }

    public func createDir(dirPath: String): Unit {
        let fullPath = joinPaths(rootDir, dirPath)
        if (pathExistsAsDirectory(fullPath)) {
            return
        }
        if (pathExistsForWriteTarget(fullPath)) {
            throw Exception("target path already exists as a file")
        }
        Directory.create(fullPath, recursive: true)
    }
}

public class FileSystemManager {
    var providers: HashMap<String, FileSystemProvider> = HashMap<String, FileSystemProvider>()
    let mutex: Mutex = Mutex()
    var consoleEnabled: Bool = true

    public init() {}

    public func setConsoleEnabled(value: Bool): Unit {
        synchronized(mutex) {
            consoleEnabled = value
        }
    }

    func shouldPrintToConsole(): Bool {
        synchronized(mutex) {
            consoleEnabled
        }
    }

    public func registerProvider(deviceId: String, provider: FileSystemProvider): Unit {
        synchronized(mutex) {
            providers.add(deviceId, provider)
        }
    }

    public func getProvider(deviceId: String): ?FileSystemProvider {
        synchronized(mutex) {
            providers.get(deviceId)
        }
    }

    public func listDir(deviceId: String, path: String): ArrayList<FileEntry> {
        if (let Some(provider) <- getProvider(deviceId)) {
            return provider.listDir(path)
        }
        if (shouldPrintToConsole()) {
            println("[FileSystem] 设备未注册文件系统提供者: ${deviceId}")
        }
        ArrayList<FileEntry>()
    }

    public func readFile(deviceId: String, path: String, offset: Int64, length: Int64): Array<UInt8> {
        if (let Some(provider) <- getProvider(deviceId)) {
            return provider.readFile(path, offset, length)
        }
        Array<UInt8>(0, repeat: 0)
    }

    public func writeFile(deviceId: String, path: String, data: Array<UInt8>, offset: Int64): Unit {
        if (let Some(provider) <- getProvider(deviceId)) {
            provider.writeFile(path, data, offset)
        }
    }

    public func getFileInfo(deviceId: String, path: String): ?FileMetadata {
        if (let Some(provider) <- getProvider(deviceId)) {
            try {
                return provider.getFileInfo(path)
            } catch (e: Exception) {
                if (shouldPrintToConsole()) {
                    println("[FileSystem] 获取文件信息失败: ${path} - ${e.message}")
                }
            }
        }
        None
    }

    public func deleteFile(deviceId: String, path: String): Unit {
        if (let Some(provider) <- getProvider(deviceId)) {
            provider.deleteFile(path)
        }
    }

    public func createDir(deviceId: String, path: String): Unit {
        if (let Some(provider) <- getProvider(deviceId)) {
            provider.createDir(path)
        }
    }
}

func joinPaths(base: String, relative: String): String {
    if (relative.size == 0) { return base }
    if (base.size == 0) { return relative }
    let baseRunes = base.toRuneArray()
    let relRunes = relative.toRuneArray()
    let baseEndsSlash = baseRunes[baseRunes.size - 1] == r'/'
    let relStartsSlash = relRunes[0] == r'/'
    if (baseEndsSlash && relStartsSlash) {
        return base + strSubstring(relative, 1, Int64(relRunes.size))
    }
    if (!baseEndsSlash && !relStartsSlash) {
        return base + "/" + relative
    }
    base + relative
}

func extractFileName(path: String): String {
    let runes = path.toRuneArray()
    var i = runes.size - 1
    while (i >= 0) {
        if (runes[i] == r'/' || runes[i] == r'\\') {
            var name = ""
            for (j in (i + 1)..runes.size) {
                name += runes[j].toString()
            }
            return name
        }
        i -= 1
    }
    path
}

func ensureParentDir(filePath: String): Unit {
    let runes = filePath.toRuneArray()
    var lastSlash: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'/') {
            lastSlash = i
        }
    }
    if (lastSlash > 0) {
        let parentDir = strSubstring(filePath, 0, lastSlash)
        try {
            Directory.create(parentDir, recursive: true)
        } catch (_: Exception) {}
    }
}

func ensureFileTargetPath(path: String): Unit {
    if (pathExistsAsDirectory(path)) {
        throw Exception("target path is a directory")
    }
}

func pathExistsAsDirectory(path: String): Bool {
    try {
        FileInfo(path).isDirectory()
    } catch (_: Exception) {
        false
    }
}

func pathExistsForWriteTarget(path: String): Bool {
    try {
        let _ = FileInfo(path)
        true
    } catch (_: Exception) {
        false
    }
}
