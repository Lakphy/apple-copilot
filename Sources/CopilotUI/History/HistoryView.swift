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
    private var isWorkspace = false

    private var sections: [HistoryDaySection] {
        let calendar = Calendar.current
        return Dictionary(grouping: environment.session.history) {
            calendar.startOfDay(for: $0.updatedAt)
        }
        .map { HistoryDaySection(day: $0.key, conversations: $0.value) }
        .sorted { $0.day > $1.day }
    }

    public init() {}

    init(isWorkspace: Bool) {
        self.isWorkspace = isWorkspace
    }

    public var body: some View {
        navigation
            .task(id: query) {
                await environment.load()
                guard !Task.isCancelled else { return }
                await environment.session.loadHistory(query: query)
            }
            .onChange(of: selection) { _, id in selectConversation(id) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reloadHistory() }
            }
            .onChange(of: detail?.conversation) { previous, current in
                if let previous, let current,
                    previous.id == current.id, previous.updatedAt != current.updatedAt
                {
                    reloadHistory()
                }
            }
            .confirmationDialog(
                "删除这段会话？",
                isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting
            ) { conversation in
                Button("删除会话", role: .destructive) { deleteConversation(conversation) }
                Button("取消", role: .cancel) { deleting = nil }
            } message: { _ in
                Text("此设备上的译文与追问将被永久删除。")
            }
    }

    @ViewBuilder private var navigation: some View {
        if isWorkspace {
            #if os(iOS)
            NavigationSplitView(columnVisibility: .constant(.all)) {
                workspaceSidebar
                    .navigationTitle("Apple Copilot")
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 320)
                    .toolbar(removing: .sidebarToggle)
                    .background(FixedSidebarPolicy().frame(width: 0, height: 0))
            } detail: {
                NavigationStack { workspaceDetail }
            }
            .navigationSplitViewStyle(.balanced)
            #else
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    workspaceSidebar
                        .frame(width: min(320, max(240, geometry.size.width * 0.31)))
                    NavigationStack { workspaceDetail }
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            #endif
        } else {
            standaloneNavigation
        }
    }

    @ViewBuilder private var workspaceDetail: some View {
        switch environment.section {
        case .translate: TranslateView()
        case .history: historyDetail
        case .settings: SettingsView()
        }
    }

    private var sidebarSelection: Binding<HistorySidebarSelection?> {
        Binding {
            if environment.section == .history, let selection {
                return .conversation(selection)
            }
            return .section(environment.section)
        } set: { value in
            switch value {
            case .section(.translate): startNewTranslation()
            case .section(let section): environment.section = section
            case .conversation(let id):
                selection = id
                environment.section = .history
            case nil: break
            }
        }
    }

    private var workspaceSidebar: some View {
        HistorySidebar(
            query: $query, selection: sidebarSelection, sections: sections,
            selectedConversationID: selection, startNewTranslation: startNewTranslation,
            reloadHistory: reloadHistory, onDelete: { deleting = $0 })
    }

    private var standaloneNavigation: some View {
        NavigationSplitView {
            historyList
        } detail: {
            historyDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var historyList: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.conversations) { conversation in
                        NavigationLink(value: conversation.id) {
                            HistoryRow(conversation: conversation, isSelected: selection == conversation.id)
                        }
                        .listRowBackground(CopilotSurface.page)
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
        .scrollContentBackground(.hidden)
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
                    .background(CopilotSurface.page)
            }
        }
        .copilotPageBackground()
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
                ContentUnavailableView(
                    "选择一段翻译", systemImage: "character.bubble",
                    description: Text("阅读译文，或继续之前的对话。"))
            }
        }
        .copilotPageBackground()
        .navigationTitle(detail == nil ? "历史" : "翻译详情")
        .toolbar {
            if let conversation = detail?.conversation {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        deleting = conversation
                    } label: {
                        ToolbarActionIcon(symbol: "trash")
                    }
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("删除会话")
                    .help("删除这段翻译及追问")
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(
            UIDevice.current.userInterfaceIdiom == .phone && detail != nil ? .hidden : .automatic,
            for: .tabBar)
        #endif
    }

    private func startNewTranslation() {
        detail?.cancel()
        selection = nil
        detail = nil
        environment.startNewTranslation()
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
