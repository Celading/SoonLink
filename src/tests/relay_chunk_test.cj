package soonlnk.tests

import soonlnk.api2.*
import soonlnk.commons.*
import soonlnk.features.*
import std.fs.remove
import std.unittest.*
import std.unittest.testmacro.*

@Test
public class RelayChunk_test {
    @TestCase
    public func relayPendingWhenNotWhitelisted(): Unit {
        let scope = testTempToken("soonlink_relay_pending")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        relay.setDeviceOnlineChecker({ _id: String => true })
        relay.setWriteHandler({ _device: String, _path: String, _payload: Array<UInt8> => true })

        let job = relay.createJobFromPayload("A", "B", "/recv", "a.txt", stringToBytes("abc"))
        @Assert(job.status, "pending_approval")
    }

    @TestCase
    public func relayDispatchWhenWhitelistedAndOnline(): Unit {
        let scope = testTempToken("soonlink_relay_dispatch")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        relay.setDeviceOnlineChecker({ _id: String => true })
        relay.setWriteHandler({ _device: String, _path: String, _payload: Array<UInt8> => true })
        let _ = relay.upsertRule("*", "B", true)

        let job = relay.createJobFromPayload("A", "B", "/recv", "b.txt", stringToBytes("relay-ok"))
        relay.tick()

        match (relay.getJob(job.id)) {
            case Some(found) =>
                @Assert(found.status, "delivered")
            case None => @Assert(false)
        }
    }

    @TestCase
    public func relayWhitelistToggleAndRemove(): Unit {
        let scope = testTempToken("soonlink_relay_toggle")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        relay.setDeviceOnlineChecker({ _id: String => true })
        relay.setWriteHandler({ _device: String, _path: String, _payload: Array<UInt8> => true })
        let _ = relay.upsertRule("*", "B", true)

        match (relay.setRuleEnabled("*", "B", false)) {
            case Some(rule) => @Assert(rule.enabled, false)
            case None => @Assert(false)
        }

        let job = relay.createJobFromPayload("A", "B", "/recv", "rule.txt", stringToBytes("blocked"))
        @Assert(job.status, "pending_approval")

        let removed = relay.removeRule("*", "B")
        @Assert(removed)
        @Assert(relay.listRules("B").size, 0)
    }

    @TestCase
    public func relayCleanupJobsByStatus(): Unit {
        let scope = testTempToken("soonlink_relay_cleanup")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        relay.setDeviceOnlineChecker({ _id: String => true })
        relay.setWriteHandler({ _device: String, _path: String, _payload: Array<UInt8> => false })
        let _ = relay.upsertRule("*", "B", true)

        let failedJob = relay.createJobFromPayload("A", "B", "/recv", "failed.txt", stringToBytes("payload"))
        relay.tick()
        let removed = relay.cleanupJobs("cached", currentTimestamp() + 1)
        @Assert(removed, 1)
        match (relay.getJob(failedJob.id)) {
            case Some(_job) => @Assert(false)
            case None => @Assert(true)
        }
    }

    @TestCase
    public func relayDispatchComposesDirectoryTargetWithFileName(): Unit {
        let scope = testTempToken("soonlink_relay_dispatch_path")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let writtenPathFile = "/tmp/${scope}_written_path.txt"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        let fileMgr = LocalFileMgr()

        relay.setDeviceOnlineChecker({ _id: String => true })
        relay.setWriteHandler({ _device: String, path: String, _payload: Array<UInt8> =>
            try {
                fileMgr.writeText(writtenPathFile, path, false)
                true
            } catch (_: Exception) {
                false
            }
        })
        let _ = relay.upsertRule("*", "B", true)

        let job = relay.createJobFromPayload("A", "B", "/recv", "named.txt", stringToBytes("payload"))
        relay.tick()

        @Assert(fileMgr.readText(writtenPathFile), "/recv/named.txt")
        match (relay.getJob(job.id)) {
            case Some(found) =>
                @Assert(found.status, "delivered")
                match (relay.cacheDescriptor(job.id)) {
                    case Some(_) => @Assert(false)
                    case None => @Assert(true)
                }
            case None => @Assert(false)
        }
    }

