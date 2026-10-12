import Foundation

/// Provider-specific request encoding and complete-response decoding.
/// Streaming event decoding lives in `ModelStreamDecoder`.
extension URLSessionLanguageModelClient {
    /// Creates a validated provider request without logging credentials or message contents.
    public static func makeRequest(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage], streaming: Bool = false
    ) throws -> URLRequest {
        try configuration.validate()
        let key = try validatedAPIKey(apiKey)
        guard !key.isEmpty else { throw CopilotError.missingAPIKey }
        var request = URLRequest(url: try configuration.resolvedEndpoint())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        let turns = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let prompt = configuration.resolvedPrompt(context: PromptContext(messages: messages))
        let body: [String: Any]
        switch configuration.apiProtocol {
        case .openAIChatCompletions:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = [
                "model": configuration.model,
                "messages": [
                    ["role": "system", "content": prompt]
                ] + turns, "stream": streaming,
            ]
        case .openAIResponses:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = [
                "model": configuration.model, "instructions": prompt,
                "input": turns, "store": false, "stream": streaming,
            ]
        case .anthropicMessages:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": configuration.model, "system": prompt,
                "messages": turns, "max_tokens": 4096, "stream": streaming,
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Decodes visible assistant text, rejecting malformed or empty provider responses.
    public static func decodeResponse(_ data: Data, apiProtocol: APIProtocol) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CopilotError.invalidResponse
        }
        let text: String
        switch apiProtocol {
        case .openAIChatCompletions:
            guard let choices = root["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any]
            else {
                throw CopilotError.invalidResponse
            }
            if let content = message["content"] as? String {
                text = content
            } else if let content = message["content"] as? [[String: Any]] {
                text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(
                    separator: "\n")
            } else {
                throw CopilotError.emptyResponse
            }
        case .openAIResponses:
            guard let output = root["output"] as? [[String: Any]] else { throw CopilotError.invalidResponse }
            text = output.filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .anthropicMessages:
            guard let content = root["content"] as? [[String: Any]] else { throw CopilotError.invalidResponse }
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(
                separator: "\n")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CopilotError.emptyResponse }
        return text
    }
}
