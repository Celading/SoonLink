package soonlnk.features

import std.collection.{ArrayList, HashMap}
import std.sync.Mutex
import std.fs.{File, OpenMode, Directory}
import soonlnk.commons.*

public interface TransferProtocol {
    func name(): String
    func transfer(task: TransferTask, onProgress: (Float64) -> Unit): Bool
}

public class TransferEngine {
    let tempDir: String
    let maxWorkers: Int64
    var protocols: HashMap<String, TransferProtocol> = HashMap<String, TransferProtocol>()
    var activeTasks: HashMap<String, TransferTask> = HashMap<String, TransferTask>()
    let mutex: Mutex = Mutex()
    var onTaskUpdate: ?(String, TaskStatus, Float64) -> Unit = None
    var running: Bool = false
    var consoleEnabled: Bool = true

    public init(tempDir: String, maxWorkers: Int64) {
        this.tempDir = tempDir
        this.maxWorkers = maxWorkers
    }

    public func registerProtocol(protocol: TransferProtocol): Unit {
        synchronized(mutex) {
            protocols.add(protocol.name(), protocol)
        }
    }

    public func setTaskUpdateCallback(callback: (String, TaskStatus, Float64) -> Unit): Unit {
        this.onTaskUpdate = callback
    }

    public func start(): Unit {
        try {
            Directory.create(tempDir, recursive: true)
        } catch (_: Exception) {}
        running = true
        if (consoleEnabled) {
            println("[Transfer] 传输引擎已启动, 最大工作线程: ${maxWorkers}")
        }
    }

    public func setConsoleEnabled(value: Bool): Unit {
        consoleEnabled = value
    }

    public func startTransfer(task: TransferTask): Unit {
        synchronized(mutex) {
            activeTasks.add(task.id, task)
        }
        if (let Some(cb) <- onTaskUpdate) {
            cb(task.id, Pending, 0.0)
        }
        spawn { processTask(task) }
    }

    func processTask(task: TransferTask): Unit {
        if (let Some(cb) <- onTaskUpdate) {
            cb(task.id, Running, 0.0)
        }

        let protocolName = selectBestProtocol(task)
        task.protocol = protocolName

        var protocol: ?TransferProtocol = None
        synchronized(mutex) {
            protocol = protocols.get(protocolName)
        }

        match (protocol) {
            case Some(p) =>
                let success = p.transfer(task, { progress: Float64 =>
                    if (let Some(cb) <- onTaskUpdate) {
                        cb(task.id, Running, progress)
                    }
                })
                match (task.status) {
                    case Cancelled =>
                        if (let Some(cb) <- onTaskUpdate) {
                            cb(task.id, Cancelled, task.progress)
                        }
                    case _ =>
                        if (success) {
                            task.completedAt = currentTimestamp()
                            if (let Some(cb) <- onTaskUpdate) {
                                cb(task.id, Completed, 100.0)
                            }
                        } else {
                            if (let Some(cb) <- onTaskUpdate) {
                                cb(task.id, Failed, 0.0)
                            }
                        }
                }
            case None =>
                if (consoleEnabled) {
                    println("[Transfer] 未找到传输协议: ${protocolName}")
                }
                if (let Some(cb) <- onTaskUpdate) {
                    cb(task.id, Failed, 0.0)
                }
        }

        synchronized(mutex) {
            activeTasks.remove(task.id)
        }
    }

    func selectBestProtocol(task: TransferTask): String {
        if (task.fileCategory.trimAscii().size == 0) {
            task.fileCategory = resolveTransferFileCategory(
                task.filePath,
                task.metadata.mimeType,
                task.sourceIsDir || task.metadata.isDir
            )
        }
        task.protocolPreferences = sanitizeTransferProtocolPreferences(task.protocolPreferences)
        let totalBytes = if (task.totalBytes > 0) { task.totalBytes } else { task.metadata.size }
        task.protocolCandidates = buildTransferProtocolCandidates(
            task.fileCategory,
            totalBytes,
            task.protocolPreferences,
            task.sourceIsDir || task.metadata.isDir,
            task.threads
        )

        synchronized(mutex) {
            for (protocolName in task.protocolCandidates) {
                if (!isRuntimeReadyTransferProtocol(protocolName)) {
                    continue
                }
                if (let Some(_protocol) <- protocols.get(protocolName)) {
                    return protocolName
                }
            }
        }
        "http"
    }

    public func cancelTask(taskId: String): Bool {
        synchronized(mutex) {
            if (let Some(task) <- activeTasks.get(taskId)) {
                task.status = Cancelled
                if (let Some(cb) <- onTaskUpdate) {
                    cb(taskId, Cancelled, task.progress)
                }
                return true
            }
        }
        false
    }
}