    @TestCase
    public func relayRestoreWritesCacheBackToTargetDirectory(): Unit {
        let scope = testTempToken("soonlink_relay_restore")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let restoreRoot = "/tmp/${scope}_restore"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        let fileMgr = LocalFileMgr()

        relay.setDeviceOnlineChecker({ _id: String => false })
        relay.setWriteHandler({ _device: String, path: String, payload: Array<UInt8> =>
            try {
                fileMgr.writeBytes(restoreRoot + path, payload, false)
                true
            } catch (_: Exception) {
                false
            }
        })

        let job = relay.createJobFromPayload("A", "B", "/recv", "restore.txt", stringToBytes("restore-body"))
        let restored = relay.restoreJob(job.id, "local", "/downloads")
        @Assert(restored, true)
        @Assert(fileMgr.readText(restoreRoot + "/downloads/restore.txt"), "restore-body")
    }

    @TestCase
    public func textRecordCachesAsTxtAndDeleteRemovesRecordOnly(): Unit {
        let scope = testTempToken("soonlink_relay_text_record")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        let job = relay.createTextRecord("web-client", "meeting-note", "line1\nline2")
        @Assert(job.recordKind, "text")
        @Assert(job.status, "cached")
        @Assert(job.targetDevice, "")
        @Assert(strEndsWith(job.fileName, ".txt"))

        match (relay.cacheDescriptor(job.id)) {
            case Some((_cachePath, fileName)) =>
                @Assert(fileName, "meeting-note.txt")
            case None =>
                @Assert(false)
        }

        match (relay.retryJob(job.id)) {
            case Some(found) =>
                @Assert(found.status, "cached")
                @Assert(found.message, "text record retained")
            case None =>
                @Assert(false)
        }

        let deleted = relay.deleteJob(job.id)
        @Assert(deleted, true)
        match (relay.getJob(job.id)) {
            case Some(_job) => @Assert(false)
            case None => @Assert(true)
        }
    }

    @TestCase
    public func chunkSessionCompleteWritesMergedFile(): Unit {
        let scope = testTempToken("soonlink_chunk")
        let tempDir = "/tmp/${scope}_temp"
        let outputPath = "/tmp/${scope}_target.bin"
        let fileMgr = LocalFileMgr()

        let chunk = ChunkTransferFeature(tempDir)
        chunk.setWriteHandler({ _device: String, _path: String, payload: Array<UInt8>, offset: Int64 =>
            try {
                fileMgr.writeBytes(outputPath, payload, offset > 0)
                true
            } catch (_: Exception) {
                false
            }
        })

        let session = chunk.createSession("node-a", "node-b", "/target", "demo.txt", 11, 6)
        let w0 = chunk.writeChunk(session.id, 0, stringToBytes("hello "))
        let w1 = chunk.writeChunk(session.id, 1, stringToBytes("world"))
        @Assert(w0.success)
        @Assert(w1.success)

        let completed = chunk.completeSession(session.id)
        @Assert(completed.success)
        @Assert(completed.bytesWritten, 11)
        @Assert(completed.targetPath, "/target/demo.txt")

        let merged = fileMgr.readText(outputPath)
        @Assert(merged, "hello world")

        remove(outputPath)
    }

    @TestCase
    public func chunkSessionCompleteKeepsExplicitTargetFilePath(): Unit {
        let scope = testTempToken("soonlink_chunk_explicit")
        let tempDir = "/tmp/${scope}_temp"
        let outputPath = "/tmp/${scope}_target.bin"
        let fileMgr = LocalFileMgr()

        let chunk = ChunkTransferFeature(tempDir)
        chunk.setWriteHandler({ _device: String, _path: String, payload: Array<UInt8>, offset: Int64 =>
            try {
                fileMgr.writeBytes(outputPath, payload, offset > 0)
                true
            } catch (_: Exception) {
                false
            }
        })

        let session = chunk.createSession("node-a", "node-b", "/target/demo.txt", "demo.txt", 11, 6)
        let w0 = chunk.writeChunk(session.id, 0, stringToBytes("hello "))
        let w1 = chunk.writeChunk(session.id, 1, stringToBytes("world"))
        @Assert(w0.success)
        @Assert(w1.success)

        let completed = chunk.completeSession(session.id)
        @Assert(completed.success)
        @Assert(completed.bytesWritten, 11)
        @Assert(completed.targetPath, "/target/demo.txt")

        let merged = fileMgr.readText(outputPath)
        @Assert(merged, "hello world")

        remove(outputPath)
    }

    @TestCase
    public func decodeChunkFileIdAcceptsPercentEncodedParam(): Unit {
        let encoded = "local%7C~sample-root~demo.txt"
        match (decodeChunkFileId(encoded)) {
            case Some((deviceId, path)) =>
                @Assert(deviceId, "local")
                @Assert(path, "/sample-root/demo.txt")
            case None =>
                @Assert(false)
        }
    }
}
