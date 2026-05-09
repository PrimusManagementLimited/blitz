import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case recording(Mode)
    case processing
}

@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<OverlayView>?
    private let state = OverlayStateBox()

    func show(mode: Mode) {
        state.value = .recording(mode)
        ensurePanel()
        positionPanel()
        panel?.orderFrontRegardless()
    }

    func setProcessing() {
        state.value = .processing
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        if panel != nil { return }
        let size = NSSize(width: 180, height: 46)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: OverlayView(state: state))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        self.panel = panel
        self.hostingView = hosting
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let w = panel.frame.width
        let h = panel.frame.height
        let x = visible.midX - w / 2
        let y = visible.minY + 72
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Shared reference-type box so SwiftUI view re-renders when state changes.
@MainActor
final class OverlayStateBox: ObservableObject {
    @Published var value: OverlayState = .recording(.exact)
}

private struct OverlayView: View {
    @ObservedObject var state: OverlayStateBox
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.35 : 1.0)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: pulse
                )
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .onAppear { pulse = true }
    }

    private var label: String {
        switch state.value {
        case .recording(let m): return "Recording — \(m.displayName)"
        case .processing:       return "Transcribing…"
        }
    }

    private var color: Color {
        switch state.value {
        case .recording:  return .red
        case .processing: return .orange
        }
    }
}
