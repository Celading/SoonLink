package soonlnk.features

import soonlnk.api2.*
import soonlnk.commons.*
import std.collection.{ArrayList, HashMap}
import std.convert.*
import std.fs.{Directory, FileInfo, remove}
import std.sync.Mutex
import std.unicode.*
import stdx.net.http.{ClientBuilder, HttpRequestBuilder, HttpResponse}

let relayTextRecordMaxBytes: Int64 = 256 * 1024
let relayRoomStoreFileName: String = "relay_rooms.toml"
let relayMessageStoreDirName: String = "relay_messages"

public class RelayFeature {
    let cacheDir: String
    let retentionHours: Int64
    let limitMode: String
    let limitBytes: Int64
    let limitPercent: Int64
    let diskProbe: DiskProbe
    let whitelistStore: TomlConfigStore
    let manifestStore: TomlConfigStore
    let roomStore: TomlConfigStore
    let messageStoreDir: String
    let fileMgr: FileMgr

    let mutex: Mutex = Mutex()
    var jobs: HashMap<String, RelayJob> = HashMap<String, RelayJob>()
    var whitelist: HashMap<String, WhitelistRule> = HashMap<String, WhitelistRule>()
    var channelAdapters: HashMap<String, ChannelAdapter> = HashMap<String, ChannelAdapter>()
    var localSendUploadSessions: HashMap<String, LocalSendSession> = HashMap<String, LocalSendSession>()
    var localSendDownloadSessions: HashMap<String, LocalSendSession> = HashMap<String, LocalSendSession>()
    var localSendPeerRegistrationSeenAt: HashMap<String, Int64> = HashMap<String, Int64>()
    var localSendAcceptPolicy: String = "manual"
    var localSendDefaultSaveDir: String = "/tmpSL"
    var localSendWhitelist: String = ""
    var localSendBlacklist: String = ""
    var onlineChecker: ?(String) -> Bool = None
    var writeHandler: ?(String, String, Array<UInt8>) -> Bool = None

    public init(
        cacheDir: String,
        retentionHours: Int64,
        limitMode: String,
        limitBytes: Int64,
        limitPercent: Int64,
        diskProbe: DiskProbe,
        whitelistFile: String
    ) {
        this.cacheDir = cacheDir
        this.retentionHours = if (retentionHours > 0) { retentionHours } else { 24 }
        this.limitMode = normalizeLimitMode(limitMode)
        this.limitBytes = if (limitBytes > 0) { limitBytes } else { 20 * 1024 * 1024 * 1024 }
        this.limitPercent = if (limitPercent > 0) { limitPercent } else { 10 }
        this.diskProbe = diskProbe
        this.whitelistStore = TomlConfigStore(whitelistFile)
        this.manifestStore = TomlConfigStore(joinPaths(cacheDir, "relay_manifest.toml"))
        this.roomStore = TomlConfigStore(joinPaths(cacheDir, relayRoomStoreFileName))
        this.messageStoreDir = joinPaths(cacheDir, relayMessageStoreDirName)
        this.fileMgr = LocalFileMgr()

        fileMgr.ensureDir(cacheDir)
        fileMgr.ensureDir(messageStoreDir)
        registerDefaultChannelAdapters()
        loadWhitelist()
        loadPersistedTextJobs()
    }

    public func setDeviceOnlineChecker(checker: (String) -> Bool): Unit {
        synchronized(mutex) {
            onlineChecker = checker
        }
    }

    public func setWriteHandler(handler: (String, String, Array<UInt8>) -> Bool): Unit {
        synchronized(mutex) {
            writeHandler = handler
        }
    }

    public func configureLocalSendAcceptPolicy(policy: String, defaultSaveDir: String, whitelist: String, blacklist: String): Unit {
        synchronized(mutex) {
            localSendAcceptPolicy = normalizeLocalSendAcceptPolicy(policy)
            localSendDefaultSaveDir = if (defaultSaveDir.trimAscii().size > 0) { defaultSaveDir.trimAscii() } else { "/tmpSL" }
            localSendWhitelist = whitelist
            localSendBlacklist = blacklist
        }
    }

    public func localSendPolicySnapshot(): JsonObject {
        synchronized(mutex) {
            JsonObject()
                .put("acceptPolicy", localSendAcceptPolicy)
                .put("defaultSaveDir", localSendDefaultSaveDir)
                .put("whitelist", localSendWhitelist)
                .put("blacklist", localSendBlacklist)
        }
    }

    public func createJobFromPayload(
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        payload: Array<UInt8>
    ): RelayJob {
        createRelayRecord("file", sourceDevice, targetDevice, targetPath, fileName, payload, true, "")
    }

    public func createTextRecord(sourceDevice: String, fileName: String, content: String): RelayJob {
        createTextRecord(sourceDevice, fileName, content, "/tmpSL")
    }

    public func createTextRecord(sourceDevice: String, fileName: String, content: String, targetPath: String): RelayJob {
        createTextRecord(sourceDevice, fileName, content, targetPath, "")
    }

    public func createTextRecord(sourceDevice: String, fileName: String, content: String, targetPath: String, sessionId: String): RelayJob {
        let payload = stringToBytes(content)
        if (payload.size == 0) {
            throw Exception("文本内容不能为空")
        }
        if (payload.size > relayTextRecordMaxBytes) {
            throw Exception("临时文本缓存最多支持 256 KiB，请改走文件中转")
        }
        let normalizedSessionId = normalizeRelayTextSessionId(sessionId)
        let normalizedFileName = normalizeRelayTextRecordName(if (fileName.trimAscii().size > 0) { fileName } else { normalizedSessionId })
        var job: RelayJob
        if (normalizedSessionId.size > 0) {
            job = appendRelayTextSessionRecord(sourceDevice, normalizedFileName, content, targetPath, normalizedSessionId)
        } else {
            job = createRelayRecord("text", sourceDevice, "", normalizeRelayTextTargetPath(targetPath), normalizedFileName, payload, false, "")
        }
        appendStoredMessageForTextJob(job, sourceDevice, content, 0)
        job
    }

    public func registerChannelAdapter(adapter: ChannelAdapter): ChannelAdapter {
        let normalized = normalizeChannelProtocolId(adapter.protocolId)
        if (normalized.size == 0) {
            throw Exception("频道协议ID不能为空")
        }
        adapter.protocolId = normalized
        if (adapter.displayName.trimAscii().size == 0) {
            adapter.displayName = normalized
        }
        if (adapter.trustShape.trimAscii().size == 0) {
            adapter.trustShape = "manual"
        }
        if (adapter.receiveMode.trimAscii().size == 0) {
            adapter.receiveMode = "pull-or-ingress"
        }
        if (adapter.roomKind.trimAscii().size == 0) {
            adapter.roomKind = "protocol-room"
        }
        synchronized(mutex) {
            channelAdapters.add(adapter.protocolId, adapter)
        }
        adapter
    }

    public func listChannelAdapters(): ArrayList<ChannelAdapter> {
        let out = ArrayList<ChannelAdapter>()
        synchronized(mutex) {
            for ((_, adapter) in channelAdapters) {
                out.add(adapter)
            }
        }
        out
    }

    public func getChannelAdapter(protocolId: String): ?ChannelAdapter {
        let normalized = normalizeChannelProtocolId(protocolId)
        synchronized(mutex) {
            channelAdapters.get(normalized)
        }
    }

    public func createAdapterTextMessage(message: ChannelAdapterMessage): RelayJob {
        let normalized = normalizeChannelAdapterMessage(message)
        let adapter = getChannelAdapter(normalized.protocolId)
        match (adapter) {
            case Some(_adapter) => ()
            case None => throw Exception("频道协议未注册: ${normalized.protocolId}")
        }
        if (normalized.body.trimAscii().size == 0) {
            throw Exception("频道消息内容不能为空")
        }

        let sessionId = channelAdapterRoomId(normalized.protocolId, normalized.peerId)
        let fileName = channelAdapterRoomFileName(normalized.protocolId, normalized.peerDisplayName)
        let sourceDevice = channelAdapterSourceDevice(normalized.protocolId, normalized.peerDisplayName)
        let job = appendRelayTextSessionRecord(sourceDevice, fileName, normalized.body, "/tmpSL", sessionId)

        synchronized(mutex) {
            if (let Some(stored) <- jobs.get(job.id)) {
                stored.sourceProtocolId = normalized.protocolId
                stored.sourcePeerId = normalized.peerId
                stored.sourceEndpoint = normalized.endpoint
                stored.message = "adapter message cached from ${normalized.protocolId}"
                stored.updatedAt = currentTimestamp()
                persistTextManifestLocked()
                appendStoredMessageForTextJob(stored, sourceDevice, normalized.body, normalized.createdAt, normalized.sourceRecordId)
                return stored
            }
        }
        job.sourceProtocolId = normalized.protocolId
        job.sourcePeerId = normalized.peerId
        job.sourceEndpoint = normalized.endpoint
        appendStoredMessageForTextJob(job, sourceDevice, normalized.body, normalized.createdAt, normalized.sourceRecordId)
        job
    }

    public func recordLocalSendPeerRegistration(info: LocalSendPeerInfo, body: String): ?RelayJob {
        var peerKey = info.peerId.trimAscii()
        if (peerKey.size == 0) {
            peerKey = info.fingerprint.trimAscii()
        }
        if (peerKey.size == 0) {
            peerKey = info.alias.trimAscii()
        }
        if (peerKey.size == 0) {
            return None
        }

        let now = currentTimestamp()
        var shouldRecord = false
        synchronized(mutex) {
            match (localSendPeerRegistrationSeenAt.get(peerKey)) {
                case Some(lastSeenAt) =>
                    if (now - lastSeenAt >= 60) {
                        shouldRecord = true
                    }
                case None => shouldRecord = true
            }
            localSendPeerRegistrationSeenAt.add(peerKey, now)
        }
        if (!shouldRecord) {
            return None
        }

        let messageBody = if (body.trimAscii().size > 0) { body.trimAscii() } else { "LocalSend peer registered" }
        let template = buildLocalSendInfoChannelAdapterMessage(info, messageBody)
        Some(createAdapterTextMessage(template))
    }

