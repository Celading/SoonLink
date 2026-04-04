package soonlnk.features

import soonlnk.commons.*
public class PeerDownloadPayload {
    public var result: PeerTransferResult = PeerTransferResult()
    public var data: Array<UInt8> = Array<UInt8>(0, repeat: 0)

    public init() {}
}

public class PeerTransferFeature {
    let fileMgr: FileMgr
    let securityChannel: SecurityChannel
    let peerChannel: PeerChannel

    public init() {
        this.fileMgr = LocalFileMgr()
        this.securityChannel = SecurityChannel()
        this.peerChannel = LocalPeerChannel(this.fileMgr, this.securityChannel)
    }

    public init(fileMgr: FileMgr, securityChannel: SecurityChannel) {
        this.fileMgr = fileMgr
        this.securityChannel = securityChannel
        this.peerChannel = LocalPeerChannel(fileMgr, securityChannel)
    }

    public init(fileMgr: FileMgr, securityChannel: SecurityChannel, peerChannel: PeerChannel) {
        this.fileMgr = fileMgr
        this.securityChannel = securityChannel
        this.peerChannel = peerChannel
    }

    public func setSecurityMode(raw: String): String {
        let mode = securityChannel.setMode(raw)
        securityModeToString(mode)
    }

    public func getSecurityMode(): String {
        securityChannel.getModeString()
    }

    public func beginHandshake(peerId: String): String {
        securityChannel.beginHandshake(peerId)
    }

    public func acceptUpload(targetPath: String, peerId: String, token: String, payload: Array<UInt8>): PeerTransferResult {
        let request = PeerTransferRequest()
        request.targetPath = targetPath
        request.peerId = peerId
        request.handshakeToken = token
        peerChannel.acceptUpload(request, payload)
    }

    public func provideDownload(sourcePath: String, peerId: String, token: String): PeerDownloadPayload {
        let request = PeerTransferRequest()
        request.sourcePath = sourcePath
        request.peerId = peerId
        request.handshakeToken = token

        let output = PeerDownloadPayload()
        let inner = peerChannel.provideDownload(request)
        output.result = inner.transfer
        output.data = inner.data
        output
    }

    public func pullLocalToPath(sourcePath: String, targetPath: String): PeerTransferResult {
        let result = PeerTransferResult()

        if (!fileMgr.exists(sourcePath)) {
            result.success = false
            result.message = "source file not found"
            return result
        }

        try {
            let data = fileMgr.readBytes(sourcePath)
            fileMgr.writeBytes(targetPath, data, false)
            result.success = true
            result.message = "local pull completed"
            result.bytesTransferred = data.size
            result
        } catch (e: Exception) {
            result.success = false
            result.message = "local pull failed: ${e.message}"
            result
        }
    }
}
