# Blitz

Native macOS menu-bar speech-to-text. Hold a hotkey, talk, get text pasted into the frontmost app. Whisper for transcription, optional GPT-4o-mini for style rewrites.

A self-hosted Wispr Flow alternative — you bring your own OpenAI key, you own the app.

## Why

- **Cost:** ~$1–11/month in API usage instead of $15/month subscription. Even at 1 hour of dictation per day you stay under the Wispr Pro price.
- **Control:** Your prompts, your hotkeys, no telemetry, no cloud account.
- **Native:** Swift / SwiftUI / AVAudioEngine. No Electron, no background bloat.

## Quick start (with Claude Code)

The fastest way to install Blitz is to paste [`SETUP.md`](./SETUP.md) into [Claude Code](https://docs.claude.com/en/docs/claude-code). It walks you through dependencies, build, key storage, and permissions.

## Manual install

```bash
git clone https://github.com/<YOUR_USERNAME>/blitz.git ~/Desktop/Blitz
cd ~/Desktop/Blitz
brew install xcodegen
xcodegen generate
xcodebuild -project Blitz.xcodeproj -scheme Blitz -configuration Release \
  -derivedDataPath build clean build
ditto build/Build/Products/Release/Blitz.app /Applications/Blitz.app
open /Applications/Blitz.app
```

Then in the menu-bar icon → Settings, paste your OpenAI API key. Grant Microphone + Accessibility permissions when prompted.

## Default hotkeys (hold to talk)

| Mode | Hotkey | Post-processing |
|---|---|---|
| Exact | Right-Option | none |
| Written | Ctrl+Opt+1 | GPT-4o-mini, written style |
| Rage | Ctrl+Opt+2 | GPT-4o-mini, diplomatic rewrite |
| Emoji | Ctrl+Opt+3 | GPT-4o-mini, add fitting emojis |

All remappable in Settings.

## Requirements

- macOS 14+
- Xcode 15+ (full Xcode, not just Command Line Tools — needed for `xcodebuild` of a SwiftUI app)
- An OpenAI API key

## License

MIT — do whatever you want with it.
