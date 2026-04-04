package soonlnk.commons

import std.unicode.*

public func resolvePreviewMimeType(rawMime: String, path: String, isDir: Bool): String {
    if (isDir) {
        return "inode/directory"
    }

    let normalizedMime = rawMime.trimAscii().toLower()
    if (normalizedMime.size > 0 && normalizedMime != "application/octet-stream") {
        return normalizedMime
    }

    let ext = lowerPathExtension(path)
    if (ext == "jpg" || ext == "jpeg") { return "image/jpeg" }
    if (ext == "png") { return "image/png" }
    if (ext == "gif") { return "image/gif" }
    if (ext == "webp") { return "image/webp" }
    if (ext == "svg") { return "image/svg+xml" }
    if (ext == "bmp") { return "image/bmp" }
    if (ext == "ico") { return "image/x-icon" }
    if (ext == "mp4") { return "video/mp4" }
    if (ext == "webm") { return "video/webm" }
    if (ext == "mov") { return "video/quicktime" }
    if (ext == "m4v") { return "video/x-m4v" }
    if (ext == "mkv") { return "video/x-matroska" }
    if (ext == "mp3") { return "audio/mpeg" }
    if (ext == "wav") { return "audio/wav" }
    if (ext == "ogg") { return "audio/ogg" }
    if (ext == "m4a") { return "audio/mp4" }
    if (ext == "flac") { return "audio/flac" }
    if (ext == "pdf") { return "application/pdf" }
    if (ext == "json") { return "application/json" }
    if (ext == "xml") { return "application/xml" }
    if (ext == "html" || ext == "htm") { return "text/html; charset=utf-8" }
    if (ext == "css") { return "text/css; charset=utf-8" }
    if (ext == "js" || ext == "mjs" || ext == "cjs") { return "application/javascript" }
    if (ext == "ts" || ext == "tsx") { return "application/typescript" }
    if (ext == "jsx") { return "text/jsx; charset=utf-8" }
    if (ext == "md") { return "text/markdown; charset=utf-8" }
    if (ext == "yaml" || ext == "yml") { return "application/yaml" }
    if (isLikelyTextExtension(ext)) {
        return "text/plain; charset=utf-8"
    }
    "application/octet-stream"
}

public func resolvePreviewKind(path: String, rawMime: String, isDir: Bool): String {
    if (isDir) {
        return "directory"
    }

    let mimeType = resolvePreviewMimeType(rawMime, path, false)
    if (strStartsWithPreview(mimeType, "image/")) {
        return "image"
    }
    if (strStartsWithPreview(mimeType, "video/")) {
        return "video"
    }
    if (strStartsWithPreview(mimeType, "audio/")) {
        return "audio"
    }
    if (mimeType == "application/pdf") {
        return "pdf"
    }

    let ext = lowerPathExtension(path)
    if (isCodeExtension(ext) || isCodeMimeType(mimeType)) {
        return "code"
    }
    if (isTextMimeType(mimeType) || isLikelyTextExtension(ext)) {
        return "text"
    }
    "unsupported"
}

public func resolvePreviewLanguage(path: String, rawMime: String): String {
    let mimeType = resolvePreviewMimeType(rawMime, path, false)
    let ext = lowerPathExtension(path)

    if (ext == "cj") { return "cangjie" }
    if (ext == "js" || ext == "mjs" || ext == "cjs") { return "javascript" }
    if (ext == "ts" || ext == "tsx") { return "typescript" }
    if (ext == "jsx") { return "jsx" }
    if (ext == "json") { return "json" }
    if (ext == "xml") { return "xml" }
    if (ext == "yaml" || ext == "yml") { return "yaml" }
    if (ext == "md") { return "markdown" }
    if (ext == "html" || ext == "htm") { return "html" }
    if (ext == "css") { return "css" }
    if (ext == "rs") { return "rust" }
    if (ext == "go") { return "go" }
    if (ext == "java") { return "java" }
    if (ext == "py") { return "python" }
    if (ext == "sh") { return "shell" }
    if (ext == "sql") { return "sql" }
    if (ext == "toml") { return "toml" }
    if (ext == "ini" || ext == "cfg" || ext == "conf") { return "ini" }
    if (ext == "log") { return "log" }
    if (ext == "csv") { return "csv" }

    if (mimeType == "application/json") { return "json" }
    if (mimeType == "application/xml") { return "xml" }
    if (mimeType == "application/yaml") { return "yaml" }
    if (mimeType == "application/javascript") { return "javascript" }
    if (mimeType == "application/typescript") { return "typescript" }
    if (strStartsWithPreview(mimeType, "text/html")) { return "html" }
    if (strStartsWithPreview(mimeType, "text/css")) { return "css" }
    if (strStartsWithPreview(mimeType, "text/markdown")) { return "markdown" }
    if (strStartsWithPreview(mimeType, "text/")) { return "text" }
    ""
}

public func isTextPreviewKind(kind: String): Bool {
    kind == "text" || kind == "code"
}

func lowerPathExtension(path: String): String {
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

func isLikelyTextExtension(ext: String): Bool {
    ext == "txt" ||
        ext == "md" ||
        ext == "json" ||
        ext == "xml" ||
        ext == "yaml" ||
        ext == "yml" ||
        ext == "toml" ||
        ext == "ini" ||
        ext == "cfg" ||
        ext == "conf" ||
        ext == "properties" ||
        ext == "lock" ||
        ext == "log" ||
        ext == "csv" ||
        ext == "html" ||
        ext == "htm" ||
        ext == "css" ||
        ext == "js" ||
        ext == "mjs" ||
        ext == "cjs" ||
        ext == "ts" ||
        ext == "tsx" ||
        ext == "jsx" ||
        ext == "cj" ||
        ext == "rs" ||
        ext == "go" ||
        ext == "java" ||
        ext == "py" ||
        ext == "sh" ||
        ext == "sql"
}

func isCodeExtension(ext: String): Bool {
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
        ext == "css" ||
        ext == "html" ||
        ext == "htm"
}

func isTextMimeType(mimeType: String): Bool {
    strStartsWithPreview(mimeType, "text/") ||
        mimeType == "application/json" ||
        mimeType == "application/xml" ||
        mimeType == "application/yaml" ||
        mimeType == "application/javascript" ||
        mimeType == "application/typescript"
}

func isCodeMimeType(mimeType: String): Bool {
    mimeType == "application/javascript" ||
        mimeType == "application/typescript" ||
        mimeType == "application/json" ||
        mimeType == "application/xml" ||
        mimeType == "application/yaml" ||
        strStartsWithPreview(mimeType, "text/html") ||
        strStartsWithPreview(mimeType, "text/css")
}

func strStartsWithPreview(text: String, prefix: String): Bool {
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
