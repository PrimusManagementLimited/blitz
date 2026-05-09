import SwiftUI
import AppKit

public enum SettingsTab: Hashable {
    case general, hotkeys, prompts, history
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: TranscriptHistory
    let onRetry: (HistoryEntry) -> Void
    @Binding var selectedTab: SettingsTab

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            HotkeysTab(settings: settings)
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                .tag(SettingsTab.hotkeys)

            PromptsTab(settings: settings)
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
                .tag(SettingsTab.prompts)

            HistoryView(history: history, onRetry: onRetry)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(SettingsTab.history)
        }
        .tabViewStyle(.automatic)
        .frame(width: 560, height: 620)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    @State private var keyInput: String = ""
    @State private var saveFeedback: String? = nil

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        SecureField("sk-…", text: $keyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)

                        Button("Save") {
                            settings.apiKey = keyInput
                            saveFeedback = "Saved"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if saveFeedback == "Saved" { saveFeedback = nil }
                            }
                        }
                        .disabled(keyInput == settings.apiKey)

                        Button("Clear") {
                            settings.apiKey = ""
                            keyInput = ""
                            saveFeedback = "Cleared"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if saveFeedback == "Cleared" { saveFeedback = nil }
                            }
                        }
                    }

                    Text("Stored in the macOS Keychain. Never written to disk in plaintext.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let feedback = saveFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }

                    Link("Get an API key",
                         destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            } header: {
                Text("OpenAI API Key")
            }

            Section {
                Toggle("Press-to-toggle mode (instead of hold-to-talk)",
                       isOn: $settings.toggleMode)
            } header: {
                Text("Behavior")
            } footer: {
                Text("When enabled, press the hotkey once to start recording and again to stop. When disabled, hold the hotkey to record.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            keyInput = settings.apiKey
        }
    }
}

// MARK: - Hotkeys

private struct HotkeysTab: View {
    @ObservedObject var settings: AppSettings
    @State private var recordingMode: Mode? = nil
    @State private var eventMonitor: Any? = nil

    private let subtitles: [Mode: String] = [
        .exact: "Exact — raw transcription",
        .written: "Written — clean written style",
        .rage: "Rage — diplomatic rewrite",
        .emoji: "Emoji — add fitting emojis"
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Mode.allCases) { mode in
                    HotkeyRow(
                        mode: mode,
                        subtitle: subtitles[mode] ?? mode.displayName,
                        binding: settings.bindings[mode],
                        isRecording: recordingMode == mode,
                        onRecord: { startRecording(for: mode) },
                        onCancel: { stopRecording() }
                    )
                }
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Click Record… then press a single modifier (e.g. Right Option) or a key combo (e.g. ⌃⌥1). Press Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset all hotkeys to defaults") {
                        settings.resetBindings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording(for mode: Mode) {
        stopRecording()
        recordingMode = mode

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard recordingMode != nil else { return event }

            if event.type == .keyDown {
                // Escape cancels
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                // Strip caps lock from consideration
                let cleanModifiers = modifiers.subtracting(.capsLock)

                if !cleanModifiers.isEmpty {
                    let binding = HotkeyBinding.combo(
                        modifiers: cleanModifiers.rawValue,
                        keyCode: UInt16(event.keyCode)
                    )
                    commit(binding)
                    return nil
                }
                // Normal key without modifiers — ignore (don't set a binding without modifiers)
                return nil
            }

            if event.type == .flagsChanged {
                if let modifier = Self.modifierKey(forKeyCode: event.keyCode) {
                    let binding = HotkeyBinding.modifierOnly(modifier)
                    commit(binding)
                    return nil
                }
                return nil
            }

            return event
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        recordingMode = nil
    }

    private func commit(_ binding: HotkeyBinding) {
        if let mode = recordingMode {
            settings.bindings[mode] = binding
        }
        stopRecording()
    }

    static func modifierKey(forKeyCode keyCode: UInt16) -> ModifierKey? {
        switch keyCode {
        case 56: return .leftShift
        case 60: return .rightShift
        case 59: return .leftControl
        case 62: return .rightControl
        case 58: return .leftOption
        case 61: return .rightOption
        case 55: return .leftCommand
        case 54: return .rightCommand
        case 63: return .fn
        default: return nil
        }
    }
}

private struct HotkeyRow: View {
    let mode: Mode
    let subtitle: String
    let binding: HotkeyBinding?
    let isRecording: Bool
    let onRecord: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(binding?.displayString ?? "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? .secondary : .primary)
                .frame(minWidth: 80, alignment: .trailing)

            Button(action: {
                if isRecording { onCancel() } else { onRecord() }
            }) {
                Text(isRecording ? "Press keys…" : "Record…")
                    .frame(minWidth: 90)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.08) : Color.clear)
                .padding(.horizontal, -6)
        )
    }
}

// MARK: - Prompts

private struct PromptsTab: View {
    @ObservedObject var settings: AppSettings

    private let promptModes: [Mode] = [.written, .rage, .emoji]

    var body: some View {
        Form {
            ForEach(promptModes, id: \.self) { mode in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: Binding(
                            get: { settings.prompts[mode, default: ""] },
                            set: { settings.prompts[mode] = $0 }
                        ))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                        HStack {
                            Spacer()
                            Button("Reset to default") {
                                settings.resetPrompt(for: mode)
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("\(mode.displayName) prompt")
                }
            }

            Section {
                Text("Prompts are sent as the system message to GPT-4o-mini.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
