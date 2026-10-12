import Foundation

/// Incremental SSE framing, independent of TCP chunk boundaries and UTF-8 splits.
/// Only visible output is emitted; reasoning and tool arguments are never shown.
actor ModelStreamDecoder {
    private let apiProtocol: APIProtocol
    private var isJSON = false
    private var json = Data()
    private var line = Data()
    private var previousWasCR = false
    private var eventName = ""
    private var eventData: [String] = []
    private var eventSize = 0
    private var completed = false
    private var hasText = false
    private var firstLine = true

    init(apiProtocol: APIProtocol) { self.apiProtocol = apiProtocol }

    func start(status: Int, contentType: String) throws {
        guard (200..<300).contains(status) else { throw CopilotError.httpStatus(status) }
        let type = contentType.lowercased().split(separator: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
        isJSON = type == "application/json" || type.hasSuffix("+json")
        guard isJSON || type == "text/event-stream" else { throw CopilotError.invalidResponse }
    }

    func consume(_ data: Data) throws -> [String] {
        if isJSON {
            guard json.count + data.count <= 8 * 1024 * 1024 else { throw CopilotError.invalidResponse }
            json.append(data)
            return []
        }
        var output: [String] = []
        for byte in data {
            if byte == 10 && previousWasCR { previousWasCR = false; continue }
            previousWasCR = byte == 13
            if byte == 10 || byte == 13 {
                output += try consumeLine()
            } else {
                line.append(byte)
                guard line.count <= 1024 * 1024 else { throw CopilotError.invalidResponse }
            }
        }
        return output
    }

    func finish() throws -> [String] {
        if isJSON {
            return [try URLSessionLanguageModelClient.decodeResponse(json, apiProtocol: apiProtocol)]
        }
        var output = try consumeLine()
        output += try dispatchEvent()
        guard completed else { throw CopilotError.streamInterrupted }
        guard hasText else { throw CopilotError.emptyResponse }
        return output
    }

    private func consumeLine() throws -> [String] {
        guard var text = String(data: line, encoding: .utf8) else { throw CopilotError.invalidResponse }
        line.removeAll(keepingCapacity: true)
        if firstLine { firstLine = false; if text.hasPrefix("\u{FEFF}") { text.removeFirst() } }
        if text.isEmpty { return try dispatchEvent() }
        if text.hasPrefix(":") { return [] }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if field == "event" { eventName = value }
        if field == "data" {
            eventSize += value.utf8.count
            guard eventSize <= 1024 * 1024 else { throw CopilotError.invalidResponse }
            eventData.append(value)
        }
        return []
    }

    private func dispatchEvent() throws -> [String] {
        defer { eventData.removeAll(keepingCapacity: true); eventName = ""; eventSize = 0 }
        guard !eventData.isEmpty else { return [] }
        let data = eventData.joined(separator: "\n")
        if data == "[DONE]", apiProtocol == .openAIChatCompletions { completed = true; return [] }
        guard let root = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any] else {
            throw CopilotError.invalidResponse
        }
        let type = root["type"] as? String ?? eventName
        if root["error"] != nil || ["error", "response.failed", "response.incomplete"].contains(type) {
            throw CopilotError.streamInterrupted
        }
        guard !completed else { return [] }
        var text: String?
        switch apiProtocol {
        case .openAIChatCompletions:
            if let choices = root["choices"] as? [[String: Any]],
                let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 })
            {
                if let reason = choice["finish_reason"] as? String, ["length", "content_filter"].contains(reason) {
                    throw CopilotError.streamInterrupted
                }
                text = (choice["delta"] as? [String: Any])?["content"] as? String
            }
        case .openAIResponses:
            if type == "response.output_text.delta" { text = root["delta"] as? String }
            if type == "response.completed" {
                let response = root["response"] as? [String: Any]
                if let status = response?["status"] as? String, status != "completed" {
                    throw CopilotError.streamInterrupted
                }
                completed = true
            }
        case .anthropicMessages:
            if type == "content_block_delta", let delta = root["delta"] as? [String: Any],
                delta["type"] as? String == "text_delta"
            {
                text = delta["text"] as? String
            }
            if type == "content_block_start", let block = root["content_block"] as? [String: Any],
                block["type"] as? String == "text"
            {
                text = block["text"] as? String
            }
            if type == "message_delta", let delta = root["delta"] as? [String: Any],
                delta["stop_reason"] as? String == "max_tokens"
            {
                throw CopilotError.streamInterrupted
            }
            if type == "message_stop" { completed = true }
        }
        guard let text, !text.isEmpty else { return [] }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { hasText = true }
        return [text]
    }
}
