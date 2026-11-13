import MirmirKit
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ConversationList()
                .frame(width: 270)
                .background(Palette.list)
            Divider()
            Group {
                if let conversation = model.chat.selected {
                    ThreadView(conversation: conversation)
                } else {
                    EmptyState(title: "No conversation", message: "Start a new chat with ⌘N.", symbol: "bubble.left.and.bubble.right")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface)
        }
        .navigationTitle(model.chat.selected?.title ?? "Chat")
        .navigationSubtitle(model.currentInstance.name)
        .toolbar {
            if let conversation = model.chat.selected {
                ToolbarItem { ChatModelMenu(conversation: conversation) }
                ToolbarItem { GenerationOptionsMenu() }
            }
        }
    }
}

struct ConversationList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var chat = model.chat
        VStack(spacing: 0) {
            HStack {
                Text("Chats").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { model.chat.newConversation() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("New chat")
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            Divider()
            if let issue = chat.loadIssue {
                ChatLoadIssueBanner(message: issue.message, action: issue.isPersistent ? nil : ("Dismiss", { model.chat.dismissLoadIssue() }))
                Divider()
            }
            if let failure = chat.saveFailure {
                ChatLoadIssueBanner(message: failure.message, action: ("Retry", { model.chat.retrySaving() }))
                Divider()
            }
            List(selection: $chat.selectedID) {
                ForEach(chat.visibleConversations) { conversation in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(conversation.title).fontWeight(.medium).lineLimit(1)
                            Spacer()
                            Text(Format.relative(conversation.updatedAt)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text(conversation.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .tag(conversation.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) { model.chat.delete(conversation.id) }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

/// Saved chats that did not load as written: where the original went, or
/// that this session is not saved.
/// A warning above the chat list about saved chats, with one action.
struct ChatLoadIssueBanner: View {
    let message: String
    let action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(message).foregroundStyle(Palette.ink)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
            }
                .font(.system(size: 11))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.run).controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The model a conversation talks to; only loaded models can answer.
struct ChatModelMenu: View {
    @Environment(AppModel.self) private var model
    let conversation: Conversation

    var body: some View {
        Menu {
            ForEach(model.loadedModels) { local in
                Button(local.displayName) { model.chat.setModel(model.servingSelector(for: local), for: conversation.id) }
            }
            if model.loadedModels.isEmpty { Text("Load a model in Models first") }
        } label: {
            Label(label, systemImage: "shippingbox").labelStyle(.titleAndIcon)
        }
    }

    private var label: String {
        if conversation.model.isEmpty { return "Choose Model" }
        return model.model(selector: conversation.model)?.displayName ?? conversation.subtitle
    }
}

/// Temperature and maximum tokens for the next request. Thinking and JSON
/// mode need `GenerateRequest` fields that the protocol does not have yet.
struct GenerationOptionsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Picker("Temperature", selection: temperature) {
                Text("Model default").tag(Float?.none)
                ForEach([Float(0), 0.3, 0.7, 1.0, 1.3], id: \.self) { Text(String(format: "%.1f", $0)).tag(Float?.some($0)) }
            }
            Picker("Max tokens", selection: maxTokens) {
                Text("Model default").tag(UInt64?.none)
                ForEach([UInt64(512), 1024, 4096, 16384], id: \.self) { Text(Format.grouped($0)).tag(UInt64?.some($0)) }
            }
        } label: {
            Label("Generation settings", systemImage: "slider.horizontal.3")
        }
    }

    private var temperature: Binding<Float?> {
        Binding { model.chat.temperature } set: { model.chat.temperature = $0 }
    }

    private var maxTokens: Binding<UInt64?> {
        Binding { model.chat.maxTokens } set: { model.chat.maxTokens = $0 }
    }
}

#if DEBUG
#Preview("Chat", traits: .fixedLayout(width: 1070, height: 800)) {
    ChatView().previewModel()
}
#Preview("Chat — streaming", traits: .fixedLayout(width: 1070, height: 800)) {
    ChatView().previewModel(.preview(.generating))
}
#endif
