import CopilotCore
import SwiftUI

struct HistoryDaySection: Identifiable {
    let day: Date
    let conversations: [Conversation]

    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        if calendar.component(.year, from: day) == calendar.component(.year, from: Date()) {
            return day.formatted(.dateTime.month().day())
        }
        return day.formatted(.dateTime.year().month().day())
    }
}

struct HistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let conversation: Conversation
    let isSelected: Bool
    var isCompact = false

    private var secondaryTextStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }

    private var followUpCount: Int {
        max(0, conversation.messages.filter { $0.role == .user }.count - 1)
    }

    private var translationSummary: String {
        let flattened = (conversation.translation ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(flattened.prefix(160))
    }

    @ViewBuilder var body: some View {
        if isCompact {
            Text(conversation.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.vertical, 6)
        } else {
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conversation.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if !translationSummary.isEmpty {
                Text(translationSummary)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextStyle)
                    .opacity(isSelected ? 0.9 : 1)
                    .lineLimit(2)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading) {
                    languageAndFollowUps
                    timestamp
                }
            } else {
                HStack {
                    languageAndFollowUps
                    Spacer(minLength: 8)
                    timestamp
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var languageAndFollowUps: some View {
        HStack {
            Text(conversation.configuration.targetLanguage)
                .lineLimit(1)
            if followUpCount > 0 {
                Text("\(followUpCount) 次追问")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(secondaryTextStyle)
        .opacity(isSelected ? 0.85 : 1)
    }

    private var timestamp: some View {
        Text(conversation.updatedAt, format: .dateTime.hour().minute())
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(secondaryTextStyle)
            .opacity(isSelected ? 0.85 : 1)
            .accessibilityLabel(
                Text("更新于 \(conversation.updatedAt.formatted(.dateTime.month().day().hour().minute()))"))
    }
}

struct HistoryListStatus: View {
    let query: String
    let isLoading: Bool
    let error: String?
    let reload: () -> Void

    var body: some View {
        if isLoading {
            ProgressView("正在读取记录…")
        } else if let error {
            ContentUnavailableView {
                Label("无法读取历史", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("重新加载", action: reload)
            }
        } else {
            ContentUnavailableView(
                query.isEmpty ? "还没有翻译记录" : "没有匹配的记录",
                systemImage: query.isEmpty ? "clock" : "magnifyingglass",
                description: Text(query.isEmpty ? "完成一次翻译后，译文和追问会保存在这里。" : "试试其他关键词。"))
        }
    }
}
