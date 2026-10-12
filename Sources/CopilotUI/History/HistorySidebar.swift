import CopilotCore
import SwiftUI

enum HistorySidebarSelection: Hashable {
    case section(AppSection)
    case conversation(UUID)
}

struct HistorySidebar: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Binding var query: String
    @Binding var selection: HistorySidebarSelection?
    let sections: [HistoryDaySection]
    let selectedConversationID: UUID?
    let startNewTranslation: () -> Void
    let reloadHistory: () -> Void
    let onDelete: (Conversation) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GlassHistorySearch(text: $query)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            List(selection: $selection) {
                Button(action: startNewTranslation) {
                    Label(AppSection.translate.title, systemImage: AppSection.translate.symbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .tag(HistorySidebarSelection.section(.translate))
                Text("历史")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .selectionDisabled()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(.isHeader)
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.conversations) { conversation in
                            HistoryRow(
                                conversation: conversation,
                                isSelected: environment.section == .history
                                    && selectedConversationID == conversation.id,
                                isCompact: true
                            )
                            .padding(.leading, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tag(HistorySidebarSelection.conversation(conversation.id))
                            .contextMenu {
                                Button("删除会话", systemImage: "trash", role: .destructive) {
                                    onDelete(conversation)
                                }
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) { onDelete(conversation) }
                            }
                        }
                    }
                }
                if environment.session.history.isEmpty {
                    Section {
                        if environment.session.isLoadingHistory {
                            ProgressView("正在读取记录…")
                        } else {
                            Text(query.isEmpty ? "还没有翻译记录" : "没有匹配的记录")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = environment.session.historyErrorMessage {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                        Button("重新加载", action: reloadHistory)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .refreshable { await environment.session.loadHistory(query: query) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if os(iOS)
            List(selection: $selection) {
                Label("设置", systemImage: AppSection.settings.symbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tag(HistorySidebarSelection.section(.settings))
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 80)
            #else
            Button {
                environment.section = .settings
            } label: {
                Label("设置", systemImage: AppSection.settings.symbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 12)
                    .contentShape(.rect)
                    .foregroundStyle(environment.section == .settings ? Color.white : Color.primary)
                    .background(
                        environment.section == .settings ? Color.accentColor : Color.clear,
                        in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(environment.section == .settings ? .isSelected : [])
            .padding(12)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(.background.secondary)
        #endif
    }

}
