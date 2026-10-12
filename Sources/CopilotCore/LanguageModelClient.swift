import Foundation

/// An injectable provider client that consumes complete conversation context.
public protocol LanguageModelClient: Sendable {
    /// Returns visible assistant text, or throws when the request cannot complete.
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
    /// Emits visible text increments and propagates cancellation or incomplete-response failures.
    func stream(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage],
        onDelta: @escaping @Sendable (String) async throws -> Void) async throws
}

public extension LanguageModelClient {
    /// Keeps injected clients and previews compatible with the streaming UI.
    func stream(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage],
        onDelta: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        let text = try await complete(configuration: configuration, apiKey: apiKey, messages: messages)
        try Task.checkCancellation()
        try await onDelta(text)
    }
}

/// A protocol adapter over injectable HTTP I/O, with safe provider and network errors.
public struct URLSessionLanguageModelClient: LanguageModelClient {
    private let transport: any HTTPTransport
    public init(transport: any HTTPTransport = URLSessionHTTPTransport()) { self.transport = transport }

    public func stream(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage],
        onDelta: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let request = try Self.makeRequest(
            configuration: configuration, apiKey: apiKey, messages: messages, streaming: true)
        let decoder = ModelStreamDecoder(apiProtocol: configuration.apiProtocol)
        do {
            try await transport.stream(
                request,
                onResponse: { status, contentType in
                    try await decoder.start(status: status, contentType: contentType)
                },
                onData: { data in
                    for delta in try await decoder.consume(data) {
                        try Task.checkCancellation()
                        try await onDelta(delta)
                    }
                })
            for delta in try await decoder.finish() { try await onDelta(delta) }
            try Task.checkCancellation()
        } catch is CancellationError { throw CancellationError() } catch let error as URLError
            where error.code == .cancelled
        { throw CancellationError() } catch let error as URLError {
            throw CopilotError.networkFailure(error.errorCode)
        } catch let error as CopilotError { throw error } catch { throw CopilotError.networkUnavailable }
    }

    public func complete(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]
    ) async throws -> String {
        try Task.checkCancellation()
        let request = try Self.makeRequest(configuration: configuration, apiKey: apiKey, messages: messages)
        let result: HTTPResult
        do { result = try await transport.send(request) } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled { throw CancellationError() } catch let error
            as URLError
        { throw CopilotError.networkFailure(error.errorCode) } catch let error as CopilotError { throw error } catch {
            throw CopilotError.networkUnavailable
        }
        try Task.checkCancellation()
        guard (200..<300).contains(result.statusCode) else { throw CopilotError.httpStatus(result.statusCode) }
        return try Self.decodeResponse(result.data, apiProtocol: configuration.apiProtocol)
    }

}
