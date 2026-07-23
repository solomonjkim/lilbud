import Foundation
import Observation

@MainActor @Observable final class ChatStore {
    private let storageURL: URL
    private let agent: any AgentBridge = PiAgentBridge()
    var conversations: [Conversation] = [] { didSet { save() } }
    var selectedConversationID: UUID? { didSet { save() } }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Lilbud", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        storageURL = support.appending(path: "conversations.json")
        load()
        if conversations.isEmpty { createConversation() }
    }
    var selectedConversation: Conversation? { conversations.first { $0.id == selectedConversationID } ?? conversations.first }
    func createConversation() { let item = Conversation(); conversations.insert(item, at: 0); selectedConversationID = item.id }
    func delete(_ id: UUID) { conversations.removeAll { $0.id == id }; if selectedConversationID == id { selectedConversationID = conversations.first?.id }; if conversations.isEmpty { createConversation() } }
    func updateTier(_ tier: ModelTier, for id: UUID) { mutate(id) { $0.tier = tier } }
    func send(_ text: String, in id: UUID) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        mutate(id) { chat in chat.messages.append(ChatMessage(role: .user, content: text)); if chat.title == "New conversation" { chat.title = String(text.prefix(48)) }; chat.updatedAt = .now }
        guard let snapshot = conversations.first(where: { $0.id == id }) else { return }
        Task { [weak self] in
            do {
                let reply = try await self?.agent.send(messages: snapshot.messages, summary: snapshot.summary, tier: snapshot.tier)
                guard let reply else { return }
                self?.mutate(id) { $0.messages.append(ChatMessage(role: .assistant, content: reply)); $0.updatedAt = .now }
            } catch {
                self?.mutate(id) { $0.messages.append(ChatMessage(role: .assistant, content: "I couldn’t start the local assistant. \(error.localizedDescription)")); $0.updatedAt = .now }
            }
        }
    }
    func compact(_ id: UUID, style: CompactionStyle) {
        guard let snapshot = conversations.first(where: { $0.id == id }) else { return }
        Task { [weak self] in
            do {
                let summary = try await self?.agent.compact(messages: snapshot.messages, previousSummary: snapshot.summary, style: style, tier: snapshot.tier)
                guard let summary else { return }
                self?.mutate(id) { chat in chat.summary = ContextSummary(content: summary, createdAt: .now, compactedMessageCount: chat.messages.count); chat.messages.removeAll(); chat.updatedAt = .now }
            } catch { }
        }
    }
    private func mutate(_ id: UUID, _ body: (inout Conversation) -> Void) { guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }; body(&conversations[index]); conversations.sort { $0.updatedAt > $1.updatedAt } }
    private struct SavedState: Codable { var conversations: [Conversation]; var selectedConversationID: UUID? }
    private func load() { guard let data = try? Data(contentsOf: storageURL), let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }; conversations = state.conversations; selectedConversationID = state.selectedConversationID }
    private func save() { guard let data = try? JSONEncoder().encode(SavedState(conversations: conversations, selectedConversationID: selectedConversationID)) else { return }; try? data.write(to: storageURL, options: .atomic) }
}

enum CompactionStyle: String, CaseIterable, Identifiable { case concise, detailed; var id: String { rawValue }; var title: String { self == .concise ? "Keep key decisions and preferences" : "Keep a detailed working summary" } }
