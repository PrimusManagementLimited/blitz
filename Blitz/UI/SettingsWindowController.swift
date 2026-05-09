import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let container: SettingsContainerState

    init(settings: AppSettings,
         history: TranscriptHistory,
         onRetry: @escaping (HistoryEntry) -> Void) {
        let container = SettingsContainerState()
        self.container = container
        let root = SettingsContainer(
            settings: settings,
            history: history,
            onRetry: onRetry,
            state: container
        )
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Blitz Settings"
        window.setContentSize(NSSize(width: 560, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }

    func show(tab: SettingsTab = .general) {
        container.selectedTab = tab
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class SettingsContainerState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

private struct SettingsContainer: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: TranscriptHistory
    let onRetry: (HistoryEntry) -> Void
    @ObservedObject fileprivate var state: SettingsContainerState

    var body: some View {
        SettingsView(
            settings: settings,
            history: history,
            onRetry: onRetry,
            selectedTab: Binding(
                get: { state.selectedTab },
                set: { state.selectedTab = $0 }
            )
        )
    }
}
