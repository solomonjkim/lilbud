import Foundation
import Observation

@MainActor @Observable final class ModelManager {
    private(set) var installedModelIDs = Set<String>()
    private(set) var downloading: ModelTier?
    private(set) var error: String?

    init() { Task { await refresh() } }

    func isInstalled(_ tier: ModelTier) -> Bool { installedModelIDs.contains(modelID(for: tier)) }
    func modelID(for tier: ModelTier) -> String { tier == .everyday ? "qwen3.5:4b-mlx" : "qwen3.5:9b-mlx" }
    func download(_ tier: ModelTier) async {
        downloading = tier; error = nil
        defer { downloading = nil }
        do { _ = try await runOllama(["pull", modelID(for: tier)]); await refresh() }
        catch let caught { self.error = "Couldn’t download \(tier.title): \(caught.localizedDescription)" }
    }
    func refresh() async {
        guard let output = try? await runOllama(["list"]) else { return }
        installedModelIDs = Set(output.split(separator: "\n").dropFirst().compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) })
    }
    private func runOllama(_ arguments: [String]) async throws -> String {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env"); process.arguments = ["ollama"] + arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuntimeError.commandFailed(String(decoding: data, as: UTF8.self)) }
        return String(decoding: data, as: UTF8.self)
    }
}

enum RuntimeError: LocalizedError { case commandFailed(String); var errorDescription: String? { if case let .commandFailed(message) = self { return message } ; return nil } }