    public func createRoomTextMessage(roomId: String, sourceDevice: String, fileName: String, content: String): RelayJob {
        let normalizedRoomId = normalizeRelayTextSessionId(roomId)
        if (normalizedRoomId.size == 0) {
            throw Exception("频道窗口ID不能为空")
        }
        let sender = if (sourceDevice.trimAscii().size > 0) { sourceDevice.trimAscii() } else { "web-client" }
        let recordName = if (fileName.trimAscii().size > 0) { fileName.trimAscii() } else { normalizedRoomId }
        createTextRecord(sender, recordName, content, "/tmpSL", normalizedRoomId)
    }

    public func prepareLocalSendUpload(raw: String, endpoint: String): LocalSendSession {
        let peer = parseLocalSendPeerInfoFromEnvelope(raw, endpoint, "v2")
        let files = parseLocalSendFileOffers(raw)
        if (files.size == 0) {
            throw Exception("LocalSend prepare-upload must include at least one file")
        }

        let decision = decideLocalSendAccept(peer, endpoint)
        if (decision == "reject") {
            throw Exception("LocalSend peer rejected by accept policy")
        }

        let session = LocalSendSession()
        session.sessionId = "ls-up-" + generateId()
        session.createdAt = currentTimestamp()
        session.acceptPolicy = decision
        session.autoSave = decision == "auto-save"
        session.defaultSaveDir = currentLocalSendDefaultSaveDir()
        match (peer) {
            case Some(info) =>
                session.peerId = if (info.peerId.size > 0) { info.peerId } else { normalizeRelayTextSessionId(info.alias) }
                session.peerDisplayName = if (info.alias.size > 0) { info.alias } else { session.peerId }
                session.endpoint = info.endpoint
            case None =>
                session.peerId = "unknown-localsend-peer"
                session.peerDisplayName = "LocalSend Peer"
                session.endpoint = endpoint.trimAscii()
        }

        for (file in files) {
            let token = LocalSendFileToken()
            token.fileId = normalizeRelayTextSessionId(if (file.fileId.size > 0) { file.fileId } else { file.fileName })
            token.fileName = normalizeFileName(file.fileName)
            token.size = file.size
            token.token = "lst-" + generateId()
            session.tokens.add(token)
        }

        synchronized(mutex) {
            localSendUploadSessions.add(session.sessionId, session)
        }
        session
    }

    public func receiveLocalSendUpload(sessionId: String, fileId: String, token: String, payload: Array<UInt8>): RelayJob {
        let normalizedSessionId = sessionId.trimAscii()
        let normalizedFileId = normalizeRelayTextSessionId(fileId)
        let normalizedToken = token.trimAscii()
        var session: ?LocalSendSession = None
        var fileToken: ?LocalSendFileToken = None
        var peerId = ""
        var peerDisplayName = ""
        var endpoint = ""
        var autoSave = false
        var defaultSaveDir = "/tmpSL"
        synchronized(mutex) {
            session = localSendUploadSessions.get(normalizedSessionId)
        }
        match (session) {
            case Some(s) =>
                peerId = s.peerId
                peerDisplayName = s.peerDisplayName
                endpoint = s.endpoint
                autoSave = s.autoSave
                defaultSaveDir = s.defaultSaveDir
                for (candidate in s.tokens) {
                    if (candidate.fileId == normalizedFileId && candidate.token == normalizedToken) {
                        fileToken = Some(candidate)
                    }
                }
            case None => throw Exception("LocalSend upload session not found")
        }
        match (fileToken) {
            case Some(t) =>
                if (payload.size <= 0) {
                    throw Exception("LocalSend upload payload is empty")
                }
                let sourceDevice = "localsend:${if (peerDisplayName.size > 0) { peerDisplayName } else { peerId }}"
                let job = createRelayRecord("file", sourceDevice, "", "/", t.fileName, payload, false, "")
                job.sourceProtocolId = "localsend"
                job.sourcePeerId = peerId
                job.sourceEndpoint = endpoint
                job.message = "LocalSend file cached"
                job.updatedAt = currentTimestamp()
                if (autoSave) {
                    let savedPath = composeRelayTargetFilePath(defaultSaveDir, t.fileName)
                    if (autoSaveLocalSendPayload(savedPath, payload)) {
                        job.targetDevice = "local"
                        job.targetPath = defaultSaveDir
                        job.message = "LocalSend file cached and auto-saved to local:${savedPath}"
                    } else {
                        job.message = "LocalSend file cached; auto-save failed"
                    }
                    job.updatedAt = currentTimestamp()
                }

                let message = ChannelAdapterMessage()
                message.protocolId = "localsend"
                message.peerId = peerId
                message.peerDisplayName = peerDisplayName
                message.endpoint = endpoint
                message.body = "LocalSend file received: ${t.fileName} (${formatBytes(payload.size)})"
                message.contentType = "text/plain"
                message.sourceRecordId = job.id
                let _ = createAdapterTextMessage(message)
                job
            case None => throw Exception("LocalSend upload token invalid")
        }
    }

    public func cancelLocalSendUpload(sessionId: String): Bool {
        let normalized = sessionId.trimAscii()
        if (normalized.size == 0) {
            return false
        }
        synchronized(mutex) {
            match (localSendUploadSessions.get(normalized)) {
                case Some(_s) =>
                    localSendUploadSessions.remove(normalized)
                    true
                case None => false
            }
        }
    }

