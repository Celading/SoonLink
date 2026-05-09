package soonlnk.commons

import std.collection.{ArrayList, HashMap}
import std.unicode.*

public func resolveTransferFileCategory(path: String, rawMime: String, isDir: Bool): String {
    if (isDir) {
        return "directory"
    }

    let mimeType = resolvePreviewMimeType(rawMime, path, false).trimAscii().toLower()
    let ext = lowerTransferPathExtension(path)
    let normalizedPath = path.trimAscii().toLower()

    if (isImageTransferType(mimeType, ext)) {
        return "image"
    }
    if (isVideoTransferType(mimeType, ext)) {
        return "video"
    }
    if (isAudioTransferType(mimeType, ext)) {
        return "audio"
    }
    if (isArchiveTransferType(mimeType, ext, normalizedPath)) {
        return "archive"
    }
    if (isCodeTransferType(mimeType, ext)) {
        return "code"
    }
    if (isDocumentTransferType(mimeType, ext)) {
        return "document"
    }
    if (isTextTransferType(mimeType, ext)) {
        return "text"
    }
    "unknown"
}

public func sanitizeTransferProtocolPreferences(values: ArrayList<String>): ArrayList<String> {
    let out = ArrayList<String>()
    let seen = HashMap<String, Bool>()
    for (value in values) {
        let normalized = normalizeTransferProtocolName(value)
        if (normalized.size == 0) {
            continue
        }
        if (seen.contains(normalized)) {
            continue
        }
        seen.add(normalized, true)
        out.add(normalized)
    }
    out
}

public func buildTransferProtocolCandidates(
    fileCategory: String,
    totalBytes: Int64,
    protocolPreferences: ArrayList<String>,
    isDir: Bool,
    threads: Int64
): ArrayList<String> {
    let out = ArrayList<String>()
    let seen = HashMap<String, Bool>()

    for (value in sanitizeTransferProtocolPreferences(protocolPreferences)) {
        addTransferProtocolCandidate(out, seen, value)
    }

    let category = normalizeTransferFileCategory(fileCategory, isDir)
    let preferMultiThread = shouldPreferMultiThreadTransfer(category, totalBytes, threads, isDir)

    if (category == "directory") {
        addTransferProtocolCandidate(out, seen, "rsync")
        addTransferProtocolCandidate(out, seen, "multi-thread-http")
        addTransferProtocolCandidate(out, seen, "http")
        addTransferProtocolCandidate(out, seen, "p2p")
        addTransferProtocolCandidate(out, seen, "quic")
    } else if (category == "archive") {
        if (preferMultiThread) {
            addTransferProtocolCandidate(out, seen, "multi-thread-http")
        }
        addTransferProtocolCandidate(out, seen, "rsync")
        addTransferProtocolCandidate(out, seen, "http")
        addTransferProtocolCandidate(out, seen, "quic")
        addTransferProtocolCandidate(out, seen, "p2p")
    } else if (category == "video" || category == "audio" || category == "image") {
        if (preferMultiThread) {
            addTransferProtocolCandidate(out, seen, "multi-thread-http")
        }
        addTransferProtocolCandidate(out, seen, "http")
        addTransferProtocolCandidate(out, seen, "quic")
        addTransferProtocolCandidate(out, seen, "p2p")
        addTransferProtocolCandidate(out, seen, "rsync")
    } else if (category == "document" || category == "code" || category == "text") {
        if (preferMultiThread) {
            addTransferProtocolCandidate(out, seen, "multi-thread-http")
        }
        addTransferProtocolCandidate(out, seen, "http")
        if (!preferMultiThread) {
            addTransferProtocolCandidate(out, seen, "multi-thread-http")
        }
        addTransferProtocolCandidate(out, seen, "quic")
        addTransferProtocolCandidate(out, seen, "rsync")
    } else {
        if (preferMultiThread) {
            addTransferProtocolCandidate(out, seen, "multi-thread-http")
        }
        addTransferProtocolCandidate(out, seen, "http")
        addTransferProtocolCandidate(out, seen, "quic")
        addTransferProtocolCandidate(out, seen, "p2p")
        addTransferProtocolCandidate(out, seen, "rsync")
    }

    if (out.size == 0) {
        out.add("http")
    }
    out
}

