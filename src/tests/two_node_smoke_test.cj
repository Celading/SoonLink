package soonlnk.tests

import soonlnk.commons.*
import soonlnk.master.*
import soonlnk.product.*
import std.fs.FileInfo
import std.random.Random
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class TwoNodeSmoke_test {
    @TestCase
    public func manualEndpointsSupportTwoNodeBrowseAndDirectoryTransfer(): Unit {
        let scope = testTempToken("soonlink_two_node_smoke")
        let rootA = "/tmp/${scope}_node_a"
        let rootB = "/tmp/${scope}_node_b"
        let fileMgr = LocalFileMgr()
        fileMgr.ensureDir(rootA + "/share/docs")
        fileMgr.ensureDir(rootA + "/share/empty-only")
        fileMgr.writeText(rootA + "/share/docs/readme.txt", "hello-from-node-a", false)
        fileMgr.ensureDir(rootB + "/receiver")

        let portSeed = pickTestPortSeed()
        let portA = UInt16(portSeed)
        let portB = UInt16(portSeed + 1)

        var cfgA = AppConfig()
        cfgA.nodeId = "node-a-self"
        cfgA.listenAddr = "127.0.0.1:${portA}"
        cfgA.webPort = portA
        cfgA.discoveryUdpPort = portSeed + 100
        cfgA.localRootDir = rootA
        cfgA.tempDir = "/tmp/${scope}_temp_a"
        cfgA.logDir = "/tmp/${scope}_logs_a"
        cfgA.deviceRegistryFile = "/tmp/${scope}_registry_a.json"
        cfgA.enableMdns = false

        var cfgB = AppConfig()
        cfgB.nodeId = "node-b-self"
        cfgB.listenAddr = "127.0.0.1:${portB}"
        cfgB.webPort = portB
        cfgB.discoveryUdpPort = portSeed + 101
        cfgB.localRootDir = rootB
        cfgB.tempDir = "/tmp/${scope}_temp_b"
        cfgB.logDir = "/tmp/${scope}_logs_b"
        cfgB.deviceRegistryFile = "/tmp/${scope}_registry_b.json"
        cfgB.enableMdns = false

        let serverA = CoreServer(cfgA, profile: defaultRuntimeProfile())
        let serverB = CoreServer(cfgB, profile: defaultRuntimeProfile())
        serverA.setConsoleOutputEnabled(false)
        serverB.setConsoleOutputEnabled(false)
        let webA = WebServer(serverA, portA)
        let webB = WebServer(serverB, portB)

        try {
            serverA.start()
            serverB.start()
            spawn { webA.start() }
            spawn { webB.start() }

            registerRemoteNode(serverA, "node-b", portB)
            registerRemoteNode(serverB, "node-a", portA)

            waitForRemoteEntry(serverA, "node-b", "/", "receiver")
            waitForRemoteEntry(serverB, "node-a", "/", "share")

            let taskA = serverA.createTransferTask("local", "node-b", "/share", "/receiver")
            let finalTaskA = waitForRemoteTask(serverA, taskA.id)
            @Assert(taskStatusToString(finalTaskA.status), "completed")
            @Assert(finalTaskA.sourceIsDir, true)

            @Assert(fileMgr.readText(rootB + "/receiver/share/docs/readme.txt"), "hello-from-node-a")
            @Assert(FileInfo(rootB + "/receiver/share/empty-only").isDirectory(), true)

            let taskB = serverB.createTransferTask("node-a", "local", "/share/docs/readme.txt", "/pulled/readme.txt")
            let finalTaskB = waitForRemoteTask(serverB, taskB.id)
            @Assert(taskStatusToString(finalTaskB.status), "completed")
            @Assert(fileMgr.readText(rootB + "/pulled/readme.txt"), "hello-from-node-a")
        } finally {
            webA.stop()
            webB.stop()
            serverA.stop()
            serverB.stop()
        }
    }
}

func pickTestPortSeed(): Int64 {
    let random = Random()
    var raw = random.nextInt64()
    if (raw < 0) {
        raw = -raw
    }
    24000 + raw % 12000
}

func registerRemoteNode(server: CoreServer, deviceId: String, port: UInt16): Unit {
    let record = DeviceRegistryRecord()
    record.id = deviceId
    record.name = deviceId
    record.deviceType = "remote"
    record.connectorType = "soonlink-http"
    record.ip = "127.0.0.1"
    record.port = Int64(port)
    server.upsertManagedDeviceRecord(record)
    server.setDeviceTrustState(deviceId, "trusted", source: "test")
}

func waitForRemoteEntry(server: CoreServer, deviceId: String, dirPath: String, expectedName: String): Unit {
    var loops: Int64 = 0
    while (loops < 50) {
        let entries = server.listDir(deviceId, dirPath)
        for (entry in entries) {
            if (entry.name == expectedName) {
                return
            }
        }
        sleep(Duration.millisecond * 100)
        loops += 1
    }
    throw Exception("remote entry timeout: ${deviceId}:${dirPath}:${expectedName}")
}

func waitForRemoteTask(server: CoreServer, taskId: String): TransferTask {
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