    public func prepareLocalSendDownload(jobId: String): LocalSendSession {
        let session = LocalSendSession()
        session.sessionId = "ls-down-" + generateId()
        session.peerId = "soonlink-local"
        session.peerDisplayName = "SoonLink Relay"
        session.endpoint = ""
        session.createdAt = currentTimestamp()
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (jobId.trimAscii().size > 0 && id != jobId.trimAscii()) {
                    continue
                }
                refreshCacheState(job)
                if (!canAccessCache(job)) {
                    continue
                }
                let token = LocalSendFileToken()
                token.fileId = normalizeRelayTextSessionId(id)
                token.jobId = id
                token.fileName = job.fileName
                token.size = job.bytes
                token.token = "lsd-" + generateId()
                session.tokens.add(token)
            }
            if (session.tokens.size > 0) {
                localSendDownloadSessions.add(session.sessionId, session)
            }
        }
        if (session.tokens.size == 0) {
            throw Exception("No relay cache file available for LocalSend download")
        }
        session
    }

    public func localSendDownloadCacheDescriptor(sessionId: String, fileId: String, token: String): ?(String, String) {
        let normalizedSessionId = sessionId.trimAscii()
        let normalizedFileId = normalizeRelayTextSessionId(fileId)
        let normalizedToken = token.trimAscii()
        synchronized(mutex) {
            match (localSendDownloadSessions.get(normalizedSessionId)) {
                case Some(session) =>
                    for (candidate in session.tokens) {
                        if (candidate.fileId == normalizedFileId && candidate.token == normalizedToken) {
                            match (jobs.get(candidate.jobId)) {
                                case Some(job) =>
                                    refreshCacheState(job)
                                    if (canAccessCache(job)) {
                                        return Some((job.cachePath, job.fileName))
                                    }
                                case None => ()
                            }
                        }
                    }
                case None => ()
            }
        }
        None
    }

    public func sendLocalSendJobToPeer(endpoint: String, jobId: String, alias: String, fingerprint: String, deviceModel: String, deviceType: String): LocalSendOutboundResult {
        let remoteEndpoint = normalizeLocalSendOutboundEndpoint(endpoint)
        if (remoteEndpoint.size == 0) {
            throw Exception("LocalSend outbound endpoint must start with http://")
        }

        var cachePath = ""
        var fileName = ""
        var bytes: Int64 = 0
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    if (!canAccessCache(job)) {
                        throw Exception("relay cache unavailable for LocalSend outbound")
                    }
                    cachePath = job.cachePath
                    fileName = if (job.fileName.trimAscii().size > 0) { job.fileName } else { "soonlink-relay.bin" }
                    bytes = job.bytes
                case None => throw Exception("relay job not found")
            }
        }

        let payload = fileMgr.readBytes(cachePath)
        let fileId = normalizeLocalSendOutboundFileId(jobId)
        let prepareBody = buildLocalSendOutboundPrepareBody(
            fileId,
            fileName,
            if (bytes > 0) { bytes } else { payload.size },
            alias,
            fingerprint,
            deviceModel,
            deviceType
        )
        let result = LocalSendOutboundResult()
        result.remoteEndpoint = remoteEndpoint
        result.jobId = jobId
        result.fileId = fileId

        let client = ClientBuilder().build()
        try {
            let prepareReq = HttpRequestBuilder()
                .post()
                .url(remoteEndpoint + "/api/localsend/v2/prepare-upload")
                .header("content-type", "application/json")
                .body(prepareBody)
                .build()
            let prepareResp = client.send(prepareReq)
            let prepareStatus = Int64(prepareResp.status)
            let prepareRespBody = readLocalSendHttpBody(prepareResp)
            prepareResp.close()
            if (prepareStatus < 200 || prepareStatus >= 300) {
                result.statusCode = prepareStatus
                result.responseBody = prepareRespBody
                result.message = "LocalSend prepare-upload failed"
                return result
            }

            let sessionId = parseJsonString(prepareRespBody, "sessionId") ?? ""
            let token = parseJsonString(prepareRespBody, fileId) ?? ""
            if (sessionId.trimAscii().size == 0 || token.trimAscii().size == 0) {
                result.statusCode = prepareStatus
                result.responseBody = prepareRespBody
                result.message = "LocalSend prepare-upload response missing session/token"
                return result
            }

            result.sessionId = sessionId
            result.token = token
            let uploadReq = HttpRequestBuilder()
                .post()
                .url(remoteEndpoint + "/api/localsend/v2/upload?sessionId=" + sessionId + "&fileId=" + fileId + "&token=" + token)
                .header("content-type", "application/octet-stream")
                .body(payload)
                .build()
            let uploadResp = client.send(uploadReq)
            let uploadStatus = Int64(uploadResp.status)
            let uploadRespBody = readLocalSendHttpBody(uploadResp)
            uploadResp.close()

            result.statusCode = uploadStatus
            result.responseBody = uploadRespBody
            result.success = uploadStatus >= 200 && uploadStatus < 300
            result.message = if (result.success) { "LocalSend outbound upload completed" } else { "LocalSend outbound upload failed" }
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    job.updatedAt = currentTimestamp()
                    job.message = result.message + " -> " + remoteEndpoint
                }
            }
            result
        } finally {
            client.close()
        }
    }

    public func pullLocalSendFileFromPeer(endpoint: String, sessionId: String, fileId: String, token: String, fileName: String, peerDisplayName: String): LocalSendOutboundResult {
        let remoteEndpoint = normalizeLocalSendOutboundEndpoint(endpoint)
        if (remoteEndpoint.size == 0) {
            throw Exception("LocalSend pull endpoint must start with http://")
        }
        let normalizedSessionId = sessionId.trimAscii()
        let normalizedFileId = normalizeRelayTextSessionId(fileId)
        let normalizedToken = token.trimAscii()
        if (normalizedSessionId.size == 0 || normalizedFileId.size == 0 || normalizedToken.size == 0) {
            throw Exception("LocalSend pull requires sessionId, fileId, and token")
        }

        let result = LocalSendOutboundResult()
        result.remoteEndpoint = remoteEndpoint
        result.fileId = normalizedFileId
        result.sessionId = normalizedSessionId
        result.token = normalizedToken

        let client = ClientBuilder().build()
        try {
            let downloadUrl = remoteEndpoint +
                "/api/localsend/v2/download?sessionId=" + urlEncodeLocalSendQuery(normalizedSessionId) +
                "&fileId=" + urlEncodeLocalSendQuery(normalizedFileId) +
                "&token=" + urlEncodeLocalSendQuery(normalizedToken)
            let downloadReq = HttpRequestBuilder()
                .get()
                .url(downloadUrl)
                .build()
            let downloadResp = client.send(downloadReq)
            let status = Int64(downloadResp.status)
            let payload = readLocalSendHttpBytes(downloadResp)
            downloadResp.close()

            result.statusCode = status
            if (status < 200 || status >= 300) {
                result.responseBody = String.fromUtf8(payload)
                result.message = "LocalSend pull download failed"
                return result
            }
            if (payload.size <= 0) {
                result.message = "LocalSend pull download returned empty payload"
                return result
            }

            let displayName = if (peerDisplayName.trimAscii().size > 0) { peerDisplayName.trimAscii() } else { "LocalSend Peer" }
            let pulledFileName = if (fileName.trimAscii().size > 0) { fileName.trimAscii() } else { normalizedFileId + ".bin" }
            let job = createRelayRecord("file", "localsend:${displayName}", "", "/", pulledFileName, payload, false, "")
            job.sourceProtocolId = "localsend"
            var sourcePeerId = displayName.trimAscii()
            if (sourcePeerId.size == 0) {
                sourcePeerId = normalizedFileId
            }
            if (sourcePeerId.size == 0) {
                sourcePeerId = remoteEndpoint
            }
            job.sourcePeerId = sourcePeerId
            job.sourceEndpoint = remoteEndpoint
            job.message = "LocalSend file pulled from peer"
            job.updatedAt = currentTimestamp()

            let message = ChannelAdapterMessage()
            message.protocolId = "localsend"
            message.peerId = job.sourcePeerId
            message.peerDisplayName = displayName
            message.endpoint = remoteEndpoint
            message.body = "LocalSend file pulled: ${pulledFileName} (${formatBytes(payload.size)})"
            message.contentType = "text/plain"
            message.sourceRecordId = job.id
            let _ = createAdapterTextMessage(message)

            result.success = true
            result.jobId = job.id
            result.responseBody = ""
            result.message = "LocalSend pull download completed"
            result
        } finally {
            client.close()
        }
    }

    func decideLocalSendAccept(peer: ?LocalSendPeerInfo, endpoint: String): String {
        var policy = "manual"
        var whitelist = ""
        var blacklist = ""
        synchronized(mutex) {
            policy = localSendAcceptPolicy
            whitelist = localSendWhitelist
            blacklist = localSendBlacklist
        }
        if (localSendPeerMatches(peer, endpoint, blacklist)) {
            return "reject"
        }
        if (policy == "reject") {
            return "reject"
        }
        if (localSendPeerMatches(peer, endpoint, whitelist)) {
            return "auto-save"
        }
        if (policy == "auto") {
            return "auto-save"
        }
        if (policy == "whitelist") {
            return "reject"
        }
        "manual"
    }

    func currentLocalSendDefaultSaveDir(): String {
        synchronized(mutex) {
            if (localSendDefaultSaveDir.trimAscii().size > 0) {
                return localSendDefaultSaveDir.trimAscii()
            }
        }
        "/tmpSL"
    }

    func autoSaveLocalSendPayload(path: String, payload: Array<UInt8>): Bool {
        var handler: ?(String, String, Array<UInt8>) -> Bool = None
        synchronized(mutex) {
            handler = writeHandler
        }
        match (handler) {
            case Some(h) => h("local", path, payload)
            case None => false
        }
    }

    func appendRelayTextSessionRecord(
        sourceDevice: String,
        fileName: String,
        content: String,
        targetPath: String,
        sessionId: String
    ): RelayJob {
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.recordKind == "text" && job.sessionId == sessionId) {
                    try {
                        fileMgr.writeText(job.cachePath, buildRelayTextSessionAppendText(sourceDevice, content, true), true)
                        let info = FileInfo(job.cachePath)
                        job.bytes = info.size
                        job.status = "cached"
                        job.cacheAvailable = true
                        job.message = "session text appended"
                    } catch (e: Exception) {
                        job.status = "failed"
                        job.cacheAvailable = false
                        job.message = "session append failed: ${e.message}"
                    }
                    job.sourceDevice = if (sourceDevice.trimAscii().size > 0) { sourceDevice.trimAscii() } else { job.sourceDevice }
                    job.targetPath = normalizeRelayTextTargetPath(targetPath)
                    job.updatedAt = currentTimestamp()
                    job.expiresAt = job.updatedAt + retentionHours * 3600
                    persistTextManifestLocked()
                    return job
                }
            }
        }

        createRelayRecord(
            "text",
            sourceDevice,
            "",
            normalizeRelayTextTargetPath(targetPath),
            fileName,
            stringToBytes(buildRelayTextSessionAppendText(sourceDevice, content, false)),
            false,
            sessionId
        )
    }

    func createRelayRecord(
        recordKind: String,
        sourceDevice: String,
        targetDevice: String,
        targetPath: String,
        fileName: String,
        payload: Array<UInt8>,
        attemptDispatch: Bool,
        sessionId: String
    ): RelayJob {
        let job = RelayJob()
        job.id = "relay-" + generateId()
        job.recordKind = recordKind
        job.sessionId = sessionId
        job.sourceDevice = if (sourceDevice.size > 0) { sourceDevice } else { "unknown" }
        job.targetDevice = if (attemptDispatch) { targetDevice } else { "" }
        job.targetPath = if (recordKind == "text") {
            normalizeRelayTextTargetPath(targetPath)
        } else if (attemptDispatch) {
            normalizeRelayPath(targetPath)
        } else {
            "/"
        }
        job.fileName = if (recordKind == "text") { normalizeRelayTextRecordName(fileName) } else { normalizeFileName(fileName) }
        job.createdAt = currentTimestamp()
        job.updatedAt = job.createdAt
        job.expiresAt = job.createdAt + retentionHours * 3600
        job.status = "caching"
        job.cachePath = if (recordKind == "text" && sessionId.size > 0) {
            joinPaths(cacheDir, "${sessionId}_${job.fileName}")
        } else {
            joinPaths(cacheDir, "${job.id}_${job.fileName}")
        }

        try {
            fileMgr.writeBytes(job.cachePath, payload, false)
            job.bytes = payload.size
            job.status = "cached"
            job.cacheAvailable = true
        job.message = if (recordKind == "text") { "text record cached" } else { "cached on relay" }
        } catch (e: Exception) {
            job.status = "failed"
            job.cacheAvailable = false
            job.message = "cache write failed: ${e.message}"
        }

        synchronized(mutex) {
            jobs.add(job.id, job)
            if (job.recordKind == "text") {
                persistTextManifestLocked()
            }
        }

        enforceCapacity()
        if (attemptDispatch) {
            tryDispatch(job.id)
        }
        job
    }

    public func listJobs(): ArrayList<RelayJob> {
        let out = ArrayList<RelayJob>()
        synchronized(mutex) {
            for ((_, job) in jobs) {
                refreshCacheState(job)
                out.add(job)
            }
        }
        out
    }

    public func listRooms(): ArrayList<RelayRoom> {
        let out = ArrayList<RelayRoom>()
        let persisted = loadStoredRooms()
        for (room in persisted) {
            out.add(room)
        }
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.recordKind != "text") {
                    continue
                }
                refreshCacheState(job)
                if (!canAccessCache(job)) {
                    continue
                }
                let roomId = relayTextRoomIdForJob(job)
                var found = false
                for (room in out) {
                    if (room.roomId == roomId) {
                        found = true
                        if (job.createdAt > 0 && (room.createdAt == 0 || job.createdAt < room.createdAt)) {
                            room.createdAt = job.createdAt
                        }
                        if (job.updatedAt > room.updatedAt) {
                            room.updatedAt = job.updatedAt
                        }
                        addRelayRoomParticipant(room, relayIdentityIdForSource(job.sourceDevice))
                        addRelayRoomParticipantsFromJobText(room, job, fileMgr)
                    }
                }
                if (!found) {
                    let room = RelayRoom()
                    room.roomId = roomId
                    room.title = relayTextRoomTitleForJob(job)
                    room.kind = relayTextRoomKindForJob(job)
                    room.createdAt = job.createdAt
                    room.updatedAt = job.updatedAt
                    room.retentionPolicy = "relay-text-cache"
                    room.transportHints = relayTextRoomTransportHintsForJob(job)
                    addRelayRoomParticipant(room, relayIdentityIdForSource(job.sourceDevice))
                    addRelayRoomParticipantsFromJobText(room, job, fileMgr)
                    out.add(room)
                }
            }
        }
        out
    }

    public func listRoomMessages(roomId: String, limit: Int64): ArrayList<RelayMessage> {
        let out = ArrayList<RelayMessage>()
        let selected = ArrayList<RelayJob>()
        let normalizedRoomId = if (roomId.trimAscii().size > 0) { roomId.trimAscii() } else { "default-text-room" }
        let safeLimit = normalizeRelayMessageLimit(limit)
        let stored = loadStoredRoomMessages(normalizedRoomId, safeLimit)
        for (message in stored) {
            if (out.size >= safeLimit) {
                break
            }
            out.add(message)
        }
        if (out.size >= safeLimit) {
            return out
        }
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.recordKind != "text") {
                    continue
                }
                refreshCacheState(job)
                if (!canAccessCache(job)) {
                    continue
                }
                if (relayTextRoomIdForJob(job) == normalizedRoomId) {
                    if (stored.size > 0) {
                        continue
                    }
                    selected.add(job)
                }
            }
        }

        for (job in selected) {
            if (out.size >= safeLimit) {
                break
            }
            try {
                let text = fileMgr.readText(job.cachePath)
                let messages = parseRelayTextMessagesFromJob(job, text, safeLimit - out.size)
                for (message in messages) {
                    if (out.size >= safeLimit) {
                        break
                    }
                    out.add(message)
                }
            } catch (_: Exception) {}
        }
        out
    }

    public func getJob(jobId: String): ?RelayJob {
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    Some(job)
                case None => None
            }
        }
    }

    public func retryJob(jobId: String): ?RelayJob {
        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                if (job.recordKind == "text") {
                    refreshCacheState(job)
                    job.status = if (job.cacheAvailable) { "cached" } else { "failed" }
                    job.message = if (job.cacheAvailable) { "text record retained" } else { "text record missing" }
                    job.updatedAt = currentTimestamp()
                    return Some(job)
                }
                if (job.status == "expired") {
                    refreshCacheState(job)
                    return Some(job)
                }
                job.status = "cached"
                job.message = "retry queued"
                job.updatedAt = currentTimestamp()
                refreshCacheState(job)
            }
        }
        tryDispatch(jobId)
        getJob(jobId)
    }

    public func deleteJob(jobId: String): Bool {
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    jobs.remove(jobId)
                    persistTextManifestLocked()
                    true
                case None => false
            }
        }
    }

    public func cancelJob(jobId: String): Bool {
        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                job.status = "failed"
                job.message = "cancelled by user"
                job.updatedAt = currentTimestamp()
                try {
                    remove(job.cachePath)
                } catch (_: Exception) {}
                job.cacheAvailable = false
                persistTextManifestLocked()
                return true
            }
        }
        false
    }

    public func cacheDescriptor(jobId: String): ?(String, String) {
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    if (!canAccessCache(job)) {
                        return None
                    }
                    return Some((job.cachePath, job.fileName))
                case None => ()
            }
        }
        None
    }

    public func restoreJob(jobId: String, targetDevice: String, targetPath: String): Bool {
        var cachePath = ""
        var fileName = ""
        var handler: ?(String, String, Array<UInt8>) -> Bool = None
        synchronized(mutex) {
            match (jobs.get(jobId)) {
                case Some(job) =>
                    refreshCacheState(job)
                    if (!canAccessCache(job)) {
                        job.message = "relay cache unavailable"
                        job.updatedAt = currentTimestamp()
                        return false
                    }
                    cachePath = job.cachePath
                    fileName = job.fileName
                    match (writeHandler) {
                        case Some(h) => handler = Some(h)
                        case None =>
                            job.message = "restore handler unavailable"
                            job.updatedAt = currentTimestamp()
                            return false
                    }
                case None => return false
            }
        }

        try {
            let payload = fileMgr.readBytes(cachePath)
            let finalPath = composeRelayTargetFilePath(targetPath, fileName)
            var restored = false
            if (let Some(h) <- handler) {
                restored = h(targetDevice, finalPath, payload)
            }
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    refreshCacheState(job)
                    job.updatedAt = currentTimestamp()
                    if (restored) {
                        job.message = "cache restored to ${targetDevice}:${finalPath}"
                    } else {
                        job.message = "restore write failed"
                    }
                }
            }
            restored
        } catch (e: Exception) {
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    refreshCacheState(job)
                    job.updatedAt = currentTimestamp()
                    job.message = "restore error: ${e.message}"
                }
            }
            false
        }
    }

    public func tick(): Unit {
        cleanupExpired()
        let ids = ArrayList<String>()
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (job.recordKind != "file") {
                    continue
                }
                if (job.status == "cached" || job.status == "dispatching") {
                    ids.add(id)
                }
            }
        }
        for (id in ids) {
            tryDispatch(id)
        }
    }

    public func cleanupExpired(): Unit {
        let now = currentTimestamp()
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.status == "delivered" || job.status == "expired") {
                    continue
                }
                if (job.expiresAt > 0 && now > job.expiresAt) {
                    job.status = "expired"
                    job.message = "expired by TTL"
                    job.updatedAt = now
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    job.cacheAvailable = false
                }
            }
            persistTextManifestLocked()
        }
    }

    public func upsertRule(sourceDevice: String, targetDevice: String, enabled: Bool): WhitelistRule {
        let rule = WhitelistRule()
        rule.sourceDevice = if (sourceDevice.size > 0) { sourceDevice } else { "*" }
        rule.targetDevice = targetDevice
        rule.enabled = enabled
        rule.createdAt = currentTimestamp()
        synchronized(mutex) {
            whitelist.add(rule.key(), rule)
            persistWhitelist()
        }
        rule
    }

    public func listRules(targetDevice: String): ArrayList<WhitelistRule> {
        let out = ArrayList<WhitelistRule>()
        synchronized(mutex) {
            for ((_, rule) in whitelist) {
                if (targetDevice.size > 0 && rule.targetDevice != targetDevice) {
                    continue
                }
                out.add(rule)
            }
        }
        out
    }

    public func removeRule(sourceDevice: String, targetDevice: String): Bool {
        let source = if (sourceDevice.size > 0) { sourceDevice } else { "*" }
        let key = "${source}->${targetDevice}"
        synchronized(mutex) {
            if (let Some(_rule) <- whitelist.get(key)) {
                whitelist.remove(key)
                persistWhitelist()
                return true
            }
        }
        false
    }

    public func setRuleEnabled(sourceDevice: String, targetDevice: String, enabled: Bool): ?WhitelistRule {
        let source = if (sourceDevice.size > 0) { sourceDevice } else { "*" }
        let key = "${source}->${targetDevice}"
        synchronized(mutex) {
            if (let Some(rule) <- whitelist.get(key)) {
                rule.enabled = enabled
                persistWhitelist()
                return Some(rule)
            }
        }
        None
    }

    public func cleanupJobs(statusFilter: String, olderThan: Int64): Int64 {
        let ids = ArrayList<String>()
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (!shouldCleanupStatus(statusFilter, job.status)) {
                    continue
                }
                let ts = if (job.updatedAt > 0) { job.updatedAt } else { job.createdAt }
                if (olderThan > 0 && ts > olderThan) {
                    continue
                }
                ids.add(id)
            }

            for (id in ids) {
                if (let Some(job) <- jobs.get(id)) {
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                }
                jobs.remove(id)
            }
            persistTextManifestLocked()
        }
        ids.size
    }

    public func stats(): JsonObject {
        var total: Int64 = 0
        var cached: Int64 = 0
        var pendingApproval: Int64 = 0
        var failed: Int64 = 0
        var delivered: Int64 = 0

        synchronized(mutex) {
            for ((_, job) in jobs) {
                total += 1
                match (job.status) {
                    case "cached" => cached += 1
                    case "dispatching" => cached += 1
                    case "pending_approval" => pendingApproval += 1
                    case "failed" => failed += 1
                    case "expired" => failed += 1
                    case "delivered" => delivered += 1
                    case _ => ()
                }
            }
        }

        JsonObject()
            .putInt("total", total)
            .putInt("cached", cached)
            .putInt("pendingApproval", pendingApproval)
            .putInt("failed", failed)
            .putInt("delivered", delivered)
    }

    func tryDispatch(jobId: String): Unit {
        var targetDevice = ""
        var sourceDevice = ""
        var targetPath = ""
        var cachePath = ""
        var canDispatch = false
        var hasHandler = false
        var handler: ?(String, String, Array<UInt8>) -> Bool = None

        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                if (job.status == "expired" || job.status == "delivered" || job.status == "failed") {
                    return
                }
                if (!isWhitelisted(job.sourceDevice, job.targetDevice)) {
                    job.status = "pending_approval"
                    job.message = "target not in whitelist"
                    job.updatedAt = currentTimestamp()
                    return
                }
                if (!isDeviceOnline(job.targetDevice)) {
                    job.status = "cached"
                    job.message = "target device offline"
                    job.updatedAt = currentTimestamp()
                    return
                }
                job.status = "dispatching"
                job.updatedAt = currentTimestamp()
                job.attempts += 1

                sourceDevice = job.sourceDevice
                targetDevice = job.targetDevice
                targetPath = composeRelayTargetFilePath(job.targetPath, job.fileName)
                cachePath = job.cachePath
                canDispatch = true
                match (writeHandler) {
                    case Some(h) =>
                        handler = Some(h)
                        hasHandler = true
                    case None => ()
                }
            }
        }

        if (!canDispatch) {
            return
        }
        if (!hasHandler) {
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    job.status = "cached"
                    job.message = "dispatch handler unavailable"
                    job.updatedAt = currentTimestamp()
                }
            }
            return
        }

        if (!fileMgr.exists(cachePath)) {
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(jobId)) {
                    job.status = "failed"
                    job.message = "cache file missing"
                    job.updatedAt = currentTimestamp()
                    job.cacheAvailable = false
                }
            }
            return
        }

        var delivered = false
        var message = "delivered"
        try {
            let payload = fileMgr.readBytes(cachePath)
            if (let Some(h) <- handler) {
                delivered = h(targetDevice, targetPath, payload)
            }
            if (!delivered) {
                message = "dispatch write failed"
            }
        } catch (e: Exception) {
            delivered = false
            message = "dispatch error: ${e.message}"
        }

        synchronized(mutex) {
            if (let Some(job) <- jobs.get(jobId)) {
                job.updatedAt = currentTimestamp()
                if (delivered) {
                    job.status = "delivered"
                    job.message = "delivered from ${sourceDevice}"
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    job.cacheAvailable = false
                } else {
                    job.status = "cached"
                    job.message = message
                    refreshCacheState(job)
                }
            }
        }
    }

    func isDeviceOnline(deviceId: String): Bool {
        synchronized(mutex) {
            if (let Some(checker) <- onlineChecker) {
                return checker(deviceId)
            }
        }
        false
    }

    func isWhitelisted(sourceDevice: String, targetDevice: String): Bool {
        synchronized(mutex) {
            let exactKey = "${sourceDevice}->${targetDevice}"
            if (let Some(rule) <- whitelist.get(exactKey)) {
                return rule.enabled
            }
            let wildcardKey = "*->${targetDevice}"
            if (let Some(rule) <- whitelist.get(wildcardKey)) {
                return rule.enabled
            }
        }
        false
    }

    func loadWhitelist(): Unit {
        let values = whitelistStore.load()
        synchronized(mutex) {
            whitelist = HashMap<String, WhitelistRule>()
            var idx: Int64 = 0
            while (true) {
                let key = "rule_${idx}"
                if (let Some(raw) <- values.get(key)) {
                    match (parseWhitelistLine(raw)) {
                        case Some(rule) => whitelist.add(rule.key(), rule)
                        case None => ()
                    }
                    idx += 1
                    continue
                }
                break
            }
        }
    }

    func persistWhitelist(): Unit {
        let values = HashMap<String, String>()
        var idx: Int64 = 0
        for ((_, rule) in whitelist) {
            values.add("rule_${idx}", encodeWhitelistLine(rule))
            idx += 1
        }
        whitelistStore.save(values)
    }

    func enforceCapacity(): Unit {
        let used = currentCacheBytes()
        let limit = calcLimitBytes()
        if (limit <= 0 || used <= limit) {
            return
        }

        var remaining = used
        while (remaining > limit) {
            let oldest = findOldestActiveJobId()
            if (oldest.size == 0) {
                break
            }
            synchronized(mutex) {
                if (let Some(job) <- jobs.get(oldest)) {
                    job.status = "expired"
                    job.message = "evicted by cache limit"
                    job.updatedAt = currentTimestamp()
                    try {
                        remove(job.cachePath)
                    } catch (_: Exception) {}
                    job.cacheAvailable = false
                    remaining -= job.bytes
                    persistTextManifestLocked()
                }
            }
        }
    }

    func loadPersistedTextJobs(): Unit {
        var values = HashMap<String, String>()
        try {
            values = manifestStore.load()
        } catch (e: Exception) {
            println("[Relay][RoomStore] manifest load skipped: ${e.message}")
            return
        }

        synchronized(mutex) {
            var idx: Int64 = 0
            let now = currentTimestamp()
            while (true) {
                let key = "job_${idx}"
                if (let Some(raw) <- values.get(key)) {
                    match (parseRelayTextJobManifestLine(raw)) {
                        case Some(job) =>
                            refreshCacheState(job)
                            if (job.cacheAvailable && (job.expiresAt == 0 || job.expiresAt > now)) {
                                jobs.add(job.id, job)
                            }
                        case None => ()
                    }
                    idx += 1
                    continue
                }
                break
            }
            persistTextManifestLocked()
        }
    }

    func persistTextManifestLocked(): Unit {
        let values = HashMap<String, String>()
        var idx: Int64 = 0
        for ((_, job) in jobs) {
            if (job.recordKind != "text") {
                continue
            }
            refreshCacheState(job)
            if (!job.cacheAvailable) {
                continue
            }
            values.add("job_${idx}", encodeRelayTextJobManifestLine(job))
            idx += 1
        }
        try {
            manifestStore.save(values)
        } catch (e: Exception) {
            println("[Relay][RoomStore] manifest persist skipped: ${e.message}")
        }
    }

    func currentCacheBytes(): Int64 {
        var total: Int64 = 0
        synchronized(mutex) {
            for ((_, job) in jobs) {
                if (job.status == "delivered" || job.status == "expired") {
                    continue
                }
                if (fileMgr.exists(job.cachePath)) {
                    total += job.bytes
                }
            }
        }
        total
    }

    func findOldestActiveJobId(): String {
        var selectedId = ""
        var selectedAt: Int64 = currentTimestamp() + 86400 * 365
        synchronized(mutex) {
            for ((id, job) in jobs) {
                if (job.status == "delivered" || job.status == "expired") {
                    continue
                }
                if (!fileMgr.exists(job.cachePath)) {
                    continue
                }
                if (job.createdAt < selectedAt) {
                    selectedAt = job.createdAt
                    selectedId = id
                }
            }
        }
        selectedId
    }

    func calcLimitBytes(): Int64 {
        if (limitMode == "percent") {
            let snap = diskProbe.snapshot(cacheDir)
            let computed = snap.totalBytes * limitPercent / 100
            if (computed > 0) {
                return computed
            }
        }
        limitBytes
    }

    func registerDefaultChannelAdapters(): Unit {
        let local = ChannelAdapter()
        local.protocolId = "soonlink-local"
        local.displayName = "SoonLink Local Channel"
        local.trustShape = "local-session"
        local.receiveMode = "local-ingress"
        local.roomKind = "manual-room"
        local.capabilities.add("receive-text")
        local.capabilities.add("project-to-relay-room")
        local.contentTypes.add("text/plain")
        let _ = registerChannelAdapter(local)

        let localSend = ChannelAdapter()
        localSend.protocolId = "localsend"
        localSend.displayName = "LocalSend Compatible Channel"
        localSend.trustShape = "manual-peer-or-configured-source"
        localSend.receiveMode = "http-pull-or-adapter-ingress"
        localSend.roomKind = "protocol-room"
        localSend.capabilities.add("receive-text")
        localSend.capabilities.add("receive-file-reference")
        localSend.capabilities.add("peer-info")
        localSend.capabilities.add("localsend-v1-info")
        localSend.capabilities.add("localsend-v2-info")
        localSend.capabilities.add("localsend-v2-prepare-upload")
        localSend.capabilities.add("localsend-v2-upload")
        localSend.capabilities.add("localsend-v2-prepare-download")
        localSend.capabilities.add("localsend-v2-download")
        localSend.capabilities.add("localsend-udp-discovery")
        localSend.capabilities.add("project-to-relay-room")
        localSend.contentTypes.add("text/plain")
        localSend.contentTypes.add("application/octet-stream")
        let _ = registerChannelAdapter(localSend)
    }

    func appendStoredMessageForTextJob(job: RelayJob, sender: String, body: String, createdAt: Int64): Unit {
        appendStoredMessageForTextJob(job, sender, body, createdAt, "")
    }

    func appendStoredMessageForTextJob(job: RelayJob, sender: String, body: String, createdAt: Int64, sourceRecordId: String): Unit {
        if (job.recordKind != "text" || body.size == 0) {
            return
        }
        refreshCacheState(job)
        if (!canAccessCache(job)) {
            return
        }
        let message = buildRelayTextMessage(job, currentStoredMessageIndex(relayTextRoomIdForJob(job)), sender, if (createdAt > 0) { createdAt } else { currentTimestamp() }, body)
        message.messageId = "msg-${currentTimestamp()}-${generateId()}"
        if (sourceRecordId.trimAscii().size > 0) {
            message.sourceRecordId = sourceRecordId.trimAscii()
            message.fileRefs = ArrayList<String>()
            message.fileRefs.add(message.sourceRecordId)
        }
        persistStoredRoomForMessage(job, message)
        appendStoredRoomMessage(message)
    }

    func loadStoredRooms(): ArrayList<RelayRoom> {
        let out = ArrayList<RelayRoom>()
        var values = HashMap<String, String>()
        try {
            values = roomStore.load()
        } catch (_: Exception) {
            return out
        }
        var idx: Int64 = 0
        while (true) {
            let key = "room_${idx}"
            if (let Some(raw) <- values.get(key)) {
                match (parseStoredRelayRoomLine(raw)) {
                    case Some(room) => out.add(room)
                    case None => ()
                }
                idx += 1
                continue
            }
            break
        }
        out
    }

    func persistStoredRoomForMessage(job: RelayJob, message: RelayMessage): Unit {
        let rooms = loadStoredRooms()
        var found = false
        for (room in rooms) {
            if (room.roomId == message.roomId) {
                found = true
                room.title = relayTextRoomTitleForJob(job)
                room.kind = relayTextRoomKindForJob(job)
                if (room.createdAt == 0 || message.createdAt < room.createdAt) {
                    room.createdAt = message.createdAt
                }
                if (message.createdAt > room.updatedAt) {
                    room.updatedAt = message.createdAt
                }
                room.retentionPolicy = "relay-message-store"
                room.transportHints = relayTextRoomTransportHintsForJob(job)
                addRelayRoomParticipant(room, message.senderIdentityId)
            }
        }
        if (!found) {
            let room = RelayRoom()
            room.roomId = message.roomId
            room.title = relayTextRoomTitleForJob(job)
            room.kind = relayTextRoomKindForJob(job)
            room.createdAt = if (message.createdAt > 0) { message.createdAt } else { job.createdAt }
            room.updatedAt = if (message.createdAt > 0) { message.createdAt } else { job.updatedAt }
            room.retentionPolicy = "relay-message-store"
            room.transportHints = relayTextRoomTransportHintsForJob(job)
            addRelayRoomParticipant(room, message.senderIdentityId)
            rooms.add(room)
        }

        let values = HashMap<String, String>()
        var idx: Int64 = 0
        for (room in rooms) {
            values.add("room_${idx}", encodeStoredRelayRoomLine(room))
            idx += 1
        }
        try {
            roomStore.save(values)
        } catch (e: Exception) {
            println("[Relay][RoomStore] room persist skipped: ${e.message}")
        }
    }

    func appendStoredRoomMessage(message: RelayMessage): Unit {
        try {
            fileMgr.ensureDir(messageStoreDir)
            fileMgr.writeText(storedRoomMessagePath(message.roomId), encodeStoredRelayMessageLine(message) + "\n", true)
        } catch (e: Exception) {
            println("[Relay][RoomStore] message append skipped: ${e.message}")
        }
    }

    func loadStoredRoomMessages(roomId: String, limit: Int64): ArrayList<RelayMessage> {
        let out = ArrayList<RelayMessage>()
        let safeLimit = normalizeRelayMessageLimit(limit)
        if (safeLimit <= 0) {
            return out
        }
        try {
            let lines = fileMgr.readLines(storedRoomMessagePath(roomId))
            for (line in lines) {
                if (out.size >= safeLimit) {
                    break
                }
                match (parseStoredRelayMessageLine(line)) {
                    case Some(message) => out.add(message)
                    case None => ()
                }
            }
        } catch (_: Exception) {}
        out
    }

    func currentStoredMessageIndex(roomId: String): Int64 {
        loadStoredRoomMessages(roomId, 500).size
    }

    func storedRoomMessagePath(roomId: String): String {
        joinPaths(messageStoreDir, "${normalizeRelayTextSessionId(roomId)}.log")
    }
}

