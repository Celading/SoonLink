package soonlnk.tests

import soonlnk.commons.*
import soonlnk.master.*
import soonlnk.product.*
import std.fs.{Directory, FileInfo}
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class TransferDirectory_test {
    @TestCase
    public func localDirectoryTransferKeepsTreeAndEmptyDirs(): Unit {
        let scope = testTempToken("soonlink_transfer_root")
        let rootDir = "/tmp/${scope}"
        let fileMgr = LocalFileMgr()
        fileMgr.ensureDir(rootDir + "/source/docs/nested")
        fileMgr.ensureDir(rootDir + "/source/empty-only")
        fileMgr.writeText(rootDir + "/source/readme.txt", "root-file", false)
        fileMgr.writeText(rootDir + "/source/docs/nested/readme.txt", "nested-file", false)

        var cfg = AppConfig()
        cfg.localRootDir = rootDir
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let server = CoreServer(cfg, profile: coreProductProfile())
        try {
            server.start()
            let task = server.createTransferTask("local", "local", "/source", "/copies")
            let finalTask = waitForTask(server, task.id)

            @Assert(taskStatusToString(finalTask.status), "completed")
            @Assert(finalTask.sourceIsDir, true)
            @Assert(finalTask.completedEntries, finalTask.totalEntries)
            @Assert(fileMgr.readText(rootDir + "/copies/source/readme.txt"), "root-file")
            @Assert(fileMgr.readText(rootDir + "/copies/source/docs/nested/readme.txt"), "nested-file")
            @Assert(FileInfo(rootDir + "/copies/source/empty-only").isDirectory(), true)
        } finally {
            server.stop()
        }
    }

    @TestCase
    public func explicitFileTargetPathStillWorksForSingleFileTask(): Unit {
        let scope = testTempToken("soonlink_transfer_single")
        let rootDir = "/tmp/${scope}"
        let fileMgr = LocalFileMgr()
        fileMgr.ensureDir(rootDir + "/src")
        fileMgr.writeText(rootDir + "/src/demo.txt", "demo", false)

        var cfg = AppConfig()
        cfg.localRootDir = rootDir
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let server = CoreServer(cfg, profile: coreProductProfile())
        try {
            server.start()
            let task = server.createTransferTask("local", "local", "/src/demo.txt", "/dest/demo.txt")
            let finalTask = waitForTask(server, task.id)

            @Assert(taskStatusToString(finalTask.status), "completed")
            @Assert(finalTask.sourceIsDir, false)
            @Assert(fileMgr.readText(rootDir + "/dest/demo.txt"), "demo")
        } finally {
            server.stop()
        }
    }

    @TestCase
    public func directoryTransferMergesIntoExistingFolderWithoutDeletingSiblings(): Unit {
        let scope = testTempToken("soonlink_transfer_merge")
        let rootDir = "/tmp/${scope}"
        let fileMgr = LocalFileMgr()
        fileMgr.ensureDir(rootDir + "/source/docs")
        fileMgr.writeText(rootDir + "/source/docs/readme.txt", "fresh", false)
        fileMgr.ensureDir(rootDir + "/copies/source/docs")
        fileMgr.ensureDir(rootDir + "/copies/source/keep")
        fileMgr.writeText(rootDir + "/copies/source/docs/readme.txt", "old", false)
        fileMgr.writeText(rootDir + "/copies/source/keep/existing.txt", "keep-me", false)

        var cfg = AppConfig()
        cfg.localRootDir = rootDir
        cfg.tempDir = "/tmp/${scope}_temp"
        cfg.logDir = "/tmp/${scope}_logs"
        cfg.deviceRegistryFile = "/tmp/${scope}_registry.json"

        let server = CoreServer(cfg, profile: coreProductProfile())
        try {
            server.start()
            let task = server.createTransferTask("local", "local", "/source", "/copies")
            let finalTask = waitForTask(server, task.id)

            @Assert(taskStatusToString(finalTask.status), "completed")
            @Assert(fileMgr.readText(rootDir + "/copies/source/docs/readme.txt"), "fresh")
            @Assert(fileMgr.readText(rootDir + "/copies/source/keep/existing.txt"), "keep-me")
            @Assert(FileInfo(rootDir + "/copies/source/keep").isDirectory(), true)
        } finally {
            server.stop()
        }
    }
}

func waitForTask(server: CoreServer, taskId: String): TransferTask {
    var loops: Int64 = 0
    while (loops < 200) {
        match (server.getTask(taskId)) {
            case Some(task) =>
                let status = taskStatusToString(task.status)
                if (status == "completed" || status == "failed" || status == "cancelled") {
                    return task
                }
            case None => ()
        }
        sleep(Duration.millisecond * 50)
        loops += 1
    }
    throw Exception("task timeout: ${taskId}")
}