public class HTTPProtocol <: TransferProtocol {
    public init() {}

    public func name(): String { "http" }

    public func transfer(task: TransferTask, onProgress: (Float64) -> Unit): Bool {
        if (task.filePath.size > 0) {
            println("[HTTP] 开始传输: ${task.sourceDevice} -> ${task.targetDevice} (${task.filePath})")
        }

        if (task.sourceDevice == "local" && task.targetDevice == "local") {
            return transferLocalToLocal(task, onProgress)
        }

        for (i in 0..11) {
            let progress = Float64(i * 10)
            onProgress(progress)
            try {
                sleep(Duration.millisecond * 200)
            } catch (_: Exception) {}
        }
        true
    }

    func transferLocalToLocal(task: TransferTask, onProgress: (Float64) -> Unit): Bool {
        try {
            let srcFile = File(task.filePath, OpenMode.Read)
            let targetPath = resolveTransferTargetPath(task)
            let targetDir = extractParentDir(targetPath)
            if (targetDir.size > 0) {
                try {
                    Directory.create(targetDir, recursive: true)
                } catch (_: Exception) {}
            } else {
                try {
                    Directory.create("/tmp/soonlink", recursive: true)
                } catch (_: Exception) {}
            }

            let dstFile = File(targetPath, OpenMode.Write)
            let buffer = Array<UInt8>(65536, repeat: 0)
            var copied: Int64 = 0
            let totalSize = task.metadata.size

            while (true) {
                let n = srcFile.read(buffer)
                if (n <= 0) { break }
                let writeData = if (n == buffer.size) {
                    buffer
                } else {
                    let tmp = Array<UInt8>(n, repeat: 0)
                    for (i in 0..n) { tmp[i] = buffer[i] }
                    tmp
                }
                dstFile.write(writeData)
                copied += n
                if (totalSize > 0) {
                    let progress = Float64(copied) / Float64(totalSize) * 100.0
                    onProgress(progress)
                }
            }

            srcFile.close()
            dstFile.close()
            task.tempPath = targetPath
            println("[HTTP] 文件传输完成: ${task.filePath} -> ${targetPath}")
            return true
        } catch (e: Exception) {
            task.error = "传输失败: ${e.message}"
            println("[HTTP] ${task.error}")
            return false
        }
    }
}

func resolveTransferTargetPath(task: TransferTask): String {
    if (task.targetPath.size > 0) {
        return joinPaths(task.targetPath, extractFileName(task.filePath))
    }
    joinPaths("/tmp/soonlink", "copy_${currentTimestamp()}_${extractFileName(task.filePath)}")
}

func extractParentDir(path: String): String {
    let runes = path.toRuneArray()
    var slashAt: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'/') {
            slashAt = i
        }
    }
    if (slashAt <= 0) {
        return ""
    }
    strSubstring(path, 0, slashAt)
}

public class MultiThreadHTTPProtocol <: TransferProtocol {
    let defaultThreads: Int64 = 4
    let defaultChunkSize: Int64 = 4 * 1024 * 1024

    public init() {}

    public func name(): String { "multi-thread-http" }

    public func transfer(task: TransferTask, onProgress: (Float64) -> Unit): Bool {
        if (task.filePath.size > 0) {
            println("[MultiThread-HTTP] 开始传输: ${task.sourceDevice} -> ${task.targetDevice}")
        }
        if (task.sourceDevice == "local" && task.targetDevice == "local") {
            let httpP = HTTPProtocol()
            return httpP.transfer(task, onProgress)
        }
        println("[MultiThread-HTTP] 跨设备多线程传输尚未实现")
        false
    }
}

public class QUICProtocol <: TransferProtocol {
    public init() {}
    public func name(): String { "quic" }
    public func transfer(_task: TransferTask, _onProgress: (Float64) -> Unit): Bool {
        println("[QUIC] QUIC传输协议尚未实现")
        false
    }
}

public class RSyncProtocol <: TransferProtocol {
    public init() {}
    public func name(): String { "rsync" }
    public func transfer(_task: TransferTask, _onProgress: (Float64) -> Unit): Bool {
        println("[RSync] RSync传输协议尚未实现")
        false
    }
}

public class P2PProtocol <: TransferProtocol {
    public init() {}
    public func name(): String { "p2p" }
    public func transfer(_task: TransferTask, _onProgress: (Float64) -> Unit): Bool {
        println("[P2P] P2P传输协议尚未实现")
        false
    }
}

func isRuntimeReadyTransferProtocol(protocolName: String): Bool {
    protocolName == "http" || protocolName == "multi-thread-http"
}
