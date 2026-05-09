# Blitz — Architecture

Native macOS menu-bar speech-to-text. Hold hotkey → record → Whisper → optional GPT-4o-mini rewrite → paste into frontmost app.

## Runtime flow

```
User holds hotkey
   │
   ▼
HotkeyManager (CGEventTap)  ──► emits .startRecording(mode)
   │
   ▼
AppCoordinator starts AudioCapture + shows RecordingOverlay
   │
   ▼
User releases hotkey
   │
   ▼
HotkeyManager  ──► .stopRecording
   │
   ▼
AudioCapture yields 16kHz mono WAV Data
   │
   ▼
OpenAIClient.transcribe(wav) → raw text
   │
   ├── mode == .exact     → text
   └── mode != .exact     → OpenAIClient.rewrite(text, mode) → styled text
   │
   ▼
TextInjector: save pasteboard → write text → CGEvent Cmd+V → restore pasteboard
   │
   ▼
Overlay dismisses
```

## Modules

| File | Responsibility |
|------|----------------|
| `App/BlitzApp.swift` | `@main` entry, wires AppDelegate |
| `App/AppDelegate.swift` | `LSUIElement`, accessory activation, builds AppCoordinator |
| `App/AppCoordinator.swift` | Orchestrates modules, owns state machine |
| `Core/Mode.swift` | `.exact / .written / .rage / .emoji` + default prompts |
| `Core/AppSettings.swift` | `@MainActor ObservableObject`, UserDefaults-backed |
| `Core/KeychainStore.swift` | Generic-password Keychain wrapper for API key |
| `Audio/AudioCapture.swift` | AVAudioEngine tap → float32 → resample 16kHz mono → WAV Data |
| `Transcription/OpenAIClient.swift` | Whisper multipart upload + Chat Completions |
| `Hotkeys/HotkeyManager.swift` | CGEventTap, hold-to-talk + toggle-mode, configurable |
| `TextInjection/TextInjector.swift` | Pasteboard save/write → CGEvent Cmd+V → restore |
| `UI/MenuBarController.swift` | `NSStatusItem` + menu (Settings, Quit) |
| `UI/RecordingOverlay.swift` | Borderless floating NSPanel with pulse animation |
| `UI/SettingsView.swift` | SwiftUI settings (API key, hotkeys, prompts, toggle) |

## Default hotkeys (hold-to-talk)

| Mode | Hotkey | Post-processing |
|------|--------|-----------------|
| Exact | Right-Option | none |
| Written | Ctrl+Opt+1 | GPT-4o-mini: written style |
| Rage | Ctrl+Opt+2 | GPT-4o-mini: diplomatic rewrite |
| Emoji | Ctrl+Opt+3 | GPT-4o-mini: add fitting emojis |

All remappable in Settings. `Fn+<mod>` was rejected in favor of these because Fn is claimed by macOS Dictation and CGEventTap delivery is inconsistent across keyboards.

## Permissions

- **Microphone** — `NSMicrophoneUsageDescription` in Info.plist, prompted by AVCaptureDevice.
- **Accessibility** — required for CGEventTap + CGEvent-based Cmd+V posting. Requested at launch with explanatory dialog; opens System Settings pane if denied.
- **No sandbox** — app is non-sandboxed (like Wispr Flow / Raycast) because sandboxed apps cannot post CGEvents into arbitrary foreground apps or tap global events.

## Secrets

- Dev: `.env` in project root, read only by debug builds via `Bundle`-embedded resource fallback (gitignored).
- Production path: Settings UI writes key to Keychain service `com.elyasmirzazadeh.blitz` account `openai`. Runtime prefers Keychain; falls back to `.env` only if Keychain empty.
- Key is never logged. Network errors scrub Authorization headers.

## Clipboard

`TextInjector` snapshots `NSPasteboard.general` contents (all pasteboard items) → writes transcribed text → posts Cmd+V via CGEvent → waits ~150ms for paste to propagate → restores original items. If injection fails, leaves the text on the pasteboard so user can paste manually.

## Build

- `xcodegen generate` produces `Blitz.xcodeproj` from `project.yml`.
- `xcodebuild -project Blitz.xcodeproj -scheme Blitz -configuration Debug` builds to `build/Debug/Blitz.app`.
- Ad-hoc signed (`CODE_SIGN_IDENTITY=-`), no provisioning profile. Runs locally on user's Mac.
