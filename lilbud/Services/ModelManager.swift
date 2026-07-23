import Foundation
import Observation

@MainActor @Observable final class ModelManager {
    private(set) var installedModelIDs = Set<String>()
    private(set) var downloading: ModelTier?
    private(set) var status = ""
    private(set) var error: String?

    init() { Task { await refresh() } }

    func isInstalled(_ tier: ModelTier) -> Bool { installedModelIDs.contains(modelID(for: tier)) }
    func modelID(for tier: ModelTier) -> String { tier == .everyday ? "qwen3.5:4b-mlx" : "qwen3.5:9b-mlx" }
    func download(_ tier: ModelTier) async {
        downloading = tier; error = nil; status = "Preparing local runtime…"
        defer { downloading = nil; status = "" }
        do {
            try await RuntimeManager.shared.installIfNeeded()
            status = "Downloading \(tier.title) model… This may take a while."
            _ = try await runOllama(["pull", modelID(for: tier)])
            status = "Finishing model setup…"
            await refresh()
        }
        catch let caught { self.error = "Couldn’t download \(tier.title): \(caught.localizedDescription)"; status = "" }
    }
    func refresh() async {
        guard let output = try? await runOllama(["list"]) else { return }
        installedModelIDs = Set(output.split(separator: "\n").dropFirst().compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) })
    }
    private func runOllama(_ arguments: [String]) async throws -> String {
        try await RuntimeManager.shared.installIfNeeded()
        guard let executable = RuntimeManager.shared.ollamaExecutable() else { throw RuntimeError.commandFailed("Ollama is not installed.") }
        try OllamaServer.shared.ensureRunning(executable: executable)
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuntimeError.commandFailed(String(decoding: data, as: UTF8.self)) }
        return String(decoding: data, as: UTF8.self)
    }
}

enum RuntimeError: LocalizedError { case commandFailed(String); var errorDescription: String? { if case let .commandFailed(message) = self { return message } ; return nil } }
