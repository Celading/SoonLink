package soonlnk.product

import soonlnk.commons.*
import ignite.api2.GetData
import std.fs.{File, OpenMode}
import std.convert.*
import std.unicode.*

public func runMcpServer(config: AppConfig, profile!: ProductProfile = resolveProductProfile()): Int64 {
    let runtime = AutomationRuntime(config, profile: profile)
    let stdinFile = File("/dev/stdin", OpenMode.Read)
    let stdoutFile = File("/dev/stdout", OpenMode.Write)

    try {
        runtime.start()
        while (true) {
            match (readMcpMessage(stdinFile)) {
                case Some(requestBody) =>
                    var response: ?String = None
                    try {
                        response = dispatchMcpRequest(runtime, requestBody)
                    } catch (e: Exception) {
                        match (extractJsonRawValue(requestBody, "id")) {
                            case Some(rawId) =>
                                response = Some(buildJsonRpcError(rawId, -32603, "internal error: ${e.message}"))
                            case None => ()
                        }
                    }
                    if (let Some(payload) <- response) {
                        writeMcpResponse(stdoutFile, payload)
                    }
                case None =>
                    break
            }
        }
        0
    } finally {
        runtime.stop()
        stdoutFile.close()
        stdinFile.close()
    }
}

public func dispatchMcpRequest(runtime: AutomationRuntime, requestBody: String): ?String {
    let method = parseJsonString(requestBody, "method") ?? ""
    let requestId = extractJsonRawValue(requestBody, "id")
    if (method.size == 0) {
        match (requestId) {
            case Some(rawId) => return Some(buildJsonRpcError(rawId, -32600, "invalid request"))
            case None => return None
        }
    }

    match (method) {
        case "notifications/initialized" =>
            None
        case "ping" =>
            buildOptionalJsonRpcSuccess(requestId, JsonObject().toString())
        case "initialize" =>
            buildOptionalJsonRpcSuccess(requestId, buildMcpInitializeResult(runtime.profile))
        case "tools/list" =>
            buildOptionalJsonRpcSuccess(requestId, buildMcpToolsListResult(runtime.profile))
        case "resources/list" =>
            buildOptionalJsonRpcSuccess(requestId, JsonObject().putArr("resources", JsonArray()).toString())
        case "prompts/list" =>
            buildOptionalJsonRpcSuccess(requestId, JsonObject().putArr("prompts", JsonArray()).toString())
        case "tools/call" =>
            match (requestId) {
                case Some(rawId) =>
                    Some(buildJsonRpcSuccess(rawId, buildMcpToolCallResult(runtime, requestBody)))
                case None =>
                    None
            }
        case _ =>
            match (requestId) {
                case Some(rawId) =>
                    Some(buildJsonRpcError(rawId, -32601, "method not found: ${method}"))
                case None =>
                    None
            }
    }
}

func buildOptionalJsonRpcSuccess(requestId: ?String, resultRaw: String): ?String {
    match (requestId) {
        case Some(rawId) => Some(buildJsonRpcSuccess(rawId, resultRaw))
        case None => None
    }
}

func buildJsonRpcSuccess(rawId: String, resultRaw: String): String {
    JsonObject()
        .put("jsonrpc", "2.0")
        .putRaw("id", rawId)
        .putRaw("result", resultRaw)
        .toString()
}

func buildJsonRpcError(rawId: String, code: Int64, message: String): String {
    JsonObject()
        .put("jsonrpc", "2.0")
        .putRaw("id", rawId)
        .putObj("error", JsonObject()
            .putInt("code", code)
            .put("message", message)
        )
        .toString()
}

func buildMcpInitializeResult(profile: ProductProfile): String {
    let version = resolveProductVersion(GetData.GetDataClass.ModuleVer())
    JsonObject()
        .put("protocolVersion", "2024-11-05")
        .putObj("capabilities", JsonObject()
            .putObj("tools", JsonObject()
                .putBool("listChanged", false)
            )
        )
        .putObj("serverInfo", JsonObject()
            .put("name", "${profile.productName} MCP")
            .put("version", version)
        )
        .toString()
}

