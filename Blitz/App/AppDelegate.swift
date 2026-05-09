import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var history: TranscriptHistory!
    private var coordinator: AppCoordinator!
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        EnvLoader.seedKeychainIfEmpty(account: AppSettings.apiKeyAccount)

        let settings = AppSettings()
        let history = TranscriptHistory()
        self.settings = settings
        self.history = history
        self.coordinator = AppCoordinator(settings: settings, history: history)
        self.menuBar = MenuBarController(
            openSettings: { [weak self] in self?.openSettings() },
            openHistory: { [weak self] in self?.openSettings(initialTab: .history) },
            quit: { NSApp.terminate(nil) }
        )

        requestAccessibilityIfNeeded()

        do {
            try coordinator.start()
        } catch {
            presentError("Blitz could not start", error.localizedDescription)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    // MARK: Settings window

    func openSettings(initialTab: SettingsTab = .general) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                settings: settings,
                history: history,
                onRetry: { [weak self] entry in self?.coordinator.retry(entry: entry) }
            )
        }
        settingsWindow?.show(tab: initialTab)
    }

    // MARK: Permissions

    private func requestAccessibilityIfNeeded() {
        let trusted = AXIsProcessTrusted()
        if trusted { return }

        let alert = NSAlert()
        alert.messageText = "Blitz needs Accessibility access"
        alert.informativeText = """
        To detect global hotkeys and paste transcribed text, Blitz needs \
        Accessibility permission.

        Click “Open Settings”, then enable Blitz under \
        Privacy & Security → Accessibility. You may need to relaunch Blitz \
        after granting access.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
            // Trigger the prompt so the app appears in the list.
            let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(opts)
        }
    }

    private func presentError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
