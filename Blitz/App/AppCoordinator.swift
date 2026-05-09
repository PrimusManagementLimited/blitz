import AppKit
import Combine

@MainActor
final class AppCoordinator: HotkeyManagerDelegate {
    private let settings: AppSettings
    let history: TranscriptHistory
    private let audio: AudioCapture
    private let openAI: OpenAIClient
    private let hotkeys: HotkeyManager
    private let overlay: RecordingOverlayController

    private var currentMode: Mode?
    private var isProcessing = false
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, history: TranscriptHistory) {
        self.settings = settings
        self.history = history
        self.audio = AudioCapture()
        self.openAI = OpenAIClient(apiKeyProvider: { [weak settings] in
            guard let key = settings?.apiKey, !key.isEmpty else { return nil }
            return key
        })
        self.hotkeys = HotkeyManager()
        self.overlay = RecordingOverlayController()

        hotkeys.delegate = self
        hotkeys.bindings = settings.bindings
        hotkeys.toggleMode = settings.toggleMode

        settings.$bindings
            .sink { [weak self] in self?.hotkeys.bindings = $0 }
            .store(in: &cancellables)
        settings.$toggleMode
            .sink { [weak self] in self?.hotkeys.toggleMode = $0 }
            .store(in: &cancellables)
    }

    func start() throws { try hotkeys.start() }
    func stop() { hotkeys.stop() }

    // MARK: - HotkeyManagerDelegate

    func hotkeyPressed(mode: Mode) {
        guard currentMode == nil, !isProcessing else { return }
        startRecording(mode: mode)
    }

    func hotkeyReleased(mode: Mode) {
        guard currentMode == mode else { return }
        Task { await finishRecording(mode: mode) }
    }

    // MARK: - Retry from history

    func retry(entry: HistoryEntry) {
        Task { await runRetry(entry: entry) }
    }

    private func runRetry(entry: HistoryEntry) async {
        guard let wav = history.audioData(for: entry.id) else {
            presentError("Can't retry", "Audio for this entry is no longer on disk.")
            return
        }
        do {
            let raw = try await openAI.transcribe(wav: wav)
            let finalText: String
            if entry.mode.needsPostProcessing {
                let prompt = settings.prompts[entry.mode] ?? ""
                finalText = try await openAI.rewrite(raw, systemPrompt: prompt)
            } else {
                finalText = raw
            }
            history.markSucceeded(id: entry.id, text: finalText, rawTranscript: raw)
            // After a retry we put the text on the clipboard — the user
            // almost certainly wants to paste it somewhere specific, not
            // into the currently focused app.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(finalText, forType: .string)
        } catch {
            history.markFailed(id: entry.id, message: error.localizedDescription)
            presentError("Retry failed", error.localizedDescription)
        }
    }

    // MARK: - State

    private func startRecording(mode: Mode) {
        currentMode = mode
        overlay.show(mode: mode)
        do {
            try audio.start()
        } catch {
            overlay.hide()
            currentMode = nil
            presentError("Microphone error", error.localizedDescription)
        }
    }

    private func finishRecording(mode: Mode) async {
        currentMode = nil
        isProcessing = true
        overlay.setProcessing()
        let wavData = audio.stop()

        guard !wavData.isEmpty else {
            overlay.hide()
            isProcessing = false
            presentError("No audio captured",
                         "Blitz didn't receive any audio samples. Make sure the microphone is allowed for Blitz in System Settings → Privacy & Security → Microphone, and that the MacBook's built-in mic is available.")
            return
        }

        let entryID = history.appendPending(mode: mode, audioData: wavData)

        do {
            let raw = try await openAI.transcribe(wav: wavData)
            let finalText: String
            if mode.needsPostProcessing {
                let prompt = settings.prompts[mode] ?? ""
                finalText = try await openAI.rewrite(raw, systemPrompt: prompt)
            } else {
                finalText = raw
            }
            history.markSucceeded(id: entryID, text: finalText, rawTranscript: raw)
            overlay.hide()
            await TextInjector.insert(finalText)
        } catch {
            history.markFailed(id: entryID, message: error.localizedDescription)
            overlay.hide()
            presentError("Transcription failed",
                         error.localizedDescription +
                         "\n\nYour recording is saved in Blitz History — you can retry it from Settings → History.")
        }
        isProcessing = false
    }

    private func presentError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