func refreshCacheState(job: RelayJob): Unit {
    if (job.status == "delivered" || job.status == "expired") {
        job.cacheAvailable = false
        return
    }
    let fileMgr = LocalFileMgr()
    job.cacheAvailable = fileMgr.exists(job.cachePath)
}

func canAccessCache(job: RelayJob): Bool {
    if (job.status == "delivered" || job.status == "expired") {
        return false
    }
    job.cacheAvailable
}

func normalizeRelayPath(path: String): String {
    var out = path.trimAscii()
    if (out.size == 0) { out = "/" }
    if (!strStartsWith(out, "/")) {
        out = "/" + out
    }
    while (strContains(out, "//")) {
        out = strReplace(out, "//", "/")
    }
    out
}

func normalizeRelayTextRecordName(raw: String): String {
    let trimmed = raw.trimAscii()
    var base = if (trimmed.size > 0) { normalizeFileName(trimmed) } else { "tmpTXT-${currentTimestamp() * 1000}.txt" }
    let lower = base.toLower()
    if (!strEndsWith(lower, ".txt")) {
        base += ".txt"
    }
    base
}

func normalizeRelayTextTargetPath(path: String): String {
    let normalized = normalizeRelayPath(path)
    if (normalized == "/") {
        return "/tmpSL"
    }
    normalized
}

