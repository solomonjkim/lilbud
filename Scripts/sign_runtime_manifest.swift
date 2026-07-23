import CryptoKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: sign_runtime_manifest.swift <manifest> <signature-output>\n", stderr)
    exit(2)
}
guard let encodedKey = ProcessInfo.processInfo.environment["LILBUD_RUNTIME_MANIFEST_PRIVATE_KEY"],
      let keyData = Data(base64Encoded: encodedKey) else {
    fputs("LILBUD_RUNTIME_MANIFEST_PRIVATE_KEY is missing or invalid.\n", stderr)
    exit(2)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    let manifest = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let signature = try privateKey.signature(for: manifest).base64EncodedData()
    try signature.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
} catch {
    fputs("Failed to sign manifest: \(error.localizedDescription)\n", stderr)
    exit(1)
}
