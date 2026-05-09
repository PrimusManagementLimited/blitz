import AppKit

/// Inserts text into the frontmost app by writing to the pasteboard and
/// synthesizing Cmd+V. Saves and restores the previous pasteboard contents.
enum TextInjector {

    /// Default delay between paste synthesis and pasteboard restore.
    private static let restoreDelay: UInt64 = 180_000_000 // 180ms

    static func insert(_ text: String) async {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general

        let snapshot = snapshotPasteboard(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)

        postCmdV()

        // Give the receiving app time to read the pasteboard before we restore.
        try? await Task.sleep(nanoseconds: restoreDelay)

        restorePasteboard(pb, from: snapshot)
    }

    // MARK: - Pasteboard snapshot / restore

    private struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static func snapshotPasteboard(_ pb: NSPasteboard) -> Snapshot {
        guard let items = pb.pasteboardItems else { return Snapshot(items: []) }
        var out: [[NSPasteboard.PasteboardType: Data]] = []
        for item in items {
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            if !dict.isEmpty { out.append(dict) }
        }
        return Snapshot(items: out)
    }

    private static func restorePasteboard(_ pb: NSPasteboard, from snapshot: Snapshot) {
        pb.clearContents()
        guard !snapshot.items.isEmpty else { return }
        let newItems: [NSPasteboardItem] = snapshot.items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pb.writeObjects(newItems)
    }

    // MARK: - Cmd+V synthesis

    private static func postCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // "v"
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        let loc = CGEventTapLocation.cghidEventTap
        down?.post(tap: loc)
        up?.post(tap: loc)
    }
}