func normalizeRelayTextSessionId(raw: String): String {
    var out = raw.trimAscii()
    if (out.size == 0) {
        return ""
    }
    out = strReplace(out, "\\", "-")
    out = strReplace(out, "/", "-")
    while (strContains(out, "..")) {
        out = strReplace(out, "..", "-")
    }
    if (out.size > 80) {
        out = strSubstring(out, 0, 80)
    }
    out
}

func normalizeChannelProtocolId(raw: String): String {
    var out = raw.trimAscii().toLower()
    out = strReplace(out, "\\", "-")
    out = strReplace(out, "/", "-")
    out = strReplace(out, " ", "-")
    while (strContains(out, "..")) {
        out = strReplace(out, "..", "-")
    }
    if (out.size > 64) {
        out = strSubstring(out, 0, 64)
    }
    out
}

func normalizeChannelAdapterMessage(raw: ChannelAdapterMessage): ChannelAdapterMessage {
    let out = ChannelAdapterMessage()
    out.protocolId = normalizeChannelProtocolId(raw.protocolId)
    out.peerId = normalizeRelayTextSessionId(if (raw.peerId.trimAscii().size > 0) { raw.peerId } else { raw.peerDisplayName })
    if (out.peerId.size == 0) {
        out.peerId = "unknown-peer"
    }
    out.peerDisplayName = if (raw.peerDisplayName.trimAscii().size > 0) { raw.peerDisplayName.trimAscii() } else { out.peerId }
    out.endpoint = raw.endpoint.trimAscii()
    out.body = raw.body
    out.contentType = if (raw.contentType.trimAscii().size > 0) { raw.contentType.trimAscii() } else { "text/plain" }
    out.sourceRecordId = raw.sourceRecordId.trimAscii()
    out.createdAt = if (raw.createdAt > 0) { raw.createdAt } else { currentTimestamp() }
    out
}

