import Foundation
import Testing
@testable import CopilotCore

@Suite("Incremental provider streaming")
struct StreamingTests {
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COPILOT_STREAM_TEST_URL"] != nil,
            "Run Scripts/test.sh to start an isolated loopback fixture"))
    func completeTransportPreservesHTTPResponseMetadata() async throws {
        let value = try #require(ProcessInfo.processInfo.environment["COPILOT_STREAM_TEST_URL"])
        let base = try #require(URL(string: value))
        let request = URLRequest(url: base.deletingLastPathComponent().appendingPathComponent("health"))
        let result = try await URLSessionHTTPTransport().send(request)
        #expect(result.statusCode == 200)
        #expect(result.contentType == "application/json; charset=utf-8")
        let body = try #require(JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        #expect(body["ready"] as? Bool == true)
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["COPILOT_STREAM_TEST_URL"] != nil,
            "Start Scripts/mock_model_server.py and set COPILOT_STREAM_TEST_URL to run live loopback transport checks"),
        arguments: APIProtocol.allCases)
    func streamsOverRealURLSession(apiProtocol: APIProtocol) async throws {
        let url = try #require(ProcessInfo.processInfo.environment["COPILOT_STREAM_TEST_URL"])
        let config = ProviderConfiguration(
            apiProtocol: apiProtocol, baseURL: url, model: "copilot-test-model", allowLocalHTTP: true)
        let received = DeltaRecorder()
        try await URLSessionLanguageModelClient().stream(
            configuration: config, apiKey: "local-simulator-key",
            messages: [ChatMessage(role: .user, content: "Good design makes complex things simple.")]
        ) {
            await received.append($0)
        }
        #expect(await received.text == "优秀的设计让复杂的事情变得简单。")
        #expect(await received.count > 1)
    }

    static let fixtures: [(APIProtocol, String)] = [
        (
            .openAIChatCompletions,
            """
            : heartbeat
            data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}

            data: {"choices":[{"index":0,"delta":{"content":"你好🙂"}}]}

            data: {"choices":[{"index":1,"delta":{"content":"ignore"}}]}

            data: {"choices":[{"index":0,"delta":{"content":" Markdown"}}]}

            data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

            data: [DONE]

            """
        ),
        (
            .openAIResponses,
            """
            event: response.reasoning_summary_text.delta
            data: {"type":"response.reasoning_summary_text.delta","delta":"hidden"}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":"你好🙂"}

            event: response.output_text.delta
            data: {"type":"response.output_text.delta","delta":" Markdown"}

            event: response.output_text.done
            data: {"type":"response.output_text.done","text":"你好🙂 Markdown"}

            event: response.completed
            data: {"type":"response.completed","response":{"status":"completed"}}

            """
        ),
        (
            .anthropicMessages,
            """
            event: ping
            data: {"type":"ping"}

            event: content_block_start
            data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好🙂"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":1,"delta":{"type":"thinking_delta","thinking":"hidden"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" Markdown"}}

            event: message_stop
            data: {"type":"message_stop"}

            """
        ),
    ]

    @Test(arguments: fixtures)
    func handlesEveryByteBoundaryIncludingUTF8(values: (APIProtocol, String)) async throws {
        for newline in ["\n", "\r\n", "\r"] {
            let decoder = ModelStreamDecoder(apiProtocol: values.0)
            try await decoder.start(status: 200, contentType: "text/event-stream; charset=utf-8")
            var text = ""
            let data = "\u{FEFF}" + values.1.replacingOccurrences(of: "\n", with: newline)
            for byte in data.utf8 { text += try await decoder.consume(Data([byte])).joined() }
            text += try await decoder.finish().joined()
            #expect(text == "你好🙂 Markdown")
        }
    }

    @Test func multilineDataAndUnterminatedFinalEvent() async throws {
        let decoder = ModelStreamDecoder(apiProtocol: .openAIResponses)
        try await decoder.start(status: 200, contentType: "text/event-stream")
        let deltas = try await decoder.consume(
            Data(
                """
                event: response.output_text.delta
                data: {"type":"response.output_text.delta",
                data: "delta":"Hello"}

                event: response.completed
                data: {"type":"response.completed"}
                """.utf8))
        #expect(deltas == ["Hello"])
        #expect(try await decoder.finish().isEmpty)
    }

    @Test(arguments: APIProtocol.allCases)
    func streamRequestPreservesContextAndCredentials(apiProtocol: APIProtocol) throws {
        let config = ProviderConfiguration(apiProtocol: apiProtocol)
        let request = try URLSessionLanguageModelClient.makeRequest(
            configuration: config, apiKey: "test-key",
            messages: [ChatMessage(role: .user, content: "test")], streaming: true)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
    }

    @Test func earlyEOFAndErrorEventsAreNeverSuccessful() async throws {
        let decoder = ModelStreamDecoder(apiProtocol: .openAIChatCompletions)
        try await decoder.start(status: 200, contentType: "text/event-stream")
        #expect(
            try await decoder.consume(Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8)) == [
                "partial"
            ])
        await #expect(throws: CopilotError.streamInterrupted) { try await decoder.finish() }
        let failure = ModelStreamDecoder(apiProtocol: .anthropicMessages)
        try await failure.start(status: 200, contentType: "text/event-stream")
        await #expect(throws: CopilotError.streamInterrupted) {
            try await failure.consume(
                Data("event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"secret\"}}\n\n".utf8))
        }
        #expect(!CopilotError.streamInterrupted.localizedDescription.contains("secret"))
    }

    @Test func malformedContentAndEmptyCompletionFail() async throws {
        let invalid = ModelStreamDecoder(apiProtocol: .openAIResponses)
        try await invalid.start(status: 200, contentType: "text/event-stream")
        await #expect(throws: CopilotError.invalidResponse) {
            try await invalid.consume(Data("data: invalid\n\n".utf8))
        }
        let empty = ModelStreamDecoder(apiProtocol: .openAIChatCompletions)
        try await empty.start(status: 200, contentType: "text/event-stream")
        _ = try await empty.consume(Data("data: [DONE]\n\n".utf8))
        await #expect(throws: CopilotError.emptyResponse) { try await empty.finish() }
    }

    @Test func compatibleJSONReplyIsAcceptedWithoutASecondRequest() async throws {
        let client = URLSessionLanguageModelClient(transport: JSONStreamTransport())
        let received = DeltaRecorder()
        try await client.stream(configuration: .default, apiKey: "test-key", messages: []) { await received.append($0) }
        #expect(await received.text == "compatible")
    }

    @Test func statusAndContentTypeAreValidatedBeforeContent() async throws {
        let decoder = ModelStreamDecoder(apiProtocol: .openAIResponses)
        await #expect(throws: CopilotError.httpStatus(401)) {
            try await decoder.start(status: 401, contentType: "text/event-stream")
        }
        await #expect(throws: CopilotError.invalidResponse) {
            try await decoder.start(status: 200, contentType: "text/html")
        }
    }
}

