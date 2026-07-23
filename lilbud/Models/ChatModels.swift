import Foundation

enum ModelTier: String, CaseIterable, Codable, Identifiable {
    case everyday, workhorse
    var id: String { rawValue }
    var title: String { self == .everyday ? "Everyday" : "Workhorse" }
    var modelName: String { self == .everyday ? "Qwen 3.5 4B" : "Qwen 3.5 9B" }
    var contextLimit: Int { self == .everyday ? 8_192 : 16_384 }
}

enum MessageRole: String, Codable { case user, assistant, tool }

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: MessageRole
    var content: String
    let createdAt: Date
    var estimatedTokens: Int
    init(id: UUID = UUID(), role: MessageRole, content: String, createdAt: Date = .now, estimatedTokens: Int? = nil) {
        self.id = id; self.role = role; self.content = content; self.createdAt = createdAt
        self.estimatedTokens = estimatedTokens ?? TokenEstimator.estimate(content)
    }
}

struct ContextSummary: Codable, Hashable {
    let content: String
    let createdAt: Date
    let compactedMessageCount: Int
    var estimatedTokens: Int { TokenEstimator.estimate(content) }
}

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var tier: ModelTier
    var messages: [ChatMessage]
    var summary: ContextSummary?
    var createdAt: Date
    var updatedAt: Date
    init(id: UUID = UUID(), title: String = "New conversation", tier: ModelTier = .everyday, messages: [ChatMessage] = [], summary: ContextSummary? = nil, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.title = title; self.tier = tier; self.messages = messages; self.summary = summary; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
    var activeContextTokens: Int {
        (summary?.estimatedTokens ?? 0) + messages.reduce(0) { $0 + $1.estimatedTokens }
    }
    var contextFraction: Double { min(Double(activeContextTokens) / Double(tier.contextLimit), 1) }
}

enum TokenEstimator { static func estimate(_ text: String) -> Int { max(1, Int((Double(text.utf8.count) / 3.6).rounded(.up))) } }
