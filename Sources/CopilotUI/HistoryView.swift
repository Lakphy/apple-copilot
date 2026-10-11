import SwiftUI
import CopilotCore
import Foundation
#if os(iOS)
import UIKit
#endif

public struct HistoryView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var selection: UUID?
    @State private var detail: ConversationStore?
    @State private var deleting: Conversation?

    private var sections: [HistoryDaySection] {
        let calendar = Calendar.current
        return Dictionary(grouping: environment.session.history) {
            calendar.startOfDay(for: $0.updatedAt)
        }
        .map { HistoryDaySection(day: $0.key, conversations: $0.value) }
        .sorted { $0.day > $1.day }
    }

    public init() {}

    public var body: some View {
        NavigationSplitView {
            historyList
        } detail: {
            historyDetail
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: query) { await environment.session.loadHistory(query: query) }
        .onChange(of: selection) { _, id in selectConversation(id) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reloadHistory() }
        }
        .onChange(of: detail?.conversation) { previous, current in
            if let previous, let current,
               previous.id == current.id, previous.updatedAt != current.updatedAt {
                reloadHistory()
            }
        }
        .confirmationDialog("删除这段会话？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { conversation in
                Button("删除会话", role: .destructive) { deleteConversation(conversation) }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { _ in Text("此设备上的译文与追问将被永久删除。") }
    }

    private var historyList: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            HistoryRow(conversation: conversation, isSelected: selection == conversation.id)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) { deleting = conversation }
                        }
                        .contextMenu {
                            Button("删除会话", systemImage: "trash", role: .destructive) {
                                deleting = conversation
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if environment.session.history.isEmpty {
                HistoryListStatus(
                    query: query,
                    isLoading: environment.session.isLoadingHistory,
                    error: environment.session.historyErrorMessage,
                    reload: reloadHistory)
            }
        }
        .safeAreaInset(edge: .top) {
            if !environment.session.history.isEmpty, let error = environment.session.historyErrorMessage {
                InlineNotice(title: "历史记录操作失败", message: error)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.background)
            }
        }
        .navigationTitle("历史")
        .searchable(text: $query, prompt: "搜索原文、译文或追问")
        .refreshable { await environment.session.loadHistory(query: query) }
        .navigationSplitViewColumnWidth(min: 250, ideal: 320, max: 400)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var historyDetail: some View {
        Group {
            if let detail {
                ConversationDetail(store: detail)
            } else {
                ContentUnavailableView("选择一段翻译", systemImage: "character.bubble",
                                       description: Text("阅读译文，或继续之前的对话。"))
            }
        }
        .navigationTitle(detail == nil ? "历史" : "翻译详情")
        .toolbar {
            if let conversation = detail?.conversation {
                ToolbarItem(placement: .primaryAction) {
                    Button("删除会话", systemImage: "trash", role: .destructive) {
                        deleting = conversation
                    }
                    .help("删除这段翻译及追问")
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(UIDevice.current.userInterfaceIdiom == .phone && detail != nil ? .hidden : .automatic,
                 for: .tabBar)
        #endif
    }

    private func selectConversation(_ id: UUID?) {
        detail?.cancel()
        guard let conversation = environment.session.history.first(where: { $0.id == id }) else {
            detail = nil
            return
        }
        let session = environment.makeConversationStore()
        session.select(conversation)
        detail = session
    }

    private func reloadHistory() {
        Task { await environment.session.loadHistory(query: query) }
    }

    private func deleteConversation(_ conversation: Conversation) {
        if selection == conversation.id {
            detail?.cancel()
            selection = nil
            detail = nil
        }
        Task { await environment.session.delete(conversation.id) }
        deleting = nil
    }
}

private struct HistoryDaySection: Identifiable {
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

private struct HistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let conversation: Conversation
    let isSelected: Bool

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

    var body: some View {
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
            .accessibilityLabel(Text("更新于 \(conversation.updatedAt.formatted(.dateTime.month().day().hour().minute()))"))
    }
}

private struct HistoryListStatus: View {
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
            ContentUnavailableView(query.isEmpty ? "还没有翻译记录" : "没有匹配的记录",
                                   systemImage: query.isEmpty ? "clock" : "magnifyingglass",
                                   description: Text(query.isEmpty ? "完成一次翻译后，译文和追问会保存在这里。" : "试试其他关键词。"))
        }
    }
}
