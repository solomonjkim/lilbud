import Foundation

/// App boundary for Pi's RPC mode. Both local tiers receive the same messages
/// and the same restricted tool contract.
protocol AgentBridge {
    func send(messages: [ChatMessage], summary: ContextSummary?, tier: ModelTier) async throws -> String
    func compact(messages: [ChatMessage], previousSummary: ContextSummary?, style: CompactionStyle, tier: ModelTier) async throws -> String
}

@MainActor final class PiAgentBridge: AgentBridge {
    func send(messages: [ChatMessage], summary: ContextSummary?, tier: ModelTier) async throws -> String {
        try await RuntimeManager.shared.installIfNeeded()
        guard let executable = RuntimeManager.shared.piExecutable(), let ollama = RuntimeManager.shared.ollamaExecutable() else { throw RuntimeError.commandFailed("Lilbud's local runtime is not installed.") }
        try OllamaServer.shared.ensureRunning(executable: ollama)
        let runtime = try PiRuntime.prepare()
        let prompt = Self.prompt(messages: messages, summary: summary)
        let output = try runPi(executable: executable, runtime: runtime, tier: tier, prompt: prompt)
        let text = Self.text(from: output)
        guard !text.isEmpty else { throw RuntimeError.commandFailed("Pi completed without a response.") }
        return text
    }
    func compact(messages: [ChatMessage], previousSummary: ContextSummary?, style: CompactionStyle, tier: ModelTier) async throws -> String {
        let instruction = style == .detailed ? "Create a detailed working summary." : "Create a concise summary of key decisions, preferences, facts, and open work."
        return try await send(messages: messages + [ChatMessage(role: .user, content: instruction)], summary: previousSummary, tier: tier)
    }
    private func runPi(executable: URL, runtime: PiRuntime, tier: ModelTier, prompt: String) throws -> String {
        let process = Process(); process.executableURL = executable
        process.arguments = ["--mode", "rpc", "--no-session", "--no-builtin-tools", "--tools", "search_web", "--no-extensions", "--extension", runtime.extensionURL.path, "--provider", "lilbud-local", "--model", tier == .everyday ? "qwen3.5:4b-mlx" : "qwen3.5:9b-mlx", "--api-key", "local"]
        process.environment = ProcessInfo.processInfo.environment.merging(["PI_CODING_AGENT_DIR": runtime.directory.path, "PI_OFFLINE": "1", "PI_SKIP_VERSION_CHECK": "1", "PI_TELEMETRY": "0"]) { _, new in new }
        let input = Pipe(), output = Pipe(), error = Pipe(); process.standardInput = input; process.standardOutput = output; process.standardError = error
        try process.run()
        let command = ["id": UUID().uuidString, "type": "prompt", "message": prompt] as [String: Any]
        input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: command)); input.fileHandleForWriting.write(Data("\n".utf8)); input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuntimeError.commandFailed(String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
        return String(decoding: data, as: UTF8.self)
    }
    private static func prompt(messages: [ChatMessage], summary: ContextSummary?) -> String {
        let history = messages.map { "\($0.role.rawValue.capitalized): \($0.content)" }.joined(separator: "\n\n")
        let prior = summary.map { "Working summary:\n\($0.content)\n\n" } ?? ""
        return "You are Lilbud, a private local assistant. Use search_web only for information that may be current. Cite sources by title and URL when search is used.\n\n\(prior)Conversation:\n\(history)"
    }
    private static func text(from output: String) -> String {
        output.split(separator: "\n").compactMap { line -> String? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], object["type"] as? String == "message_update", let event = object["assistantMessageEvent"] as? [String: Any], event["type"] as? String == "text_delta" else { return nil }
            return event["delta"] as? String
        }.joined()
    }
}

private struct PiRuntime {
    let directory: URL; let extensionURL: URL
    static func prepare() throws -> PiRuntime {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Lilbud/Pi", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let models = "{\"providers\":{\"lilbud-local\":{\"baseUrl\":\"http://localhost:11434/v1\",\"api\":\"openai-completions\",\"apiKey\":\"local\",\"compat\":{\"supportsDeveloperRole\":false,\"supportsReasoningEffort\":false},\"models\":[{\"id\":\"qwen3.5:4b-mlx\",\"name\":\"Everyday\",\"contextWindow\":8192,\"maxTokens\":2048},{\"id\":\"qwen3.5:9b-mlx\",\"name\":\"Workhorse\",\"contextWindow\":16384,\"maxTokens\":4096}]}}}"
        let extensionSource = #"""
        import { Type } from "typebox";
        export default function(pi) {
          pi.registerTool({
            name: "search_web", label: "Search the web", description: "Search current web information.",
            parameters: Type.Object({ query: Type.String(), freshness: Type.Union([Type.Literal("any"), Type.Literal("recent")]), maxResults: Type.Optional(Type.Number()) }),
            async execute(_id, p) {
              const key = process.env.EXA_API_KEY;
              if (!key) throw new Error("EXA_API_KEY is not configured.");
              const response = await fetch("https://api.exa.ai/search", { method: "POST", headers: { "x-api-key": key, "Content-Type": "application/json" }, body: JSON.stringify({ query: p.query, type: "auto", numResults: Math.min(Math.max(p.maxResults ?? 5, 1), 10), contents: { highlights: true, ...(p.freshness === "recent" ? { maxAgeHours: 24 } : {}) } }) });
              if (!response.ok) throw new Error(`Exa search failed: ${response.status}`);
              const data = await response.json();
              const text = data.results.map((item, index) => `[${index + 1}] ${item.title}\n${item.url}\n${(item.highlights ?? []).slice(0, 2).join(" ")}`).join("\n\n");
              return { content: [{ type: "text", text }], details: {} };
            }
          });
        }
        """#
        try models.data(using: .utf8)!.write(to: directory.appending(path: "models.json"), options: .atomic)
        let extensionURL = directory.appending(path: "lilbud-search.ts"); try extensionSource.data(using: .utf8)!.write(to: extensionURL, options: .atomic)
        return PiRuntime(directory: directory, extensionURL: extensionURL)
    }
}

/// The sole externally connected tool granted to either local model tier.
struct SearchWebTool: Codable, Sendable {
    let query: String
    let freshness: Freshness
    let maxResults: Int
    enum Freshness: String, Codable, Sendable { case any, recent }
}