private actor DeltaRecorder {
    var text = ""
    var count = 0
    func append(_ delta: String) { text += delta; count += 1 }
}

private struct JSONStreamTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResult {
        HTTPResult(data: Data(#"{"choices":[{"message":{"content":"compatible"}}]}"#.utf8), statusCode: 200)
    }
}

@Suite("Streaming state, cancellation and persistence") @MainActor
struct StreamingStoreTests {
    private func settings() async -> SettingsStore {
        let store = SettingsStore(repository: MemorySettingsRepository(), credentials: MemoryCredentialStore())
        store.apiKey = "test-key"
        await store.save()
        return store
    }

    @Test func partialOutputAppearsBeforeCompletionAndPersistsOnce() async throws {
        let client = ControlledStreamingClient()
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: await settings())
        let request = Task { await store.translate("Hello") }
        await client.waitForPartial()
        #expect(store.isWorking)
        #expect(store.streamingMessage?.content == "**Bonjour")
        let id = try #require(store.streamingMessage?.id)
        #expect(store.conversation?.messages.isEmpty == true)
        #expect(await repository.history().isEmpty)
        await client.release()
        await request.value
        #expect(store.streamingMessage == nil)
        #expect(store.conversation?.messages.last?.id == id)
        #expect(store.conversation?.messages.last?.content == "**Bonjour**")
        #expect(await repository.history().first?.messages.count == 2)
    }

    @Test func cancelPreservesReadablePartialWithoutPersistingOrAcceptingLateTokens() async throws {
        let client = ControlledStreamingClient()
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: await settings())
        let request = Task { await store.translate("Hello") }
        await client.waitForPartial()
        store.cancel()
        #expect(store.streamingMessage?.content == "**Bonjour")
        await client.release()
        await request.value
        #expect(store.requestState == .cancelled)
        #expect(store.streamingMessage?.content == "**Bonjour")
        #expect(await repository.history().isEmpty)
        store.select(CopilotPreviewFixtures.conversation)
        #expect(store.streamingMessage == nil)
    }

    @Test func errorPreservesPartialAndRetryReplacesIt() async throws {
        let client = ControlledStreamingClient(fails: true)
        let repository = MemoryConversationRepository()
        let store = ConversationStore(client: client, repository: repository, settings: await settings())
        let request = Task { await store.translate("Hello") }
        await client.waitForPartial()
        await client.release()
        await request.value
        #expect(store.requestState == .failed)
        #expect(store.streamingMessage?.content == "**Bonjour")
        #expect(store.conversation?.messages.isEmpty == true)
        #expect(await repository.history().isEmpty)
        store.newConversation()
        #expect(store.streamingMessage == nil)
    }
}

private actor ControlledStreamingClient: LanguageModelClient {
    private var started = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var gate: CheckedContinuation<Void, Never>?
    private let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func complete(configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage]) async throws -> String
    { "unused" }
    func stream(
        configuration: ProviderConfiguration, apiKey: String, messages: [ChatMessage],
        onDelta: @escaping @Sendable (String) async throws -> Void
    ) async throws {
        try await onDelta("**Bonjour")
        await withCheckedContinuation { continuation in
            gate = continuation; started = true
            waiting.forEach { $0.resume() }; waiting = []
        }
        if fails { throw CopilotError.streamInterrupted }
        try await onDelta("**")
    }
    func waitForPartial() async {
        if started { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() { gate?.resume(); gate = nil }
}