func buildMcpToolsListResult(profile: ProductProfile): String {
    let tools = JsonArray()
    tools.addObj(buildMcpToolSpec(
        "soonlink_status",
        "${profile.productName} runtime status, config and local system snapshot",
        "{\"type\":\"object\",\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_capabilities",
        "${profile.productName} edition capability map and tags",
        "{\"type\":\"object\",\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_list_devices",
        "List known SoonLink devices or fetch one device by id",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"}},\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_list_tasks",
        "List transfer tasks or fetch one task by id",
        "{\"type\":\"object\",\"properties\":{\"taskId\":{\"type\":\"string\"}},\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_list_connectors",
        "List available connector drivers and device-to-connector bindings",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"}},\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_register_device",
        "Register or update one manual SoonLink device endpoint",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"deviceType\":{\"type\":\"string\"},\"connectorType\":{\"type\":\"string\"},\"scheme\":{\"type\":\"string\"},\"basePath\":{\"type\":\"string\"},\"ip\":{\"type\":\"string\"},\"port\":{\"type\":\"integer\"}},\"required\":[\"deviceId\",\"ip\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_remove_device",
        "Remove one manual SoonLink device endpoint by id",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"}},\"required\":[\"deviceId\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_set_device_trust",
        "Set one device trust state to trusted, blocked, or unknown",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"},\"state\":{\"type\":\"string\",\"enum\":[\"trusted\",\"blocked\",\"unknown\"]}},\"required\":[\"deviceId\",\"state\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_start_device_pin_pairing",
        "Create a one-time PIN pairing session for one device",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"}},\"required\":[\"deviceId\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_confirm_device_pin_pairing",
        "Confirm one device PIN pairing session and mark it trusted",
        "{\"type\":\"object\",\"properties\":{\"deviceId\":{\"type\":\"string\"},\"pin\":{\"type\":\"string\"}},\"required\":[\"deviceId\",\"pin\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_list_dir",
        "List files under a device path",
        "{\"type\":\"object\",\"properties\":{\"device\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_get_file_info",
        "Get metadata for one file or directory",
        "{\"type\":\"object\",\"properties\":{\"device\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"path\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_summarize_path",
        "Summarize a file or directory for transfer planning",
        "{\"type\":\"object\",\"properties\":{\"device\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"path\"],\"additionalProperties\":false}"
    ))
    tools.addObj(buildMcpToolSpec(
        "soonlink_create_transfer_task",
        "Create a SoonLink transfer task between two known devices",
        "{\"type\":\"object\",\"properties\":{\"sourceDevice\":{\"type\":\"string\"},\"targetDevice\":{\"type\":\"string\"},\"filePath\":{\"type\":\"string\"},\"targetPath\":{\"type\":\"string\"}},\"required\":[\"sourceDevice\",\"targetDevice\",\"filePath\"],\"additionalProperties\":false}"
    ))
    JsonObject()
        .putArr("tools", tools)
        .toString()
}

func buildMcpToolSpec(name: String, description: String, schemaRaw: String): JsonObject {
    JsonObject()
        .put("name", name)
        .put("description", description)
        .putRaw("inputSchema", schemaRaw)
}

func buildMcpToolCallResult(runtime: AutomationRuntime, requestBody: String): String {
    let toolName = parseJsonString(requestBody, "name") ?? ""
    if (toolName.size == 0) {
        return buildMcpErrorResult(buildMachineErrorPayload("MCP_MISSING_TOOL", "缺少 tool name"))
    }

    let payload = match (toolName) {
        case "soonlink_status" =>
            buildStatusPayload(runtime)
        case "soonlink_capabilities" =>
            JsonObject()
                .putBool("success", true)
                .put("edition", runtime.profile.edition)
                .putObj("capabilities", productCapabilitiesToJson(runtime.profile))
                .putArr("capabilityTags", productCapabilityTags(runtime.profile))
                .toString()
        case "soonlink_list_devices" =>
            buildDevicesPayload(runtime, parseJsonString(requestBody, "deviceId") ?? "")
        case "soonlink_list_tasks" =>
            buildTasksPayload(runtime, parseJsonString(requestBody, "taskId") ?? "")
        case "soonlink_list_connectors" =>
            buildConnectorsPayload(runtime, parseJsonString(requestBody, "deviceId") ?? "")
        case "soonlink_register_device" =>
            buildUpsertDevicePayload(runtime, buildMcpDeviceRecord(requestBody, Int64(runtime.config.webPort)))
        case "soonlink_remove_device" =>
            buildRemoveDevicePayload(runtime, parseJsonString(requestBody, "deviceId") ?? "")
        case "soonlink_set_device_trust" =>
            buildDeviceTrustPayload(
                runtime,
                parseJsonString(requestBody, "deviceId") ?? "",
                parseJsonString(requestBody, "state") ?? ""
            )
        case "soonlink_start_device_pin_pairing" =>
            buildDevicePinStartPayload(
                runtime,
                parseJsonString(requestBody, "deviceId") ?? ""
            )
        case "soonlink_confirm_device_pin_pairing" =>
            buildDevicePinConfirmPayload(
                runtime,
                parseJsonString(requestBody, "deviceId") ?? "",
                parseJsonString(requestBody, "pin") ?? ""
            )
        case "soonlink_list_dir" =>
            buildFsListPayload(
                runtime,
                parseJsonString(requestBody, "device") ?? "local",
                parseJsonString(requestBody, "path") ?? "/"
            )
        case "soonlink_get_file_info" =>
            buildFsInfoPayload(
                runtime,
                parseJsonString(requestBody, "device") ?? "local",
                parseJsonString(requestBody, "path") ?? ""
            )
        case "soonlink_summarize_path" =>
            buildSummaryPayload(
                runtime,
                parseJsonString(requestBody, "device") ?? "local",
                parseJsonString(requestBody, "path") ?? ""
            )
        case "soonlink_create_transfer_task" =>
            buildTransferTaskPayload(
                runtime,
                parseJsonString(requestBody, "sourceDevice") ?? "local",
                parseJsonString(requestBody, "targetDevice") ?? "",
                parseJsonString(requestBody, "filePath") ?? "",
                parseJsonString(requestBody, "targetPath") ?? ""
            )
        case _ =>
            buildMachineErrorPayload("MCP_UNKNOWN_TOOL", "未知工具: ${toolName}")
    }

    if (payload.contains("\"success\":false")) {
        return buildMcpErrorResult(payload)
    }
    buildMcpSuccessResult(payload)
}

