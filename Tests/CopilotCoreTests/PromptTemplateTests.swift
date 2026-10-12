import Foundation
import Testing
@testable import CopilotCore

@Suite("Translation prompt variables")
struct PromptTemplateTests {
    @Test func preservesExistingTargetLanguageTemplates() {
        let configuration = ProviderConfiguration(targetLanguage: "French")
        #expect(
            configuration.resolvedPrompt
                == ProviderConfiguration.defaultPrompt
                .replacingOccurrences(of: "{targetLanguage}", with: "French"))
    }

    @Test func substitutionsAreNotRecursiveAndRespectLiteralBraces() {
        let template = #"{targetLanguage}|{model}|{{targetLanguage}}|{unknown}|{"answer":true}|{model}"#
        let configuration = ProviderConfiguration(
            model: "fixture-model", translationPrompt: template,
            targetLanguage: "{model}")
        #expect(
            configuration.resolvedPrompt
                == #"{model}|fixture-model|{targetLanguage}|{unknown}|{"answer":true}|fixture-model"#)
    }

    @Test func countsOriginalCharactersAndFollowUpContext() {
        let configuration = ProviderConfiguration(
            translationPrompt:
                "{sourceLength}/{messageCount}/{followUpCount}/{requestType}/{locale}/{appName}")
        let messages = [
            ChatMessage(role: .user, content: "你好👩‍💻"),
            ChatMessage(role: .assistant, content: "Hello"),
            ChatMessage(role: .user, content: "Explain this translation."),
        ]
        let context = PromptContext(messages: messages, locale: Locale(identifier: "zh_CN"))
        #expect(configuration.resolvedPrompt(context: context) == "3/3/1/followUp/zh_CN/Apple Copilot")
        #expect(
            configuration.resolvedPrompt(
                context: PromptContext(
                    messages: Array(messages.prefix(1)),
                    locale: Locale(identifier: "zh_CN"))) == "3/1/0/translation/zh_CN/Apple Copilot")
    }

    @Test(arguments: [
        ("Asia/Shanghai", "1970-01-01/08:00:00"),
        ("America/Los_Angeles", "1969-12-31/16:00:00"),
    ])
    func dateAndTimeUseTheSameExplicitTimeZone(value: (String, String)) throws {
        let timeZone = try #require(TimeZone(identifier: value.0))
        let context = PromptContext(
            date: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "ar"), timeZone: timeZone)
        let configuration = ProviderConfiguration(translationPrompt: "{currentDate}/{currentTime}/{timeZone}")
        #expect(configuration.resolvedPrompt(context: context) == value.1 + "/" + value.0)
    }

    @Test func ambiguousSourceLanguageDoesNotClaimACertainDetection() {
        let configuration = ProviderConfiguration(translationPrompt: "{sourceLanguageCode}/{sourceLanguage}")
        #expect(
            configuration.resolvedPrompt(
                context: PromptContext(messages: [
                    ChatMessage(role: .user, content: "chat")
                ])) == "und/Unknown")
        #if canImport(NaturalLanguage)
        #expect(
            configuration.resolvedPrompt(
                context: PromptContext(messages: [
                    ChatMessage(role: .user, content: "Good design makes complex things simple.")
                ])) == "en/English")
        #endif
    }

    @Test(arguments: APIProtocol.allCases)
    func requestAdaptersRenderContextButKeepSourceInUserMessages(apiProtocol: APIProtocol) throws {
        let source = "Source text containing {model} must stay exactly as written."
        let messages = [
            ChatMessage(role: .user, content: source),
            ChatMessage(role: .assistant, content: "Translation"),
            ChatMessage(role: .user, content: "Please explain."),
        ]
        let configuration = ProviderConfiguration(
            apiProtocol: apiProtocol, model: "fixture-model",
            translationPrompt: "{model}|{apiProtocol}|{followUpCount}|{messageCount}|{requestType}")
        let request = try URLSessionLanguageModelClient.makeRequest(
            configuration: configuration,
            apiKey: "fixture-key", messages: messages)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected = "fixture-model|" + apiProtocol.displayName + "|1|3|followUp"
        switch apiProtocol {
        case .openAIChatCompletions:
            let turns = try #require(body["messages"] as? [[String: String]])
            #expect(turns.first?["content"] == expected)
            #expect(turns[1]["content"] == source)
        case .openAIResponses:
            #expect(body["instructions"] as? String == expected)
            let turns = try #require(body["input"] as? [[String: String]])
            #expect(turns.first?["content"] == source)
        case .anthropicMessages:
            #expect(body["system"] as? String == expected)
            let turns = try #require(body["messages"] as? [[String: String]])
            #expect(turns.first?["content"] == source)
        }
    }
}