func channelAdapterRoomId(protocolId: String, peerId: String): String {
    "adapter-${normalizeChannelProtocolId(protocolId)}-${normalizeRelayTextSessionId(peerId)}"
}

func channelAdapterRoomFileName(protocolId: String, peerName: String): String {
    let proto = normalizeChannelProtocolId(protocolId)
    let peer = if (peerName.trimAscii().size > 0) { peerName.trimAscii() } else { "peer" }
    normalizeRelayTextRecordName("${proto}-${peer}")
}

func channelAdapterSourceDevice(protocolId: String, peerName: String): String {
    let proto = normalizeChannelProtocolId(protocolId)
    let peer = if (peerName.trimAscii().size > 0) { peerName.trimAscii() } else { "peer" }
    "${proto}:${peer}"
}

func buildRelayTextSessionAppendText(sourceDevice: String, content: String, append: Bool): String {
    let source = if (sourceDevice.trimAscii().size > 0) { sourceDevice.trimAscii() } else { "web-client" }
    let prefix = if (append) { "\n\n" } else { "" }
    "${prefix}[${currentTimestamp()}] ${source}\n${content}"
}

func localSendPeerMatches(peer: ?LocalSendPeerInfo, endpoint: String, list: String): Bool {
    let raw = list.trimAscii()
    if (raw.size == 0) {
        return false
    }
    var token = ""
    for (ch in raw.toRuneArray()) {
        if (ch == r',' || ch == r';' || ch == r'\n' || ch == r'\r' || ch == r'\t' || ch == r' ') {
            if (localSendPeerMatchesToken(peer, endpoint, token)) {
                return true
            }
            token = ""
        } else {
            token += ch.toString()
        }
    }
    localSendPeerMatchesToken(peer, endpoint, token)
}

func localSendPeerMatchesToken(peer: ?LocalSendPeerInfo, endpoint: String, token: String): Bool {
    let needle = normalizeLocalSendPolicyKey(token)
    if (needle.size == 0) {
        return false
    }
    if (needle == "*") {
        return true
    }
    if (normalizeLocalSendPolicyKey(endpoint) == needle) {
        return true
    }
    match (peer) {
        case Some(info) =>
            normalizeLocalSendPolicyKey(info.peerId) == needle ||
            normalizeLocalSendPolicyKey(info.fingerprint) == needle ||
            normalizeLocalSendPolicyKey(info.alias) == needle ||
            normalizeLocalSendPolicyKey(info.endpoint) == needle
        case None => false
    }
}

func normalizeLocalSendPolicyKey(raw: String): String {
    var out = raw.trimAscii().toLower()
    if (strStartsWith(out, "localsend:")) {
        out = strSubstring(out, 10, out.size)
    }
    out
}

func normalizeFileName(name: String): String {
    var out = name.trimAscii()
    if (out.size == 0) {
        out = "payload.bin"
    }
    out = strReplace(out, "/", "_")
    out = strReplace(out, "\\", "_")
    out
}

func composeRelayTargetFilePath(targetPath: String, fileName: String): String {
    let normalizedPath = normalizeRelayPath(targetPath)
    let normalizedFileName = normalizeFileName(fileName)
    if (normalizedPath == "/") {
        return "/" + normalizedFileName
    }
    if (strEndsWith(normalizedPath, "/" + normalizedFileName)) {
        return normalizedPath
    }
    normalizedPath + "/" + normalizedFileName
}

func normalizeLimitMode(raw: String): String {
    if (raw.toLower() == "percent") {
        return "percent"
    }
    "fixed"
}