func buildMcpSuccessResult(payloadJson: String): String {
    let content = JsonArray()
        .addObj(JsonObject()
            .put("type", "text")
            .put("text", payloadJson)
        )
    JsonObject()
        .putArr("content", content)
        .putRaw("structuredContent", payloadJson)
        .toString()
}

func buildMcpErrorResult(payloadJson: String): String {
    let content = JsonArray()
        .addObj(JsonObject()
            .put("type", "text")
            .put("text", payloadJson)
        )
    JsonObject()
        .putBool("isError", true)
        .putArr("content", content)
        .putRaw("structuredContent", payloadJson)
        .toString()
}

func buildMcpDeviceRecord(requestBody: String, defaultPort: Int64): DeviceRegistryRecord {
    let record = DeviceRegistryRecord()
    record.id = parseJsonString(requestBody, "deviceId") ?? ""
    record.name = parseJsonString(requestBody, "name") ?? ""
    record.deviceType = parseJsonString(requestBody, "deviceType") ?? ""
    record.connectorType = parseJsonString(requestBody, "connectorType") ?? ""
    record.endpointScheme = parseJsonString(requestBody, "endpointScheme") ?? (parseJsonString(requestBody, "scheme") ?? "")
    record.endpointBasePath = parseJsonString(requestBody, "endpointBasePath") ?? (parseJsonString(requestBody, "basePath") ?? "")
    record.ip = parseJsonString(requestBody, "ip") ?? ""

    let portRaw = parseJsonString(requestBody, "port") ?? ""
    if (portRaw.trimAscii().size > 0) {
        try {
            record.port = Int64.parse(portRaw)
        } catch (_: Exception) {
            record.port = defaultPort
        }
    } else {
        record.port = defaultPort
    }
    record
}

func readMcpMessage(input: File): ?String {
    while (true) {
        match (readStdioLine(input)) {
            case Some(rawLine) =>
                let line = trimMcpLine(rawLine)
                if (line.size == 0) {
                    continue
                }
                if (strStartsWithMcp(line, "{")) {
                    return Some(line)
                }

                var contentLength: Int64 = -1
                match (parseContentLengthLine(line)) {
                    case Some(length) => contentLength = length
                    case None => ()
                }

                while (true) {
                    match (readStdioLine(input)) {
                        case Some(nextLineRaw) =>
                            let nextLine = trimMcpLine(nextLineRaw)
                            if (nextLine.size == 0) {
                                break
                            }
                            match (parseContentLengthLine(nextLine)) {
                                case Some(length) => contentLength = length
                                case None => ()
                            }
                        case None =>
                            return None
                    }
                }

                if (contentLength >= 0) {
                    return Some(readExactUtf8(input, contentLength))
                }
            case None =>
                return None
        }
    }
    None
}

func writeMcpResponse(output: File, payload: String): Unit {
    let body = stringToBytes(payload)
    let header =
        "Content-Length: ${body.size}\r\n" +
        "Content-Type: application/json\r\n\r\n"
    output.write(stringToBytes(header))
    output.write(body)
}

