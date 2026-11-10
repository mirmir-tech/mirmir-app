import AppKit
import MirmirKit
import SwiftUI
import UniformTypeIdentifiers

struct ThreadView: View {
    @Environment(AppModel.self) private var model
    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(conversation.messages) { message in
                            MessageView(message: message).id(message.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: conversation.messages.last) {
                    if let last = conversation.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Composer(conversation: conversation)
        }
    }
}

struct MessageView: View {
    let message: ChatMessage

    var body: some View {
        switch message.body {
        case .user(let text, let hasImage):
            HStack {
                Spacer(minLength: 120)
                VStack(alignment: .trailing, spacing: 4) {
                    if hasImage { Label("Image attached", systemImage: "photo").font(.system(size: 11)).opacity(0.85) }
                    Text(text).textSelection(.enabled)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .foregroundStyle(Palette.onSignal)
                .background(Palette.signal, in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16))
            }
        case .assistant(let text, let reasoning, let seconds, let state):
            AssistantMessage(text: text, reasoning: reasoning, thinkingSeconds: seconds, state: state)
        }
    }
}

struct AssistantMessage: View {
    let text: String
    let reasoning: String
    let thinkingSeconds: Double?
    let state: ReplyState

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Mark(lineWidth: 1.6).foregroundStyle(Palette.signal).padding(5)
                .frame(width: 24, height: 24)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 8) {
                if !reasoning.isEmpty {
                    DisclosureGroup(thinkingLabel) {
                        Text(reasoning).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !answer.isEmpty {
                    Text(LocalizedStringKey(answer)).textSelection(.enabled).lineSpacing(3)
                }
                footer
            }
        }
    }

    private var thinkingLabel: String {
        if let thinkingSeconds { return String(format: "Thought for %.1f s", thinkingSeconds) }
        return "Thinking…"
    }

    @ViewBuilder private var footer: some View {
        switch state {
        case .streaming:
            HStack(spacing: 8) {
                StatusDot(color: Palette.signal, size: 6)
                Text("streaming").font(.mono(11)).foregroundStyle(Palette.signal)
            }
        case .completed(let stats):
            HStack(spacing: 12) {
                Text("\(Format.grouped(stats.completionTokens)) tokens")
                Text("\(Format.rate(stats.decodeTokensPerSecond)) tok/s")
                Text("TTFT \(Format.seconds(fromMilliseconds: stats.ttftMs)) s")
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(.link)
            }
            .font(.mono(11)).foregroundStyle(.secondary)
        case .stopped:
            Text("Stopped").font(.system(size: 11)).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(Palette.danger)
        }
    }
}

struct Composer: View {
    @Environment(AppModel.self) private var model
    let conversation: Conversation
    @State private var draft = ""
    @State private var image: Data?

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...10)
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 4, trailing: 14))
                .onSubmit(send)
            HStack(spacing: 6) {
                Button(action: attach) { Image(systemName: image == nil ? "paperclip" : "photo.fill") }
                    .buttonStyle(.borderless)
                    .disabled(!(model.model(selector: conversation.model)?.imageInput ?? false))
                    .help("Attach an image for vision models")
                Spacer()
                if let tokens = conversation.contextTokens {
                    Text("\(Format.grouped(tokens)) tokens").font(.mono(11)).foregroundStyle(.secondary)
                }
                if model.chat.isGenerating {
                    Button { model.chat.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(.borderedProminent).clipShape(Circle())
                        .accessibilityLabel("Stop generating")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up") }
                        .buttonStyle(.borderedProminent).clipShape(Circle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityLabel("Send")
                }
            }
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 8, trailing: 8))
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border, lineWidth: 0.5))
        .frame(maxWidth: 720)
        .padding(EdgeInsets(top: 12, leading: 24, bottom: 18, trailing: 24))
    }

    private var placeholder: String {
        if !conversation.model.isEmpty { return "Message \(conversation.subtitle)" }
        return model.primaryModel.map { "Message \($0.displayName)" } ?? "Load a model to start chatting"
    }

    private func send() {
        guard !model.chat.isGenerating else { return }
        model.chat.send(draft, image: image)
        draft = ""
        image = nil
    }

    private func attach() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { image = try? Data(contentsOf: url) }
    }
}
