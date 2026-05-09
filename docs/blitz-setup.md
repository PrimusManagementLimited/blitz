# Blitz Installer

**For the human reading this:** drag this whole file into your Claude Code input and press Enter. Claude Code will install Blitz on your Mac in about 2 minutes.

Don't have Claude Code yet? In Terminal:
```
brew install node
npm install -g @anthropic-ai/claude-code
cd ~/Desktop && claude
```
Then drag this file in.

---

## Before you start — make sure you have these

1. **macOS 14 (Sonoma) or newer.** Apple menu → About This Mac.
2. **Full Xcode** (not just Command Line Tools). Open the App Store, search "Xcode", install. **It's a 15+ GB download — this is the biggest time sink.** If you've never used Xcode, install it before starting and come back when it's done.
3. **An OpenAI API key with paid credits.** This is *not* the same as a ChatGPT subscription:
   - Go to https://platform.openai.com/api-keys (sign up if needed).
   - Add a payment method at https://platform.openai.com/settings/organization/billing — $5–10 prepaid is enough to start.
   - Click **Create new secret key**, copy it (starts with `sk-`).
4. **Claude Code** (already installed if you're reading this in it).

If any of those is missing, sort it out first — Blitz can't install without all four.

---

You are helping me install **Blitz**, a native macOS menu-bar speech-to-text app — a self-hosted alternative to Wispr Flow. Walk me through it interactively. Run commands yourself via the Bash tool. Ask one thing at a time, don't dump all commands at once. If a step errors, stop and show me the error.

**Steps:**

1. **Verify environment.** Run `sw_vers` — confirm macOS 14.0 or higher. Run `which xcodebuild git brew`. If `brew` is missing, instruct me to install it from https://brew.sh and stop. If `xcodebuild` is missing, tell me to install full Xcode from the App Store (not just CLT) and stop.

2. **Confirm Xcode.app is the active developer dir.** Run `xcode-select -p`. If it returns `/Library/Developer/CommandLineTools` (or anything that isn't an Xcode.app path), Xcode.app is installed but not selected. Detect Xcode with `ls -d /Applications/Xcode*.app 2>/dev/null | head -1` and **use the resulting path as a `DEVELOPER_DIR=...` prefix on every `xcodebuild` command in step 6** — do NOT run `sudo xcode-select -s` (that needs admin password). If no Xcode.app is found, tell me to install Xcode from the App Store and stop.

3. **Install xcodegen if missing:** `brew list xcodegen >/dev/null 2>&1 || brew install xcodegen`

4. **Clone the repo:**
   ```
   cd ~/Desktop && git clone https://github.com/PrimusManagementLimited/blitz.git Blitz && cd Blitz
   ```
   If `~/Desktop/Blitz` already exists, ask whether to back it up (rename to `Blitz-backup-<timestamp>`) or abort.

5. **Get my OpenAI API key.** Ask me to paste it. The key starts with `sk-`. If I don't have one yet, point me to https://platform.openai.com/api-keys and tell me to also set up billing at https://platform.openai.com/settings/organization/billing ($5–10 prepaid is plenty), then come back. **Do NOT echo the key back in chat or write it to any file.** Once I paste it, store in macOS Keychain:
   ```
   security add-generic-password -s "com.elyasmirzazadeh.blitz" -a "openai" -w "<KEY>" -U
   ```
   Verify silently: `security find-generic-password -s "com.elyasmirzazadeh.blitz" -a "openai" >/dev/null && echo OK`

6. **Generate Xcode project + build (Release).** If step 2 told you to use a `DEVELOPER_DIR=...` prefix, prepend it to the `xcodebuild` command:
   ```
   cd ~/Desktop/Blitz
   xcodegen generate
   xcodebuild -project Blitz.xcodeproj -scheme Blitz -configuration Release \
     -derivedDataPath build clean build
   ```
   If the build fails, show me the last 30 lines of output and stop.

7. **Install to /Applications.** Use `ditto`, NOT `cp -R` (cp -R merges into existing bundles and corrupts them):
   ```
   rm -rf /Applications/Blitz.app
   ditto build/Build/Products/Release/Blitz.app /Applications/Blitz.app
   ```

8. **Strip quarantine + launch.** The build is ad-hoc signed (no Apple Developer account), so macOS Gatekeeper will block it on first launch with a "developer cannot be verified" warning. Strip the quarantine attribute first, then open:
   ```
   xattr -cr /Applications/Blitz.app
   open /Applications/Blitz.app
   ```
   If the user still sees a Gatekeeper dialog, tell them: System Settings → Privacy & Security → scroll down → click **Open Anyway** next to "Blitz was blocked".

9. **Find the menu-bar icon.** Tell me to look top-right of the screen — Blitz lives there as a small icon.

10. **Permissions walkthrough.** Tell me:
    - First time I hold the hotkey, macOS will prompt for **Microphone access** — grant it.
    - Then for **Accessibility access** (needed to send Cmd+V into other apps) — open System Settings → Privacy & Security → Accessibility and toggle Blitz on.
    - After granting Accessibility, **fully quit and relaunch** Blitz (menu-bar icon → Quit, then `open /Applications/Blitz.app` again).

11. **Default hotkeys (hold to talk):**
    - Right-Option → Exact transcription
    - Ctrl+Opt+1 → Written style rewrite
    - Ctrl+Opt+2 → Diplomatic rewrite ("rage mode")
    - Ctrl+Opt+3 → Add fitting emojis
    - All remappable in menu-bar icon → Settings.

12. **Test.** Tell me to open Notes.app, click into the text area, hold Right-Option, say "hello world", release. Text should appear. If nothing happens, debug: `log show --predicate 'process == "Blitz"' --last 2m`.

**Rules:**
- Don't proceed past a step if it errored.
- Don't echo my API key anywhere.
- Don't suggest `sudo` unless explicitly required.

Start with step 1.