func encodeWhitelistLine(rule: WhitelistRule): String {
    let source = strReplace(rule.sourceDevice, "|", "_")
    let target = strReplace(rule.targetDevice, "|", "_")
    let enabled = if (rule.enabled) { "true" } else { "false" }
    "${source}|${target}|${enabled}|${rule.createdAt}"
}

func parseWhitelistLine(raw: String): ?WhitelistRule {
    let parts = splitWhitelist(raw)
    if (parts.size < 3) {
        return None
    }
    let rule = WhitelistRule()
    rule.sourceDevice = if (parts[0].size > 0) { parts[0] } else { "*" }
    rule.targetDevice = parts[1]
    rule.enabled = parts[2] == "true"
    if (parts.size > 3) {
        try {
            rule.createdAt = Int64.parse(parts[3])
        } catch (_: Exception) {
            rule.createdAt = currentTimestamp()
        }
    } else {
        rule.createdAt = currentTimestamp()
    }
    if (rule.targetDevice.size == 0) {
        return None
    }
    Some(rule)
}

func splitWhitelist(raw: String): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    for (ch in raw.toRuneArray()) {
        if (ch == r'|') {
            out.add(current)
            current = ""
            continue
        }
        current += ch.toString()
    }
    out.add(current)
    out
}

func shouldCleanupStatus(statusFilter: String, status: String): Bool {
    if (statusFilter.size > 0 && statusFilter != "all") {
        return status == statusFilter
    }
    status == "delivered" || status == "expired" || status == "failed"
}

func encodeRelayTextJobManifestLine(job: RelayJob): String {
    let parts = ArrayList<String>()
    parts.add(job.id)
    parts.add(job.recordKind)
    parts.add(job.sessionId)
    parts.add(job.sourceDevice)
    parts.add(job.targetDevice)
    parts.add(job.targetPath)
    parts.add(job.fileName)
    parts.add(job.cachePath)
    parts.add("${job.bytes}")
    parts.add(job.status)
    parts.add("${job.attempts}")
    parts.add(job.message)
    parts.add(job.sourceProtocolId)
    parts.add(job.sourcePeerId)
    parts.add(job.sourceEndpoint)
    parts.add("${job.createdAt}")
    parts.add("${job.updatedAt}")
    parts.add("${job.expiresAt}")

    var out = ""
    for (idx in 0..parts.size) {
        if (idx > 0) {
            out += "|"
        }
        out += escapeRelayManifestPart(parts[idx])
    }
    out
}

func parseRelayTextJobManifestLine(raw: String): ?RelayJob {
    let parts = splitRelayManifestLine(raw)
    if (parts.size < 15) {
        return None
    }
    let job = RelayJob()
    job.id = parts[0]
    job.recordKind = parts[1]
    job.sessionId = parts[2]
    job.sourceDevice = parts[3]
    job.targetDevice = parts[4]
    job.targetPath = parts[5]
    job.fileName = parts[6]
    job.cachePath = parts[7]
    job.bytes = parseRelayManifestInt(parts[8], 0)
    job.status = parts[9]
    job.attempts = parseRelayManifestInt(parts[10], 0)
    job.message = parts[11]
    if (parts.size >= 18) {
        job.sourceProtocolId = parts[12]
        job.sourcePeerId = parts[13]
        job.sourceEndpoint = parts[14]
        job.createdAt = parseRelayManifestInt(parts[15], currentTimestamp())
        job.updatedAt = parseRelayManifestInt(parts[16], job.createdAt)
        job.expiresAt = parseRelayManifestInt(parts[17], 0)
    } else {
        job.createdAt = parseRelayManifestInt(parts[12], currentTimestamp())
        job.updatedAt = parseRelayManifestInt(parts[13], job.createdAt)
        job.expiresAt = parseRelayManifestInt(parts[14], 0)
    }
    if (job.id.size == 0 || job.recordKind != "text" || job.cachePath.size == 0 || job.fileName.size == 0) {
        return None
    }
    Some(job)
}

func splitRelayManifestLine(raw: String): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    for (ch in raw.toRuneArray()) {
        if (ch == r'|') {
            out.add(unescapeRelayManifestPart(current))
            current = ""
            continue
        }
        current += ch.toString()
    }
    out.add(unescapeRelayManifestPart(current))
    out
}

func escapeRelayManifestPart(raw: String): String {
    var out = raw
    out = strReplace(out, "%", "%25")
    out = strReplace(out, "|", "%7C")
    out = strReplace(out, "\n", "%0A")
    out = strReplace(out, "\r", "%0D")
    out
}

func unescapeRelayManifestPart(raw: String): String {
    var out = raw
    out = strReplace(out, "%0D", "\r")
    out = strReplace(out, "%0A", "\n")
    out = strReplace(out, "%7C", "|")
    out = strReplace(out, "%25", "%")
    out
}

func parseRelayManifestInt(raw: String, fallback: Int64): Int64 {
    try {
        return Int64.parse(raw)
    } catch (_: Exception) {
        fallback
    }
}

func encodeStoredRelayRoomLine(room: RelayRoom): String {
    let parts = ArrayList<String>()
    parts.add(room.roomId)
    parts.add(room.title)
    parts.add(room.kind)
    parts.add(joinRelayStoreList(room.participantIdentityIds))
    parts.add("${room.createdAt}")
    parts.add("${room.updatedAt}")
    parts.add(room.retentionPolicy)
    parts.add(room.transportHints)
    joinRelayStoreParts(parts)
}

func parseStoredRelayRoomLine(raw: String): ?RelayRoom {
    let parts = splitRelayManifestLine(raw)
    if (parts.size < 8) {
        return None
    }
    let room = RelayRoom()
    room.roomId = parts[0]
    room.title = parts[1]
    room.kind = parts[2]
    let participantIds = splitRelayStoreList(parts[3])
    for (id in participantIds) {
        addRelayRoomParticipant(room, id)
    }
    room.createdAt = parseRelayManifestInt(parts[4], currentTimestamp())
    room.updatedAt = parseRelayManifestInt(parts[5], room.createdAt)
    room.retentionPolicy = parts[6]
    room.transportHints = parts[7]
    if (room.roomId.size == 0) {
        return None
    }
    Some(room)
}

func encodeStoredRelayMessageLine(message: RelayMessage): String {
    let parts = ArrayList<String>()
    parts.add(message.messageId)
    parts.add(message.roomId)
    parts.add(message.senderIdentityId)
    parts.add(message.senderKind)
    parts.add(message.body)
    parts.add(message.contentType)
    parts.add("${message.createdAt}")
    parts.add(message.deliveryState)
    parts.add(message.sourceProtocolId)
    parts.add(message.sourceRecordId)
    parts.add(joinRelayStoreList(message.fileRefs))
    joinRelayStoreParts(parts)
}

func parseStoredRelayMessageLine(raw: String): ?RelayMessage {
    let parts = splitRelayManifestLine(raw)
    if (parts.size < 11) {
        return None
    }
    let message = RelayMessage()
    message.messageId = parts[0]
    message.roomId = parts[1]
    message.senderIdentityId = parts[2]
    message.senderKind = parts[3]
    message.body = parts[4]
    message.contentType = if (parts[5].size > 0) { parts[5] } else { "text/plain" }
    message.createdAt = parseRelayManifestInt(parts[6], currentTimestamp())
    message.deliveryState = parts[7]
    message.sourceProtocolId = parts[8]
    message.sourceRecordId = parts[9]
    let refs = splitRelayStoreList(parts[10])
    for (ref in refs) {
        if (ref.size > 0) {
            message.fileRefs.add(ref)
        }
    }
    if (message.messageId.size == 0 || message.roomId.size == 0) {
        return None
    }
    Some(message)
}

func joinRelayStoreParts(parts: ArrayList<String>): String {
    var out = ""
    for (idx in 0..parts.size) {
        if (idx > 0) {
            out += "|"
        }
        out += escapeRelayManifestPart(parts[idx])
    }
    out
}

func joinRelayStoreList(values: ArrayList<String>): String {
    var out = ""
    for (idx in 0..values.size) {
        if (idx > 0) {
            out += ","
        }
        out += strReplace(values[idx], ",", "_")
    }
    out
}

func splitRelayStoreList(raw: String): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    for (ch in raw.toRuneArray()) {
        if (ch == r',') {
            if (current.size > 0) {
                out.add(current)
            }
            current = ""
            continue
        }
        current += ch.toString()
    }
    if (current.size > 0) {
        out.add(current)
    }
    out
}

func relayTextRoomIdForJob(job: RelayJob): String {
    if (job.sessionId.trimAscii().size > 0) {
        return job.sessionId.trimAscii()
    }
    "default-text-room"
}

func relayTextRoomTitleForJob(job: RelayJob): String {
    if (job.sourceProtocolId.trimAscii().size > 0) {
        let peer = if (job.sourcePeerId.trimAscii().size > 0) { job.sourcePeerId.trimAscii() } else { job.sourceDevice.trimAscii() }
        if (peer.size > 0) {
            return "${job.sourceProtocolId}:${peer}"
        }
        return "${job.sourceProtocolId} channel"
    }
    if (job.sessionId.trimAscii().size > 0) {
        return if (job.fileName.size > 0) { job.fileName } else { job.sessionId }
    }
    "文字中转站"
}

func relayTextRoomKindForJob(job: RelayJob): String {
    if (job.sourceProtocolId.trimAscii().size > 0) {
        return "protocol-room"
    }
    if (job.sessionId.size > 0) {
        return "default-text-station"
    }
    "manual-room"
}

func relayTextRoomTransportHintsForJob(job: RelayJob): String {
    if (job.sourceProtocolId.trimAscii().size > 0) {
        return "adapter:${job.sourceProtocolId}|relay-job-text"
    }
    "relay-job-text"
}

