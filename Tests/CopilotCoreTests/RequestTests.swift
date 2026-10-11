import Foundation
import Testing
@testable import CopilotCore

@Suite("BYOK protocol adapters")
struct RequestTests {
    @Test(arguments: [
        (APIProtocol.openAIChatCompletions, "https://example.com", "https://example.com/v1/chat/completions"),
        (.openAIChatCompletions, "https://example.com/v1/", "https://example.com/v1/chat/completions"),
        (.openAIChatCompletions, "https://example.com/v1/chat/completions", "https://example.com/v1/chat/completions"),
        (.openAIResponses, "https://example.com/api/v1", "https://example.com/api/v1/responses"),
        (.openAIResponses, "https://example.com/v1/responses", "https://example.com/v1/responses"),
        (.anthropicMessages, "https://example.com/v1", "https://example.com/v1/messages"),
        (.anthropicMessages, "https://example.com/v1/messages/", "https://example.com/v1/messages")
    ])
    func resolvesEndpoint(values: (APIProtocol, String, String)) throws {
        let config = ProviderConfiguration(apiProtocol: values.0, baseURL: values.1)
        #expect(try config.resolvedEndpoint().absoluteString == values.2)
    }

    @Test(arguments: ["http://api.example.com/v1", "https://user:secret@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#secret", "file:///tmp/v1", "example.com/v1"])
    func rejectsUnsafeEndpoint(baseURL: String) {
        #expect(throws: CopilotError.self) { try ProviderConfiguration(baseURL: baseURL).resolvedEndpoint() }
    }

    @Test func httpRequiresExplicitLoopbackOptIn() throws {
        #expect(throws: CopilotError.self) { try ProviderConfiguration(baseURL: "http://localhost:8080/v1").resolvedEndpoint() }
        let local = ProviderConfiguration(baseURL: "http://localhost:8080/v1", allowLocalHTTP: true)
        #expect(try local.resolvedEndpoint().host == "localhost")
        #expect(throws: CopilotError.self) {
            try ProviderConfiguration(baseURL: "http://192.168.1.2/v1", allowLocalHTTP: true).resolvedEndpoint()
        }
    }

    @Test func wrongFullEndpointRequiresChangingProtocol() {
        #expect(throws: CopilotError.self) {
            try ProviderConfiguration(apiProtocol: .openAIResponses, baseURL: "https://example.com/v1/chat/completions").resolvedEndpoint()
        }
    }

    @Test(arguments: APIProtocol.allCases)
    func includesFullConversationAndResolvedPrompt(apiProtocol: APIProtocol) throws {
        let config = ProviderConfiguration(apiProtocol: apiProtocol, translationPrompt: "Translate into {targetLanguage}", targetLanguage: "French")
        let messages = [ChatMessage(role: .user, content: "Hello"), ChatMessage(role: .assistant, content: "Bonjour"), ChatMessage(role: .user, content: "Why?")]
        let request = try URLSessionLanguageModelClient.makeRequest(configuration: config, apiKey: "fixture-key", messages: messages)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(request.httpMethod == "POST")
        #expect(body["model"] as? String == config.model)
        switch apiProtocol {
        case .openAIChatCompletions:
            let turns = try #require(body["messages"] as? [[String: String]])
            #expect(turns.map { $0["role"]! } == ["system", "user", "assistant", "user"])
            #expect(turns.first?["content"] == "Translate into French")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        case .openAIResponses:
            #expect(body["instructions"] as? String == "Translate into French")
            #expect(body["store"] as? Bool == false)
            let turns = try #require(body["input"] as? [[String: String]])
            #expect(turns.map { $0["role"]! } == ["user", "assistant", "user"])
        case .anthropicMessages:
            #expect(body["system"] as? String == "Translate into French")
            #expect(body["max_tokens"] as? Int == 4096)
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-key")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Test(arguments: [
        (APIProtocol.openAIChatCompletions, #"{"choices":[{"message":{"content":"Bonjour"}}]}"#),
        (.openAIResponses, #"{"output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Bonjour"}]}]}"#),
        (.anthropicMessages, #"{"content":[{"type":"thinking","thinking":"hidden"},{"type":"text","text":"Bonjour"}]}"#)
    ])
    func decodesVisibleTextOnly(values: (APIProtocol, String)) throws {
        #expect(try URLSessionLanguageModelClient.decodeResponse(Data(values.1.utf8), apiProtocol: values.0) == "Bonjour")
    }

    @Test func rejectsMalformedAndEmptyResponses() {
        #expect(throws: CopilotError.invalidResponse) {
            try URLSessionLanguageModelClient.decodeResponse(Data("no JSON".utf8), apiProtocol: .openAIResponses)
        }
        #expect(throws: CopilotError.emptyResponse) {
            try URLSessionLanguageModelClient.decodeResponse(Data(#"{"content":[{"type":"text","text":" "}]}"#.utf8), apiProtocol: .anthropicMessages)
        }
    }

    @Test func rejectsHeaderInjection() {
        #expect(throws: CopilotError.self) {
            try URLSessionLanguageModelClient.makeRequest(configuration: .default, apiKey: "secret\r\nOther: header", messages: [])
        }
    }

    @Test func httpErrorsNeverEchoServerBodyOrCredential() async {
        let transport = FixtureTransport(result: HTTPResult(data: Data("secret-key customer source text".utf8), statusCode: 401))
        let client = URLSessionLanguageModelClient(transport: transport)
        await #expect(throws: CopilotError.httpStatus(401)) {
            try await client.complete(configuration: .default, apiKey: "secret-key", messages: [])
        }
        #expect(CopilotError.httpStatus(401).localizedDescription.contains("secret-key") == false)
    }

    @Test func redirectsRemainAnExplicitError() async {
        let transport = FixtureTransport(result: HTTPResult(data: Data(), statusCode: 307))
        await #expect(throws: CopilotError.httpStatus(307)) {
            try await URLSessionLanguageModelClient(transport: transport).complete(configuration: .default, apiKey: "fixture", messages: [])
        }
    }
}

private struct FixtureTransport: HTTPTransport {
    let result: HTTPResult
    func send(_ request: URLRequest) async throws -> HTTPResult { result }
}
