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
        let content = "备案号\n你好，SoonLink"

        let job = relay.createTextRecord("web-client", "", content, "/notes/tmpSL")
        @Assert(job.recordKind, "text")
        @Assert(job.status, "cached")
        @Assert(job.targetDevice, "")
        @Assert(job.targetPath, "/notes/tmpSL")
        @Assert(strEndsWith(job.fileName, ".txt"))

        match (relay.cacheDescriptor(job.id)) {
            case Some((cachePath, fileName)) =>
                @Assert(strStartsWith(fileName, "tmpTXT-"), true)
                @Assert(LocalFileMgr().readText(cachePath), content)
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
    public func textSessionAppendsMessagesIntoOneTxtRecord(): Unit {
        let scope = testTempToken("soonlink_relay_text_session")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        let first = relay.createTextRecord("node-a", "team-room", "第一条消息", "/chat/tmpSL", "room-main")
        let second = relay.createTextRecord("node-b", "team-room", "第二条消息", "/chat/tmpSL", "room-main")

        @Assert(first.id, second.id)
        @Assert(second.sessionId, "room-main")
        @Assert(second.fileName, "team-room.txt")

        match (relay.cacheDescriptor(second.id)) {
            case Some((cachePath, _fileName)) =>
                let text = LocalFileMgr().readText(cachePath)
                @Assert(text.contains("node-a"), true)
                @Assert(text.contains("第一条消息"), true)
                @Assert(text.contains("node-b"), true)
                @Assert(text.contains("第二条消息"), true)
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    public func textSessionManifestRestoresAfterColdStart(): Unit {
        let scope = testTempToken("soonlink_relay_text_session_restore")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let first = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        let created = first.createTextRecord("node-a", "team-room", "冷启动前", "/chat/tmpSL", "room-main")
        let _ = first.createTextRecord("node-b", "team-room", "冷启动后仍应读取", "/chat/tmpSL", "room-main")

        let second = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        match (second.getJob(created.id)) {
            case Some(restored) =>
                @Assert(restored.recordKind, "text")
                @Assert(restored.sessionId, "room-main")
                @Assert(restored.fileName, "team-room.txt")
                match (second.cacheDescriptor(restored.id)) {
                    case Some((cachePath, _fileName)) =>
                        let text = LocalFileMgr().readText(cachePath)
                        @Assert(text.contains("冷启动前"), true)
                        @Assert(text.contains("冷启动后仍应读取"), true)
                    case None =>
                        @Assert(false)
                }
            case None =>
                @Assert(false)
        }

        let rooms = second.listRooms()
        var foundRoom = false
        for (room in rooms) {
            if (room.roomId == "room-main") {
                foundRoom = true
                @Assert(room.title, "team-room.txt")
                @Assert(room.participantIdentityIds.size, 2)
            }
        }
        @Assert(foundRoom, true)

        let messages = second.listRoomMessages("room-main", 20)
        @Assert(messages.size, 2)
        @Assert(messages[0].roomId, "room-main")
        @Assert(messages[0].senderIdentityId.contains("node-a"), true)
        @Assert(messages[0].body.contains("冷启动前"), true)
        @Assert(messages[1].senderIdentityId.contains("node-b"), true)
        @Assert(messages[1].body.contains("冷启动后仍应读取"), true)
    }

    @TestCase
    public func roomMessageStoreSurvivesColdStartWithoutTextCache(): Unit {
        let scope = testTempToken("soonlink_relay_room_store")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let first = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        let created = first.createTextRecord("node-a", "store-room", "store 第一条", "/chat/tmpSL", "room-store")
        let _ = first.createTextRecord("node-b", "store-room", "store 第二条", "/chat/tmpSL", "room-store")

        match (first.cacheDescriptor(created.id)) {
            case Some((cachePath, _fileName)) =>
                remove(cachePath)
            case None =>
                @Assert(false)
        }

        let second = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        match (second.getJob(created.id)) {
            case Some(_restored) => @Assert(false)
            case None => @Assert(true)
        }

        let rooms = second.listRooms()
        var foundRoom = false
        for (room in rooms) {
            if (room.roomId == "room-store") {
                foundRoom = true
                @Assert(room.retentionPolicy, "relay-message-store")
                @Assert(room.participantIdentityIds.size, 2)
            }
        }
        @Assert(foundRoom, true)

        let messages = second.listRoomMessages("room-store", 20)
        @Assert(messages.size, 2)
        @Assert(messages[0].body.contains("store 第一条"), true)
        @Assert(messages[1].body.contains("store 第二条"), true)
        @Assert(messages[1].sourceRecordId, created.id)
    }

    @TestCase
    public func roomMessageMutationSkipsMalformedStoreLines(): Unit {
        let scope = testTempToken("soonlink_relay_room_mutation")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        let job = relay.createRoomTextMessage("ops-room", "operator-a", "ops-log", "manual message")
        @Assert(job.recordKind, "text")
        @Assert(job.sessionId, "ops-room")
        @Assert(job.fileName, "ops-log.txt")

        let logPath = cacheDir + "/relay_messages/ops-room.log"
        LocalFileMgr().writeText(logPath, "bad-line-without-fields\n||||\n", true)

        let second = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        let messages = second.listRoomMessages("ops-room", 20)
        @Assert(messages.size, 1)
        @Assert(messages[0].roomId, "ops-room")
        @Assert(messages[0].body.contains("manual message"), true)
        @Assert(messages[0].senderIdentityId.contains("operator-a"), true)
    }

    @TestCase
    public func localSendAdapterMessageProjectsIntoProtocolRoom(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_adapter")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        let adapters = relay.listChannelAdapters()
        var foundLocalSend = false
        for (adapter in adapters) {
            if (adapter.protocolId == "localsend") {
                foundLocalSend = true
                @Assert(adapter.roomKind, "protocol-room")
                var receivesText = false
                for (capability in adapter.capabilities) {
                    if (capability == "receive-text") {
                        receivesText = true
                    }
                }
                @Assert(receivesText, true)
            }
        }
        @Assert(foundLocalSend, true)

        let message = ChannelAdapterMessage()
        message.protocolId = "localsend"
        message.peerId = "phone-a"
        message.peerDisplayName = "Pixel Phone"
        message.endpoint = "http://192.168.1.50:53317"
        message.body = "hello from localsend"
        message.sourceRecordId = "ls-msg-1"

        let job = relay.createAdapterTextMessage(message)
        @Assert(job.recordKind, "text")
        @Assert(job.sourceProtocolId, "localsend")
        @Assert(job.sourcePeerId, "phone-a")
        @Assert(job.sourceEndpoint, "http://192.168.1.50:53317")
        @Assert(job.sessionId, "adapter-localsend-phone-a")

        let rooms = relay.listRooms()
        var foundRoom = false
        for (room in rooms) {
            if (room.roomId == "adapter-localsend-phone-a") {
                foundRoom = true
                @Assert(room.kind, "protocol-room")
                @Assert(room.transportHints.contains("adapter:localsend"), true)
            }
        }
        @Assert(foundRoom, true)

        let messages = relay.listRoomMessages("adapter-localsend-phone-a", 20)
        @Assert(messages.size, 1)
        @Assert(messages[0].senderKind, "protocol-peer")
        @Assert(messages[0].sourceProtocolId, "localsend")
        @Assert(messages[0].senderIdentityId.contains("phone-a"), true)
        @Assert(messages[0].body.contains("hello from localsend"), true)
    }

    @TestCase
    public func localSendInfoPayloadNormalizesIntoAdapterMessage(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_info")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        let raw = "{\"alias\":\"Cool Carrot\",\"version\":\"2.1\",\"deviceModel\":\"macOS\",\"deviceType\":\"desktop\",\"fingerprint\":\"7360EE65EBEA97EC2CB3A895AD65F51379D7694B1A1CC3B0E1B868E54F119AF1\",\"download\":false}"

        match (parseLocalSendPeerInfoPayload(raw, "https://127.0.0.1:53317", "v2")) {
            case Some(info) =>
                @Assert(info.alias, "Cool Carrot")
                @Assert(info.deviceModel, "macOS")
                @Assert(info.deviceType, "desktop")
                @Assert(info.download, false)
                @Assert(info.peerId, "7360ee65ebea97ec2cb3a895ad65f51379d7694b1a1cc3b0e1b868e54f119af1")

                let message = buildLocalSendInfoChannelAdapterMessage(info, "LocalSend peer online")
                @Assert(message.protocolId, "localsend")
                @Assert(message.peerDisplayName, "Cool Carrot")
                @Assert(message.endpoint, "https://127.0.0.1:53317")

                let job = relay.createAdapterTextMessage(message)
                @Assert(job.sourceProtocolId, "localsend")
                @Assert(job.sourcePeerId, info.peerId)
                @Assert(job.sourceEndpoint, "https://127.0.0.1:53317")
                @Assert(job.sessionId, "adapter-localsend-${info.peerId}")

                let messages = relay.listRoomMessages(job.sessionId, 20)
                @Assert(messages.size, 1)
                @Assert(messages[0].senderKind, "protocol-peer")
                @Assert(messages[0].body.contains("LocalSend peer online"), true)
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    public func localSendRegisterProjectsPeerWithHeartbeatDedup(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_register")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        let raw = "{\"alias\":\"Cool Carrot\",\"version\":\"2.1\",\"deviceModel\":\"macOS\",\"deviceType\":\"desktop\",\"fingerprint\":\"fp-register\",\"protocol\":\"https\",\"port\":53317,\"download\":true}"
        let peerEndpoint = resolveLocalSendPeerEndpointFromEnvelope(raw, "192.168.1.44", "http://127.0.0.1:8081")
        @Assert(peerEndpoint, "https://192.168.1.44:53317")

        match (parseLocalSendPeerInfoPayload(raw, peerEndpoint, "v2")) {
            case Some(info) =>
                match (relay.recordLocalSendPeerRegistration(info, "LocalSend peer registered")) {
                    case Some(job) =>
                        @Assert(job.sourceProtocolId, "localsend")
                        @Assert(job.sourcePeerId, "fp-register")
                        @Assert(job.sourceEndpoint, "https://192.168.1.44:53317")
                        @Assert(job.sessionId, "adapter-localsend-fp-register")
                    case None =>
                        @Assert(false)
                }
                match (relay.recordLocalSendPeerRegistration(info, "LocalSend peer registered")) {
                    case Some(_job) =>
                        @Assert(false)
                    case None => ()
                }
                let messages = relay.listRoomMessages("adapter-localsend-fp-register", 20)
                @Assert(messages.size, 1)
                @Assert(messages[0].body.contains("LocalSend peer registered"), true)
            case None =>
                @Assert(false)
        }
    }

    @TestCase
    public func localSendUploadAndDownloadSessionsBridgeRelayCache(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_file")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        let raw = localSendUploadFixture("Cool Carrot", "fp-local", "hello.txt", 11)

        let upload = relay.prepareLocalSendUpload(raw, "http://127.0.0.1:53317")
        @Assert(upload.sessionId.contains("ls-up-"), true)
        @Assert(upload.peerDisplayName, "Cool Carrot")
        @Assert(upload.tokens.size, 1)
        @Assert(upload.tokens[0].fileId, "file-a")
        @Assert(upload.tokens[0].fileName, "hello.txt")

        let job = relay.receiveLocalSendUpload(upload.sessionId, upload.tokens[0].fileId, upload.tokens[0].token, stringToBytes("hello world"))
        @Assert(job.recordKind, "file")
        @Assert(job.sourceProtocolId, "localsend")
        @Assert(job.sourcePeerId, "fp-local")
        @Assert(job.fileName, "hello.txt")

        let rooms = relay.listRooms()
        var foundProtocolRoom = false
        for (room in rooms) {
            if (room.roomId == "adapter-localsend-fp-local") {
                foundProtocolRoom = true
            }
        }
        @Assert(foundProtocolRoom, true)

        let messages = relay.listRoomMessages("adapter-localsend-fp-local", 20)
        @Assert(messages.size, 1)
        @Assert(messages[0].sourceRecordId, job.id)
        @Assert(messages[0].fileRefs.size, 1)
        @Assert(messages[0].fileRefs[0], job.id)
        @Assert(messages[0].body.contains("LocalSend file received: hello.txt"), true)

        let download = relay.prepareLocalSendDownload(job.id)
        @Assert(download.sessionId.contains("ls-down-"), true)
        @Assert(download.tokens.size, 1)
        @Assert(download.tokens[0].jobId, job.id)
        match (relay.localSendDownloadCacheDescriptor(download.sessionId, download.tokens[0].fileId, download.tokens[0].token)) {
            case Some((path, name)) =>
                @Assert(name, "hello.txt")
                @Assert(LocalFileMgr().readText(path), "hello world")
            case None => @Assert(false)
        }
    }

    @TestCase
    public func localSendPullRequiresDownloadTicket(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_pull_guard")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)

        var rejected = false
        try {
            let _ = relay.pullLocalSendFileFromPeer("http://127.0.0.1:53317", "", "file-a", "token-a", "hello.txt", "Cool Carrot")
        } catch (e: Exception) {
            rejected = e.message.contains("sessionId")
        }
        @Assert(rejected)
    }

    @TestCase
    public func localSendBlacklistRejectsPrepareUpload(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_blacklist")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        relay.configureLocalSendAcceptPolicy("auto", "/tmpSL", "", "fp-blocked")

        var rejected = false
        try {
            let _ = relay.prepareLocalSendUpload(localSendUploadFixture("Bad Pear", "fp-blocked", "bad.txt", 3), "http://127.0.0.1:53317")
        } catch (e: Exception) {
            rejected = e.message.contains("rejected")
        }
        @Assert(rejected)
    }

    @TestCase
    public func localSendWhitelistAutoSavesToDefaultFolder(): Unit {
        let scope = testTempToken("soonlink_relay_localsend_whitelist")
        let cacheDir = "/tmp/${scope}_cache"
        let whitelistFile = "/tmp/${scope}_whitelist.toml"
        let savedPath = "/tmp/${scope}_saved.txt"
        let relay = RelayFeature(cacheDir, 24, "fixed", 1024 * 1024, 10, DefaultDiskProbe(), whitelistFile)
        relay.configureLocalSendAcceptPolicy("whitelist", "/Inbox", "fp-trusted", "")
        relay.setWriteHandler({ device: String, path: String, payload: Array<UInt8> =>
            if (device != "local" || path != "/Inbox/hello.txt") {
                return false
            }
            try {
                LocalFileMgr().writeBytes(savedPath, payload, false)
                true
            } catch (_: Exception) {
                false
            }
        })

        let upload = relay.prepareLocalSendUpload(localSendUploadFixture("Cool Carrot", "fp-trusted", "hello.txt", 11), "http://127.0.0.1:53317")
        @Assert(upload.autoSave)
        @Assert(upload.defaultSaveDir, "/Inbox")

        let job = relay.receiveLocalSendUpload(upload.sessionId, upload.tokens[0].fileId, upload.tokens[0].token, stringToBytes("hello world"))
        @Assert(job.targetDevice, "local")
        @Assert(job.targetPath, "/Inbox")
        @Assert(job.message.contains("auto-saved"), true)
        @Assert(LocalFileMgr().readText(savedPath), "hello world")

        remove(savedPath)
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
        let encoded = "local%7C~workspace~tester~demo.txt"
        match (decodeChunkFileId(encoded)) {
            case Some((deviceId, path)) =>
                @Assert(deviceId, "local")
                @Assert(path, "/workspace/tester/demo.txt")
            case None =>
                @Assert(false)
        }
    }
}

func localSendUploadFixture(alias: String, fingerprint: String, fileName: String, size: Int64): String {
    "{" +
        "\"info\":{\"alias\":\"${alias}\",\"version\":\"2.1\",\"deviceModel\":\"macOS\",\"deviceType\":\"desktop\",\"fingerprint\":\"${fingerprint}\",\"download\":false}," +
        "\"files\":{\"file-a\":{\"id\":\"file-a\",\"fileName\":\"${fileName}\",\"size\":${size},\"fileType\":\"text/plain\",\"sha256\":\"\"}}" +
        "}"
}