func normalizeTransferProtocolName(raw: String): String {
    let normalized = raw.trimAscii().toLower()
    if (normalized == "http") { return "http" }
    if (normalized == "multi-thread-http") { return "multi-thread-http" }
    if (normalized == "multi_thread_http") { return "multi-thread-http" }
    if (normalized == "multithread-http") { return "multi-thread-http" }
    if (normalized == "quic") { return "quic" }
    if (normalized == "rsync") { return "rsync" }
    if (normalized == "p2p") { return "p2p" }
    ""
}

func addTransferProtocolCandidate(out: ArrayList<String>, seen: HashMap<String, Bool>, protocolName: String): Unit {
    let normalized = normalizeTransferProtocolName(protocolName)
    if (normalized.size == 0 || seen.contains(normalized)) {
        return
    }
    seen.add(normalized, true)
    out.add(normalized)
}

func normalizeTransferFileCategory(raw: String, isDir: Bool): String {
    if (isDir) {
        return "directory"
    }

    let normalized = raw.trimAscii().toLower()
    if (normalized == "image") { return "image" }
    if (normalized == "video") { return "video" }
    if (normalized == "audio") { return "audio" }
    if (normalized == "document") { return "document" }
    if (normalized == "archive") { return "archive" }
    if (normalized == "code") { return "code" }
    if (normalized == "text") { return "text" }
    "unknown"
}

func shouldPreferMultiThreadTransfer(category: String, totalBytes: Int64, threads: Int64, isDir: Bool): Bool {
    if (threads > 1) {
        return true
    }
    if (isDir || category == "directory") {
        return true
    }
    totalBytes >= 128 * 1024 * 1024
}

func lowerTransferPathExtension(path: String): String {
    let trimmed = path.trimAscii()
    if (trimmed.size == 0) {
        return ""
    }

    let runes = trimmed.toRuneArray()
    var lastSlash: Int64 = -1
    var lastDot: Int64 = -1
    for (i in 0..runes.size) {
        if (runes[i] == r'/' || runes[i] == r'\\') {
            lastSlash = i
            lastDot = -1
            continue
        }
        if (runes[i] == r'.') {
            lastDot = i
        }
    }

    if (lastDot <= lastSlash || lastDot >= trimmed.size - 1) {
        return ""
    }
    strSubstring(trimmed, lastDot + 1, trimmed.size).toLower()
}

func isImageTransferType(mimeType: String, ext: String): Bool {
    strStartsWithTransfer(mimeType, "image/") ||
        ext == "jpg" ||
        ext == "jpeg" ||
        ext == "png" ||
        ext == "gif" ||
        ext == "webp" ||
        ext == "svg" ||
        ext == "bmp" ||
        ext == "ico" ||
        ext == "avif" ||
        ext == "heic" ||
        ext == "heif"
}

func isVideoTransferType(mimeType: String, ext: String): Bool {
    strStartsWithTransfer(mimeType, "video/") ||
        ext == "mp4" ||
        ext == "webm" ||
        ext == "mov" ||
        ext == "m4v" ||
        ext == "mkv" ||
        ext == "avi" ||
        ext == "flv"
}

func isAudioTransferType(mimeType: String, ext: String): Bool {
    strStartsWithTransfer(mimeType, "audio/") ||
        ext == "mp3" ||
        ext == "wav" ||
        ext == "ogg" ||
        ext == "m4a" ||
        ext == "flac" ||
        ext == "aac" ||
        ext == "opus"
}

