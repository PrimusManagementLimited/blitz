import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let openSettings: () -> Void
    private let openHistory: () -> Void
    private let quit: () -> Void

    init(openSettings: @escaping () -> Void,
         openHistory: @escaping () -> Void,
         quit: @escaping () -> Void) {
        self.openSettings = openSettings
        self.openHistory = openHistory
        self.quit = quit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "Blitz")
            btn.image?.isTemplate = true
            btn.toolTip = "Blitz"
        }

        let menu = NSMenu()
        menu.delegate = self

        let historyItem = NSMenuItem(
            title: "Show History…",
            action: #selector(openHistoryAction),
            keyEquivalent: "h"
        )
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Blitz",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettingsAction() { openSettings() }
    @objc private func openHistoryAction() { openHistory() }
    @objc private func quitAction() { quit() }
}