func relayIdentityIdForSource(sourceDevice: String): String {
    let normalized = if (sourceDevice.trimAscii().size > 0) { sourceDevice.trimAscii() } else { "unknown" }
    "relay-source-${normalizeRelayTextSessionId(normalized)}"
}

func relayIdentityIdForJobSource(job: RelayJob, sender: String): String {
    if (job.sourceProtocolId.trimAscii().size > 0) {
        let peer = if (job.sourcePeerId.trimAscii().size > 0) { job.sourcePeerId.trimAscii() } else { sender }
        return "protocol-${normalizeChannelProtocolId(job.sourceProtocolId)}-${normalizeRelayTextSessionId(peer)}"
    }
    relayIdentityIdForSource(sender)
}

func addRelayRoomParticipant(room: RelayRoom, identityId: String): Unit {
    if (identityId.size == 0) {
        return
    }
    for (id in room.participantIdentityIds) {
        if (id == identityId) {
            return
        }
    }
    room.participantIdentityIds.add(identityId)
}

func addRelayRoomParticipantsFromJobText(room: RelayRoom, job: RelayJob, fileMgr: FileMgr): Unit {
    if (job.sessionId.size == 0 || !job.cacheAvailable) {
        return
    }
    try {
        let messages = parseRelayTextMessagesFromJob(job, fileMgr.readText(job.cachePath), 500)
        for (message in messages) {
            addRelayRoomParticipant(room, message.senderIdentityId)
        }
    } catch (_: Exception) {}
}

func normalizeRelayMessageLimit(limit: Int64): Int64 {
    if (limit <= 0) {
        return 200
    }
    if (limit > 500) {
        return 500
    }
    limit
}

func parseRelayTextMessagesFromJob(job: RelayJob, content: String, limit: Int64): ArrayList<RelayMessage> {
    let out = ArrayList<RelayMessage>()
    let safeLimit = normalizeRelayMessageLimit(limit)
    if (content.size == 0 || safeLimit <= 0) {
        return out
    }
    if (job.sessionId.size == 0) {
        out.add(buildRelayTextMessage(job, 0, job.sourceDevice, job.createdAt, content))
        return out
    }

    let lines = splitRelayTextLines(content)
    var currentSender = job.sourceDevice
    var currentCreatedAt = job.createdAt
    var currentBody = ""
    var hasCurrent = false
    var index: Int64 = 0
    var sawHeader = false
    for (line in lines) {
        if (isRelayTextMessageHeader(line)) {
            if (hasCurrent && out.size < safeLimit) {
                out.add(buildRelayTextMessage(job, index, currentSender, currentCreatedAt, currentBody))
                index += 1
            }
            currentSender = relayTextHeaderSender(line)
            currentCreatedAt = relayTextHeaderTimestamp(line, job.createdAt)
            currentBody = ""
            hasCurrent = true
            sawHeader = true
            continue
        }
        if (hasCurrent) {
            if (currentBody.size > 0) {
                currentBody += "\n"
            }
            currentBody += line
        }
    }

    if (hasCurrent && out.size < safeLimit) {
        out.add(buildRelayTextMessage(job, index, currentSender, currentCreatedAt, currentBody))
    }
    if (!sawHeader && out.size == 0) {
        out.add(buildRelayTextMessage(job, 0, job.sourceDevice, job.createdAt, content))
    }
    out
}

func buildRelayTextMessage(job: RelayJob, index: Int64, sender: String, createdAt: Int64, body: String): RelayMessage {
    let message = RelayMessage()
    message.messageId = "${job.id}:${index}"
    message.roomId = relayTextRoomIdForJob(job)
    message.senderIdentityId = relayIdentityIdForJobSource(job, sender)
    message.senderKind = if (job.sourceProtocolId.trimAscii().size > 0) {
        "protocol-peer"
    } else if (sender.trimAscii().size > 0) {
        "relay-source"
    } else {
        "manual"
    }
    message.body = body
    message.contentType = "text/plain"
    message.createdAt = if (createdAt > 0) { createdAt } else { job.createdAt }
    message.deliveryState = job.status
    message.sourceProtocolId = if (job.sourceProtocolId.trimAscii().size > 0) { job.sourceProtocolId } else { "soonlink-relay" }
    message.sourceRecordId = job.id
    message.fileRefs.add(job.id)
    message
}

func splitRelayTextLines(content: String): ArrayList<String> {
    let out = ArrayList<String>()
    var current = ""
    for (ch in content.toRuneArray()) {
        if (ch == r'\n') {
            out.add(current)
            current = ""
            continue
        }
        if (ch == r'\r') {
            continue
        }
        current += ch.toString()
    }
    out.add(current)
    out
}

func isRelayTextMessageHeader(line: String): Bool {
    let close = relayTextHeaderCloseIndex(line)
    if (close <= 1) {
        return false
    }
    let runes = line.toRuneArray()
    if (runes.size <= close + 1 || runes[close + 1] != r' ') {
        return false
    }
    let timestamp = strSubstring(line, 1, close)
    try {
        let _ = Int64.parse(timestamp)
    } catch (_: Exception) {
        return false
    }
    strSubstring(line, close + 2, runes.size).trimAscii().size > 0
}

func relayTextHeaderTimestamp(line: String, fallback: Int64): Int64 {
    let close = relayTextHeaderCloseIndex(line)
    if (close <= 1) {
        return fallback
    }
    try {
        return Int64.parse(strSubstring(line, 1, close))
    } catch (_: Exception) {
        fallback
    }
}

func relayTextHeaderSender(line: String): String {
    let close = relayTextHeaderCloseIndex(line)
    let runes = line.toRuneArray()
    if (close <= 0 || runes.size <= close + 2) {
        return "unknown"
    }
    let sender = strSubstring(line, close + 2, runes.size).trimAscii()
    if (sender.size > 0) { sender } else { "unknown" }
}

func relayTextHeaderCloseIndex(line: String): Int64 {
    let runes = line.toRuneArray()
    if (runes.size < 4 || runes[0] != r'[') {
        return -1
    }
    var idx: Int64 = 1
    while (idx < runes.size) {
        if (runes[idx] == r']') {
            return idx
        }
        idx += 1
    }
    -1
}

func normalizeLocalSendOutboundEndpoint(endpoint: String): String {
    var out = endpoint.trimAscii()
    while (strEndsWith(out, "/")) {
        out = strSubstring(out, 0, out.size - 1)
    }
    if (!strStartsWith(out, "http://")) {
        return ""
    }
    out
}

func normalizeLocalSendOutboundFileId(jobId: String): String {
    var out = jobId.trimAscii()
    out = strReplace(out, "/", "-")
    out = strReplace(out, "\\", "-")
    out = strReplace(out, "?", "-")
    out = strReplace(out, "&", "-")
    out = strReplace(out, "=", "-")
    if (out.size == 0) {
        out = "soonlink-file"
    }
    out
}

func buildLocalSendOutboundPrepareBody(
    fileId: String,
    fileName: String,
    size: Int64,
    alias: String,
    fingerprint: String,
    deviceModel: String,
    deviceType: String
): String {
    let info = JsonObject()
        .put("alias", if (alias.trimAscii().size > 0) { alias.trimAscii() } else { "SoonLink Relay" })
        .put("version", "2.1")
        .put("deviceModel", if (deviceModel.trimAscii().size > 0) { deviceModel.trimAscii() } else { "SoonLink" })
        .put("deviceType", if (deviceType.trimAscii().size > 0) { deviceType.trimAscii() } else { "desktop" })
        .put("fingerprint", if (fingerprint.trimAscii().size > 0) { fingerprint.trimAscii() } else { "soonlink-relay" })
        .put("protocol", "http")
        .putInt("port", 0)
        .putBool("download", true)
    let file = JsonObject()
        .put("id", fileId)
        .put("fileName", fileName)
        .putInt("size", size)
        .put("fileType", "application/octet-stream")
    let files = JsonObject()
        .putObj(fileId, file)
    JsonObject()
        .putObj("info", info)
        .putObj("files", files)
        .toString()
}

func readLocalSendHttpBody(resp: HttpResponse): String {
    String.fromUtf8(readLocalSendHttpBytes(resp))
}

func readLocalSendHttpBytes(resp: HttpResponse): Array<UInt8> {
    let buf = ArrayList<UInt8>()
    let tmp = Array<UInt8>(4096, repeat: 0)
    while (true) {
        let n = resp.body.read(tmp)
        if (n <= 0) {
            break
        }
        for (i in 0..n) {
            buf.add(tmp[i])
        }
    }
    buf.toArray()
}

func urlEncodeLocalSendQuery(input: String): String {
    let out = ArrayList<UInt8>()
    for (b in input.toArray()) {
        if (isLocalSendSafeQueryByte(UInt8(b))) {
            out.add(UInt8(b))
            continue
        }
        if (b == 32) {
            out.add(UInt8(43))
            continue
        }
        let byteValue = Int64(b)
        let high = UInt8(byteValue / 16)
        let low = UInt8(byteValue % 16)
        let encoded = "%${hexLocalSendDigit(high)}${hexLocalSendDigit(low)}".toArray()
        for (c in encoded) {
            out.add(UInt8(c))
        }
    }
    String.fromUtf8(out.toArray())
}

func isLocalSendSafeQueryByte(b: UInt8): Bool {
    (b >= UInt8(48) && b <= UInt8(57)) ||
    (b >= UInt8(65) && b <= UInt8(90)) ||
    (b >= UInt8(97) && b <= UInt8(122)) ||
    b == UInt8(45) || b == UInt8(46) || b == UInt8(95) || b == UInt8(126)
}

func hexLocalSendDigit(v: UInt8): String {
    if (v < UInt8(10)) {
        String.fromUtf8([UInt8(48) + v])
    } else {
        String.fromUtf8([UInt8(65) + (v - UInt8(10))])
    }
}
