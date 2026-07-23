import CryptoKit
import Foundation
import Observation

/// Installs only artifacts named in Lilbud's signed manifest. Nothing is read
/// from the user's shell PATH, so a distributed app has the same setup flow.
@MainActor @Observable final class RuntimeManager {
    static let shared = RuntimeManager()

    private(set) var isInstalling = false
    private(set) var status = ""
    private(set) var error: String?

    private let fileManager = FileManager.default
    private var root: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Lilbud/Runtime", directoryHint: .isDirectory)
    }

    func piExecutable() -> URL? { executable(named: "pi", below: root.appending(path: "Pi", directoryHint: .isDirectory)) }
    func ollamaExecutable() -> URL? {
        let bundledCLI = root.appending(path: "Ollama/Ollama.app/Contents/Resources/ollama")
        return fileManager.isExecutableFile(atPath: bundledCLI.path) ? bundledCLI : executable(named: "ollama", below: root.appending(path: "Ollama", directoryHint: .isDirectory))
    }
    var isInstalled: Bool { piExecutable() != nil && ollamaExecutable() != nil }

    func installIfNeeded() async throws {
        // This also repairs a runtime downloaded by an earlier Lilbud version.
        if isInstalled { removeQuarantine(from: root); return }
        guard !isInstalling else { throw RuntimeError.commandFailed("Lilbud setup is already in progress.") }
        isInstalling = true; error = nil
        defer { isInstalling = false; status = "" }
        do {
            let manifest = try await RuntimeManifestClient.fetch()
            for artifact in manifest.artifacts where artifact.id == "pi-macos-arm64" || artifact.id == "ollama-macos-arm64" {
                if artifact.id.hasPrefix("pi-") && piExecutable() != nil { continue }
                if artifact.id.hasPrefix("ollama-") && ollamaExecutable() != nil { continue }
                try await install(artifact)
            }
            guard isInstalled else { throw RuntimeError.commandFailed("A required runtime executable was not found after installation.") }
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    private func install(_ artifact: RuntimeManifest.Artifact) async throws {
        status = "Downloading \(artifact.id)…"
        let (archive, response) = try await URLSession.shared.data(from: artifact.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RuntimeError.commandFailed("Couldn’t download \(artifact.id).") }
        let actualHash = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard actualHash.caseInsensitiveCompare(artifact.sha256) == .orderedSame else { throw RuntimeError.commandFailed("The download for \(artifact.id) failed integrity verification.") }

        let staging = root.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let archiveURL = staging.appending(path: artifact.archive == .zip ? "runtime.zip" : "runtime.tar.gz")
        try archive.write(to: archiveURL, options: .atomic)
        status = "Installing \(artifact.id)…"
        switch artifact.archive {
        case .zip: try run("/usr/bin/ditto", ["-x", "-k", archiveURL.path, staging.path])
        case .tarGz: try run("/usr/bin/tar", ["-xzf", archiveURL.path, "-C", staging.path])
        }
        let target = root.appending(path: artifact.id.hasPrefix("pi-") ? "Pi" : "Ollama", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: target)
        try fileManager.moveItem(at: staging, to: target)
        // URLSession marks all files extracted from an internet archive as quarantined.
        // The manifest hash is verified above and Ollama's app bundle is vendor signed;
        // remove that inherited marker so macOS may launch its CLI and MLX libraries.
        removeQuarantine(from: target)
    }

    private func executable(named name: String, below directory: URL) -> URL? {
        guard let iterator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
        for case let url as URL in iterator where url.lastPathComponent == name {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { return url }
        }
        return nil
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let error = Pipe(); process.standardError = error
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RuntimeError.commandFailed(String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
    }

    private func removeQuarantine(from url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-r", "-d", "com.apple.quarantine", url.path]
        try? process.run()
        process.waitUntilExit()
    }
}

@MainActor final class OllamaServer {
    static let shared = OllamaServer()
    private var process: Process?

    func ensureRunning(executable: URL) throws {
        if process?.isRunning == true { return }
        let server = Process(); server.executableURL = executable; server.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"
        environment["OLLAMA_MODELS"] = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Lilbud/Models", directoryHint: .isDirectory).path
        server.environment = environment
        server.standardOutput = Pipe(); server.standardError = Pipe()
        try server.run(); process = server
    }
}