func isArchiveTransferType(mimeType: String, ext: String, normalizedPath: String): Bool {
    mimeType == "application/zip" ||
        mimeType == "application/x-7z-compressed" ||
        mimeType == "application/vnd.rar" ||
        mimeType == "application/x-tar" ||
        mimeType == "application/gzip" ||
        mimeType == "application/x-bzip2" ||
        mimeType == "application/x-xz" ||
        ext == "zip" ||
        ext == "7z" ||
        ext == "rar" ||
        ext == "tar" ||
        ext == "gz" ||
        ext == "tgz" ||
        ext == "bz2" ||
        ext == "tbz2" ||
        ext == "xz" ||
        ext == "txz" ||
        strEndsWithTransfer(normalizedPath, ".tar.gz") ||
        strEndsWithTransfer(normalizedPath, ".tar.bz2") ||
        strEndsWithTransfer(normalizedPath, ".tar.xz")
}

func isCodeTransferType(mimeType: String, ext: String): Bool {
    ext == "cj" ||
        ext == "js" ||
        ext == "mjs" ||
        ext == "cjs" ||
        ext == "ts" ||
        ext == "tsx" ||
        ext == "jsx" ||
        ext == "rs" ||
        ext == "go" ||
        ext == "java" ||
        ext == "py" ||
        ext == "sh" ||
        ext == "sql" ||
        ext == "html" ||
        ext == "htm" ||
        ext == "css" ||
        mimeType == "application/javascript" ||
        mimeType == "application/typescript" ||
        strStartsWithTransfer(mimeType, "text/html") ||
        strStartsWithTransfer(mimeType, "text/css")
}

func isDocumentTransferType(mimeType: String, ext: String): Bool {
    mimeType == "application/pdf" ||
        mimeType == "application/json" ||
        mimeType == "application/xml" ||
        mimeType == "application/yaml" ||
        mimeType == "application/rtf" ||
        mimeType == "application/msword" ||
        mimeType == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
        mimeType == "application/vnd.ms-excel" ||
        mimeType == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ||
        mimeType == "application/vnd.ms-powerpoint" ||
        mimeType == "application/vnd.openxmlformats-officedocument.presentationml.presentation" ||
        strStartsWithTransfer(mimeType, "text/markdown") ||
        strStartsWithTransfer(mimeType, "text/csv") ||
        strStartsWithTransfer(mimeType, "text/tab-separated-values") ||
        ext == "pdf" ||
        ext == "md" ||
        ext == "yaml" ||
        ext == "yml" ||
        ext == "json" ||
        ext == "xml" ||
        ext == "csv" ||
        ext == "tsv" ||
        ext == "toml" ||
        ext == "ini" ||
        ext == "cfg" ||
        ext == "conf" ||
        ext == "properties" ||
        ext == "rtf" ||
        ext == "doc" ||
        ext == "docx" ||
        ext == "xls" ||
        ext == "xlsx" ||
        ext == "ppt" ||
        ext == "pptx"
}

func isTextTransferType(mimeType: String, ext: String): Bool {
    strStartsWithTransfer(mimeType, "text/plain") ||
        ext == "txt" ||
        ext == "log" ||
        ext == "lock"
}

func strStartsWithTransfer(text: String, prefix: String): Bool {
    if (text.size < prefix.size) {
        return false
    }
    let textRunes = text.toRuneArray()
    let prefixRunes = prefix.toRuneArray()
    for (i in 0..prefixRunes.size) {
        if (textRunes[i] != prefixRunes[i]) {
            return false
        }
    }
    true
}

func strEndsWithTransfer(text: String, suffix: String): Bool {
    if (suffix.size == 0) {
        return true
    }
    if (text.size < suffix.size) {
        return false
    }

    let textRunes = text.toRuneArray()
    let suffixRunes = suffix.toRuneArray()
    let offset = textRunes.size - suffixRunes.size
    for (i in 0..suffixRunes.size) {
        if (textRunes[offset + i] != suffixRunes[i]) {
            return false
        }
    }
    true
}
