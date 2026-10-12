import CopilotCore
import SwiftUI

struct SourceText: View {
    let text: String
    @State private var isExpanded = false

    private var needsExpansion: Bool { text.count > 180 || text.filter { $0 == "\n" }.count > 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("原文").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(needsExpansion && !isExpanded ? 4 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            if needsExpansion {
                Button(isExpanded ? "收起原文" : "展开原文", systemImage: isExpanded ? "chevron.up" : "chevron.down") {
                    isExpanded.toggle()
                }
                .font(.subheadline)
                .buttonStyle(.borderless)
                .padding(.vertical, 6)
            }
        }
        .onChange(of: text) { _, _ in isExpanded = false }
    }
}

struct ConversationTranscript: View {
    let conversation: Conversation
    var onSettings: (() -> Void)?
    var replaceTranslation: ((String) -> Void)?
    var pendingUserMessage: ChatMessage?
    var streamingMessage: ChatMessage?
    var isWorking = false

    private var displayedMessages: [ChatMessage] {
        conversation.messages + (pendingUserMessage.map { [$0] } ?? []) + (streamingMessage.map { [$0] } ?? [])
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            SourceText(text: conversation.sourceText)
            Divider()
            ForEach(
                Array(displayedMessages.dropFirst(displayedMessages.first?.role == .user ? 1 : 0).enumerated()),
                id: \.element.id
            ) { index, message in
                if message.role == .user {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("追问").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(message.content).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(CopilotSurface.secondary, in: .rect(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                } else {
                    let isIncomplete = message.id == streamingMessage?.id
                    AssistantMessageView(
                        message: message, isTranslation: index == 0,
                        targetLanguage: conversation.configuration.targetLanguage,
                        onSettings: onSettings, replaceTranslation: isIncomplete ? nil : replaceTranslation,
                        isStreaming: isIncomplete && isWorking, isIncomplete: isIncomplete)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

struct AssistantMessageView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: ChatMessage
    let isTranslation: Bool
    let targetLanguage: String
    var onSettings: (() -> Void)?
    var replaceTranslation: ((String) -> Void)?
    var isStreaming = false
    var isIncomplete = false
    @State private var copied = false
    @State private var copyRevision = 0

    private var copyTitle: String { copied ? "已复制" : (isTranslation ? "复制译文" : "复制回复") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if isTranslation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("译文").font(.headline)
                        Text(targetLanguage).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("回复").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                actions
            }
            RichMarkdownView(markdown: message.content, isStreaming: isStreaming)
            if isIncomplete && !isStreaming {
                Text("未完成的回复").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .task(id: copyRevision) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            copied = false
        }
        .onChange(of: message.content) { _, _ in
            copied = false
            copyRevision += 1
        }
    }

    @ViewBuilder private var actions: some View {
        if isTranslation && (onSettings != nil || replaceTranslation != nil) {
            Menu {
                Button(copyTitle, systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                if let replaceTranslation {
                    Button("替换原文", systemImage: "arrow.triangle.2.circlepath") {
                        replaceTranslation(message.content)
                    }
                }
                if let onSettings { Button("设置", systemImage: "gearshape", action: onSettings) }
            } label: {
                feedbackIcon(restingSymbol: "ellipsis")
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "已复制译文，译文操作" : "译文操作")
            .help(copied ? "已复制" : "译文操作")
        } else {
            Button(action: copy) { feedbackIcon(restingSymbol: "doc.on.doc") }
                .buttonStyle(.plain)
                .accessibilityLabel(copyTitle)
                .help(copyTitle)
        }
    }

    private func feedbackIcon(restingSymbol: String) -> some View {
        Image(systemName: copied ? "checkmark" : restingSymbol)
            .font(.system(size: 17, weight: copied ? .semibold : .regular))
            .foregroundStyle(copied ? Color.green : Color.primary)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: copied)
            .symbolEffectsRemoved(reduceMotion)
            .frame(width: actionSize, height: actionSize)
            .contentShape(.circle)
    }

    private func copy() {
        guard Clipboard.copy(message.content) else { return }
        copied = true
        // Changing the task identity cancels the previous reset, so repeated
        // copies always keep the checkmark visible for a full feedback period.
        copyRevision += 1
    }

    private var actionSize: CGFloat {
        #if os(macOS)
        28
        #else
        44
        #endif
    }
}
