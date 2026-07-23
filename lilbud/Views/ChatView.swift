import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var store
    @Environment(ModelManager.self) private var models
    @Environment(RuntimeManager.self) private var runtime
    let conversation: Conversation
    @State private var draft = ""
    @State private var showingCompaction = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) { Text(conversation.title).font(.headline); Text("Local only · History stays on this Mac").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Picker("Model tier", selection: Binding(get: { conversation.tier }, set: { store.updateTier($0, for: conversation.id) })) { ForEach(ModelTier.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 220)
                if models.isInstalled(conversation.tier) { Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                else { Button(models.downloading == conversation.tier ? "Setting up…" : "Download") { Task { await models.download(conversation.tier) } }.disabled(models.downloading != nil) }
            }.padding(.horizontal, 28).padding(.vertical, 16)
            Divider()
            if models.downloading != nil || runtime.isInstalling || models.error != nil || runtime.error != nil {
                SetupStatusCard(
                    status: runtime.isInstalling ? runtime.status : models.status,
                    error: models.error ?? runtime.error
                )
                .padding(.horizontal, 28).padding(.vertical, 12)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let summary = conversation.summary { SummaryCard(summary: summary) }
                        if conversation.messages.isEmpty && conversation.summary == nil { WelcomeView(tier: conversation.tier) }
                        ForEach(conversation.messages) { MessageBubble(message: $0) }
                    }.padding(28)
                }.onChange(of: conversation.messages.count) { _, _ in if let last = conversation.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }
            Divider()
            Composer(draft: $draft, contextFraction: conversation.contextFraction, activeTokens: conversation.activeContextTokens, contextLimit: conversation.tier.contextLimit, modelReady: models.isInstalled(conversation.tier), send: send, compact: { showingCompaction = true })
        }
        .sheet(isPresented: $showingCompaction) { CompactionSheet(conversation: conversation) { store.compact(conversation.id, style: $0) } }
    }
    private func send() { store.send(draft, in: conversation.id); draft = "" }
}

private struct SetupStatusCard: View {
    let status: String
    let error: String?

    var body: some View {
        HStack(spacing: 12) {
            if error == nil { ProgressView().controlSize(.small) }
            Image(systemName: error == nil ? "arrow.down.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(error == nil ? .mint : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(error ?? status).font(.subheadline)
                if error == nil { Text("Lilbud is setting up its private local runtime. You can keep the app open while this completes.").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct WelcomeView: View {
    let tier: ModelTier
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "leaf.fill").font(.system(size: 28)).foregroundStyle(.mint)
            Text("Private by default.").font(.title2.bold())
            Text("You’re using \(tier.modelName). Ask anything, or ask it to search the web when current information matters.").foregroundStyle(.secondary).frame(maxWidth: 420, alignment: .leading)
        }.padding(.top, 64).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack { if message.role == .assistant { bubble; Spacer(minLength: 80) } else { Spacer(minLength: 80); bubble } }.id(message.id)
    }
    private var bubble: some View {
        Text(message.content).textSelection(.enabled).padding(13)
            .background(message.role == .user ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)).frame(maxWidth: 580, alignment: message.role == .user ? .trailing : .leading)
    }
}

private struct SummaryCard: View {
    let summary: ContextSummary
    var body: some View {
        DisclosureGroup("Context compacted · View summary") { Text(summary.content).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 6) }
            .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
