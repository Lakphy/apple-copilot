import Foundation

public protocol LanguageModelClient: Sendable {
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
}

public struct HTTPResult: Sendable {
    public let data: Data
    public let statusCode: Int
    public init(data: Data, statusCode: Int) { self.data = data; self.statusCode = statusCode }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResult
}

/// All redirects are rejected. Credentials never follow a redirect to a different origin.
public final class URLSessionHTTPTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, Sendable {
    public override init() { super.init() }

    public func send(_ request: URLRequest) async throws -> HTTPResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CopilotError.invalidResponse }
        return HTTPResult(data: data, statusCode: response.statusCode)
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct URLSessionLanguageModelClient: LanguageModelClient {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) { self.transport = transport }

    public func complete(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]
    ) async throws -> String {
        try Task.checkCancellation()
        let request = try Self.makeRequest(configuration: configuration, apiKey: apiKey, messages: messages)
        let result: HTTPResult
        do { result = try await transport.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as CopilotError { throw error }
        catch { throw CopilotError.networkUnavailable }
        try Task.checkCancellation()
        guard (200..<300).contains(result.statusCode) else { throw CopilotError.httpStatus(result.statusCode) }
        return try Self.decodeResponse(result.data, apiProtocol: configuration.apiProtocol)
    }

    public static func makeRequest(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]
    ) throws -> URLRequest {
        try configuration.validate()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw CopilotError.missingAPIKey }
        guard !key.contains(where: { $0.isNewline || $0 == "\r" }) else {
            throw CopilotError.invalidConfiguration("API Key 不能包含换行。")
        }
        var request = URLRequest(url: try configuration.resolvedEndpoint())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let turns = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any]
        switch configuration.apiProtocol {
        case .openAIChatCompletions:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = ["model": configuration.model, "messages": [
                ["role": "system", "content": configuration.resolvedPrompt]
            ] + turns, "stream": false]
        case .openAIResponses:
            request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            body = ["model": configuration.model, "instructions": configuration.resolvedPrompt,
                    "input": turns, "store": false, "stream": false]
        case .anthropicMessages:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": configuration.model, "system": configuration.resolvedPrompt,
                    "messages": turns, "max_tokens": 4096, "stream": false]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public static func decodeResponse(_ data: Data, apiProtocol: APIProtocol) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CopilotError.invalidResponse
        }
        let text: String
        switch apiProtocol {
        case .openAIChatCompletions:
            guard let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                throw CopilotError.invalidResponse
            }
            if let content = message["content"] as? String { text = content }
            else if let content = message["content"] as? [[String: Any]] {
                text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
            } else { throw CopilotError.emptyResponse }
        case .openAIResponses:
            guard let output = root["output"] as? [[String: Any]] else { throw CopilotError.invalidResponse }
            text = output.filter { $0["type"] as? String == "message" }
                .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        case .anthropicMessages:
            guard let content = root["content"] as? [[String: Any]] else { throw CopilotError.invalidResponse }
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CopilotError.emptyResponse }
        return text
    }
}

/// Preview rendering never makes a live API request.
public struct PreviewLanguageModelClient: LanguageModelClient {
    public init() {}
    public func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String {
        try Task.checkCancellation()
        return messages.count == 1 ? "好的设计让复杂的事情变得简单。" : "这里的 simple 强调易于理解与使用，可以译为“简单”或“简洁”。"
    }
}
