import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct PromptContext: Sendable {
    public let messages: [ChatMessage]
    public let date: Date
    public let locale: Locale
    public let timeZone: TimeZone

    public init(
        messages: [ChatMessage] = [], date: Date = Date(),
        locale: Locale = .current, timeZone: TimeZone = .current
    ) {
        self.messages = messages
        self.date = date
        self.locale = locale
        self.timeZone = timeZone
    }

    var sourceText: String { messages.first(where: { $0.role == .user })?.content ?? "" }
    var followUpCount: Int { max(0, messages.filter { $0.role == .user }.count - 1) }

    var sourceLanguageCode: String {
        // Short and ambiguous text should not look like a reliable detection.
        guard sourceText.count >= 20 else { return "und" }
        #if canImport(NaturalLanguage)
        return NLLanguageRecognizer.dominantLanguage(for: sourceText)?.rawValue ?? "und"
        #else
        return "und"
        #endif
    }

    var sourceLanguageName: String {
        let code = sourceLanguageCode
        guard code != "und" else { return "Unknown" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "Unknown"
    }

    func formattedDate(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

public enum PromptVariable: String, CaseIterable, Identifiable, Sendable {
    case targetLanguage, sourceLanguage, sourceLanguageCode, sourceLength
    case model, apiProtocol, currentDate, currentTime, timeZone, locale
    case messageCount, followUpCount, requestType, appName

    public var id: String { rawValue }
    public var placeholder: String { "{" + rawValue + "}" }

    public var title: String {
        switch self {
        case .targetLanguage: "目标语言"
        case .sourceLanguage: "原文主语言（英文名称，自动识别）"
        case .sourceLanguageCode: "原文语言代码（短文本或无法识别时为 und）"
        case .sourceLength: "原文字符数"
        case .model: "模型名称"
        case .apiProtocol: "API 协议名称"
        case .currentDate: "请求日期（yyyy-MM-dd）"
        case .currentTime: "请求时间（HH:mm:ss）"
        case .timeZone: "设备时区"
        case .locale: "设备地区标识"
        case .messageCount: "当前上下文消息数（不含系统提示词）"
        case .followUpCount: "当前追问轮次（首次翻译为 0）"
        case .requestType: "请求类型（translation / followUp）"
        case .appName: "应用名称"
        }
    }

    func value(configuration: ProviderConfiguration, context: PromptContext) -> String {
        switch self {
        case .targetLanguage: configuration.targetLanguage
        case .sourceLanguage: context.sourceLanguageName
        case .sourceLanguageCode: context.sourceLanguageCode
        case .sourceLength: String(context.sourceText.count)
        case .model: configuration.model
        case .apiProtocol: configuration.apiProtocol.displayName
        case .currentDate: context.formattedDate("yyyy-MM-dd")
        case .currentTime: context.formattedDate("HH:mm:ss")
        case .timeZone: context.timeZone.identifier
        case .locale: context.locale.identifier
        case .messageCount: String(context.messages.count)
        case .followUpCount: String(context.followUpCount)
        case .requestType: context.followUpCount == 0 ? "translation" : "followUp"
        case .appName: "Apple Copilot"
        }
    }
}

enum PromptTemplate {
    static func render(_ template: String, configuration: ProviderConfiguration, context: PromptContext) -> String {
        // Match only named placeholders, leaving JSON and unrelated braces intact.
        let pattern = #"\{\{([A-Za-z][A-Za-z0-9_]*)\}\}|\{([A-Za-z][A-Za-z0-9_]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }
        let source = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: source.length))
        var result = ""
        var offset = 0
        var values: [PromptVariable: String] = [:]
        for match in matches {
            result += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            if match.range(at: 1).location != NSNotFound {
                result += "{" + source.substring(with: match.range(at: 1)) + "}"
            } else if let variable = PromptVariable(rawValue: source.substring(with: match.range(at: 2))) {
                let value = values[variable] ?? variable.value(configuration: configuration, context: context)
                values[variable] = value
                result += value
            } else {
                result += source.substring(with: match.range)
            }
            offset = NSMaxRange(match.range)
        }
        result += source.substring(from: offset)
        return result
    }
}
