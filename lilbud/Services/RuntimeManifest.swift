import CryptoKit
import Foundation

struct RuntimeManifest: Codable, Sendable {
    let schemaVersion: Int
    let channel: String
    let minimumAppVersion: String
    let artifacts: [Artifact]
    let models: [Model]

    struct Artifact: Codable, Identifiable, Sendable {
        let id: String
        let version: String
        let url: URL
        let sha256: String
        let archive: Archive
        enum Archive: String, Codable, Sendable { case zip; case tarGz = "tar.gz" }
    }
    struct Model: Codable, Sendable { let id: String; let tier: String; let downloadBytes: Int }
}

enum RuntimeManifestClient {
    static let manifestURL = URL(string: "https://github.com/solomonjkim/lilbud/releases/download/runtime-manifest-stable/manifest.json")!
    static let signatureURL = URL(string: "https://github.com/solomonjkim/lilbud/releases/download/runtime-manifest-stable/manifest.sig")!
    private static let publicKey = "s9qHgedNpz/W5zfgI9eBxfwZcV8JYtIMPEjbXvqWhKM="

    static func fetch(session: URLSession = .shared) async throws -> RuntimeManifest {
        async let manifestData = session.data(from: manifestURL).0
        async let signatureData = session.data(from: signatureURL).0
        let (manifest, signature) = try await (manifestData, signatureData)
        guard let keyData = Data(base64Encoded: publicKey),
              let signatureData = Data(base64Encoded: signature) else { throw RuntimeManifestError.invalidSignature }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard key.isValidSignature(signatureData, for: manifest) else { throw RuntimeManifestError.invalidSignature }
        return try JSONDecoder().decode(RuntimeManifest.self, from: manifest)
    }
}

enum RuntimeManifestError: LocalizedError {
    case invalidSignature
    var errorDescription: String? { "Lilbud could not verify the runtime manifest." }
}
