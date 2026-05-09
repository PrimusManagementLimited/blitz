import AppKit
import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let apiKeyAccount = "openai"

    @Published var bindings: [Mode: HotkeyBinding] {
        didSet { persistBindings() }
    }

    @Published var prompts: [Mode: String] {
        didSet { persistPrompts() }
    }

    /// `false` (default) = hold-to-talk; `true` = press once to start, press again to stop.
    @Published var toggleMode: Bool {
        didSet { UserDefaults.standard.set(toggleMode, forKey: "toggleMode") }
    }

    /// Reads from Keychain. Writing updates Keychain immediately.
    var apiKey: String {
        get { KeychainStore.get(Self.apiKeyAccount) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(Self.apiKeyAccount)
            } else {
                KeychainStore.set(newValue, for: Self.apiKeyAccount)
            }
            objectWillChange.send()
        }
    }

    init() {
        self.bindings = Self.loadBindings() ?? Self.defaultBindings
        self.prompts = Self.loadPrompts() ?? Mode.defaultPrompts
        self.toggleMode = UserDefaults.standard.bool(forKey: "toggleMode")
    }

    func resetPrompt(for mode: Mode) {
        prompts[mode] = Mode.defaultPrompts[mode] ?? ""
    }

    func resetBindings() {
        bindings = Self.defaultBindings
    }

    // MARK: - Defaults

    static let defaultBindings: [Mode: HotkeyBinding] = [
        .exact:   .modifierOnly(.rightOption),
        .written: .combo(modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyCode: 18), // 1
        .rage:    .combo(modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyCode: 19), // 2
        .emoji:   .combo(modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue, keyCode: 20)  // 3
    ]

    // MARK: - Persistence

    private func persistBindings() {
        let pairs = bindings.map { ($0.key.rawValue, $0.value) }
        let dict = Dictionary(uniqueKeysWithValues: pairs)
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "bindings")
        }
    }

    private static func loadBindings() -> [Mode: HotkeyBinding]? {
        guard let data = UserDefaults.standard.data(forKey: "bindings"),
              let dict = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data)
        else { return nil }
        var out: [Mode: HotkeyBinding] = [:]
        for (k, v) in dict { if let mode = Mode(rawValue: k) { out[mode] = v } }
        // Ensure all modes have bindings even if persisted dict is partial.
        for mode in Mode.allCases where out[mode] == nil {
            out[mode] = defaultBindings[mode]
        }
        return out
    }

    private func persistPrompts() {
        let pairs = prompts.map { ($0.key.rawValue, $0.value) }
        let dict = Dictionary(uniqueKeysWithValues: pairs)
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "prompts")
        }
    }

    private static func loadPrompts() -> [Mode: String]? {
        guard let data = UserDefaults.standard.data(forKey: "prompts"),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        var out: [Mode: String] = [:]
        for (k, v) in dict { if let mode = Mode(rawValue: k) { out[mode] = v } }
        for mode in Mode.allCases where out[mode] == nil {
            out[mode] = Mode.defaultPrompts[mode]
        }
        return out
    }
}