func readStdioLine(input: File): ?String {
    let out = Array<UInt8>(1, repeat: 0)
    var line = ""
    while (true) {
        let n = input.read(out)
        if (n <= 0) {
            if (line.size > 0) {
                return Some(line)
            }
            return None
        }
        line += runeFromByte(out[0]).toString()
        if (out[0] == UInt8(10)) {
            return Some(line)
        }
    }
    None
}

func readExactUtf8(input: File, length: Int64): String {
    let data = Array<UInt8>(length, repeat: 0)
    var offset: Int64 = 0
    while (offset < length) {
        let remaining = length - offset
        let chunk = Array<UInt8>(remaining, repeat: 0)
        let n = input.read(chunk)
        if (n <= 0) {
            break
        }
        for (i in 0..n) {
            data[offset + i] = chunk[i]
        }
        offset += n
    }
    if (offset == length) {
        return String.fromUtf8(data)
    }
    let actual = Array<UInt8>(offset, repeat: 0)
    for (i in 0..offset) {
        actual[i] = data[i]
    }
    String.fromUtf8(actual)
}

func parseContentLengthLine(line: String): ?Int64 {
    let normalized = line.trimAscii().toLower()
    if (!strStartsWithMcp(normalized, "content-length:")) {
        return None
    }
    let raw = strSubstring(line, 15, line.size).trimAscii()
    try {
        Some(Int64.parse(raw))
    } catch (_: Exception) {
        None
    }
}

func trimMcpLine(line: String): String {
    var out = line
    if (strEndsWithMcp(out, "\n")) {
        out = strSubstring(out, 0, out.size - 1)
    }
    if (strEndsWithMcp(out, "\r")) {
        out = strSubstring(out, 0, out.size - 1)
    }
    out
}

func extractJsonRawValue(json: String, field: String): ?String {
    let searchKey = "\"${field}\""
    let runes = json.toRuneArray()
    let keyRunes = searchKey.toRuneArray()
    var i: Int64 = 0
    while (i <= runes.size - keyRunes.size) {
        var found = true
        for (j in 0..keyRunes.size) {
            if (runes[i + j] != keyRunes[j]) {
                found = false
                break
            }
        }
        if (found) {
            var k = i + keyRunes.size
            while (k < runes.size && (runes[k] == r' ' || runes[k] == r':')) {
                k += 1
            }
            if (k >= runes.size) {
                return None
            }
            if (runes[k] == r'"') {
                let endAt = findJsonStringEnd(runes, k)
                return Some(strSubstring(json, k, endAt))
            }
            if (runes[k] == r'{' || runes[k] == r'[') {
                let endAt = findBalancedJsonEnd(runes, k)
                return Some(strSubstring(json, k, endAt))
            }
            let endAt = findScalarJsonEnd(runes, k)
            return Some(strSubstring(json, k, endAt).trimAscii())
        }
        i += 1
    }
    None
}

func findJsonStringEnd(runes: Array<Rune>, start: Int64): Int64 {
    var i = start + 1
    while (i < runes.size) {
        if (runes[i] == r'\\') {
            i += 2
            continue
        }
        if (runes[i] == r'"') {
            return i + 1
        }
        i += 1
    }
    runes.size
}

func findBalancedJsonEnd(runes: Array<Rune>, start: Int64): Int64 {
    var depth: Int64 = 0
    var i = start
    let openRune = runes[start]
    let closeRune = if (openRune == r'{') { r'}' } else { r']' }
    while (i < runes.size) {
        if (runes[i] == r'"') {
            i = findJsonStringEnd(runes, i)
            continue
        }
        if (runes[i] == openRune) {
            depth += 1
        } else if (runes[i] == closeRune) {
            depth -= 1
            if (depth == 0) {
                return i + 1
            }
        }
        i += 1
    }
    runes.size
}

func findScalarJsonEnd(runes: Array<Rune>, start: Int64): Int64 {
    var i = start
    while (i < runes.size) {
        if (runes[i] == r',' || runes[i] == r'}' || runes[i] == r']') {
            return i
        }
        i += 1
    }
    runes.size
}

func strStartsWithMcp(text: String, prefix: String): Bool {
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

func strEndsWithMcp(text: String, suffix: String): Bool {
    if (text.size < suffix.size) {
        return false
    }
    let textRunes = text.toRuneArray()
    let suffixRunes = suffix.toRuneArray()
    let start = textRunes.size - suffixRunes.size
    for (i in 0..suffixRunes.size) {
        if (textRunes[start + i] != suffixRunes[i]) {
            return false
        }
    }
    true
}

func runeFromByte(value: UInt8): Rune {
    Rune(UInt32(value))
}
