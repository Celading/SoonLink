package soonlnk.commons

public class PeerTransferRequest {
    public var sourcePath: String = ""
    public var targetPath: String = ""
    public var peerId: String = ""
    public var handshakeToken: String = ""

    public init() {}
}

public class PeerTransferResult {
    public var success: Bool = false
    public var message: String = ""
    public var bytesTransferred: Int64 = 0

    public init() {}

    public func toJson(): JsonObject {
        JsonObject()
            .putBool("success", success)
            .put("message", message)
            .putInt("bytesTransferred", bytesTransferred)
    }
}

public class PeerPullResult {
    public var transfer: PeerTransferResult = PeerTransferResult()
    public var data: Array<UInt8> = Array<UInt8>(0, repeat: 0)

    public init() {}
}

public interface PeerChannel {
    func acceptUpload(request: PeerTransferRequest, payload: Array<UInt8>): PeerTransferResult
    func provideDownload(request: PeerTransferRequest): PeerPullResult
}

public class LocalPeerChannel <: PeerChannel {
    let fileMgr: FileMgr
    let security: SecurityChannel

    public init() {
        this.fileMgr = LocalFileMgr()
        this.security = SecurityChannel()
    }

    public init(fileMgr: FileMgr, security: SecurityChannel) {
        this.fileMgr = fileMgr
        this.security = security
    }

    public func acceptUpload(request: PeerTransferRequest, payload: Array<UInt8>): PeerTransferResult {
        let result = PeerTransferResult()
        if (request.targetPath.size == 0) {
            result.success = false
            result.message = "targetPath is required"
            return result
        }

        if (!security.verifyHandshake(request.handshakeToken)) {
            result.success = false
            result.message = "handshake validation failed"
            return result
        }

        let decoded = security.unprotectPayload(payload)
        try {
            fileMgr.writeBytes(request.targetPath, decoded, false)
            result.success = true
            result.message = "peer upload accepted"
            result.bytesTransferred = decoded.size
            result
        } catch (e: Exception) {
            result.success = false
            result.message = "write failed: ${e.message}"
            result
        }
    }

    public func provideDownload(request: PeerTransferRequest): PeerPullResult {
        let output = PeerPullResult()
        if (request.sourcePath.size == 0) {
            output.transfer.success = false
            output.transfer.message = "sourcePath is required"
            return output
        }

        if (!security.verifyHandshake(request.handshakeToken)) {
            output.transfer.success = false
            output.transfer.message = "handshake validation failed"
            return output
        }

        if (!fileMgr.exists(request.sourcePath)) {
            output.transfer.success = false
            output.transfer.message = "source file not found"
            return output
        }

        try {
            let raw = fileMgr.readBytes(request.sourcePath)
            output.data = security.protectPayload(raw)
            output.transfer.success = true
            output.transfer.message = "peer download ready"
            output.transfer.bytesTransferred = output.data.size
            output
        } catch (e: Exception) {
            output.transfer.success = false
            output.transfer.message = "read failed: ${e.message}"
            output
        }
    }
}
