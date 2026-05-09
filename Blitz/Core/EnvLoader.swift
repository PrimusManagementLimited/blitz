import Foundation

/// Dev-only convenience: on first launch, if the Keychain has no API key,
/// try to read one from a `.env` file at a known dev path and seed the
/// Keychain. Never reads the file again after that.
enum EnvLoader {
    /// Absolute dev location. Only consulted once, at first launch.
    private static let devEnvPath = NSString("~/Desktop/Blitz/.env")
        .expandingTildeInPath

    static func seedKeychainIfEmpty(account: String) {
        guard KeychainStore.get(account) == nil else { return }
        guard let contents = try? String(contentsOfFile: devEnvPath, encoding: .utf8)
        else { return }
        for rawLine in contents.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if key == "OPENAI_API_KEY", !value.isEmpty {
                KeychainStore.set(value, for: account)
                return
            }
        }
    }
}
