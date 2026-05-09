import AppKit
import CoreGraphics
import Foundation

protocol HotkeyManagerDelegate: AnyObject {
    @MainActor func hotkeyPressed(mode: Mode)
    @MainActor func hotkeyReleased(mode: Mode)
}

enum HotkeyError: LocalizedError {
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Blitz needs Accessibility permission to listen for global hotkeys. " +
                   "Enable it in System Settings → Privacy & Security → Accessibility, then relaunch Blitz."
        }
    }
}

@MainActor
final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    var bindings: [Mode: HotkeyBinding] = [:]
    var toggleMode: Bool = false

    /// Tapping this modifier while a modifier-only hotkey is held latches the
    /// session so recording continues after the primary modifier is released.
    /// A subsequent press of the original binding ends the session.
    /// Default: Right-Command (next to Right-Option, no system shortcut).
    var latchTrigger: ModifierKey = .rightCommand

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private enum ActiveState {
        case none
        case holding(Mode)
        case latched(Mode)

        var mode: Mode? {
            switch self {
            case .none: return nil
            case .holding(let m), .latched(let m): return m
            }
        }
    }

    private var activeState: ActiveState = .none
    private var pressedModifiers: Set<ModifierKey> = []

    init() {}

    func start() throws {
        guard tap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    manager.handle(type: type, keyCode: keyCode, flags: flags)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            throw HotkeyError.accessibilityDenied
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        pressedModifiers.removeAll()
        if let mode = activeState.mode {
            delegate?.hotkeyReleased(mode: mode)
        }
        activeState = .none
    }

    // MARK: - Event dispatch

    private func handle(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        switch type {
        case .flagsChanged:
            handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown:
            handleKeyDown(keyCode: keyCode, flags: flags)
        case .keyUp:
            handleKeyUp(keyCode: keyCode)
        default:
            break
        }
    }

    // MARK: - flagsChanged (modifier press/release)

    private func handleFlagsChanged(keyCode: UInt16, flags: CGEventFlags) {
        guard let modKey = ModifierKey.allCases.first(where: { $0.keyCode == CGKeyCode(keyCode) })
        else { return }

        let wasPressed = pressedModifiers.contains(modKey)
        if wasPressed {
            pressedModifiers.remove(modKey)
        } else {
            pressedModifiers.insert(modKey)
        }

        // Latch trigger: pressing the latch modifier while already holding a
        // modifier-only binding flips the session from hold-to-talk to latched.
        // Swallow the event so the latch key itself never becomes a binding trigger.
        if !wasPressed,
           modKey == latchTrigger,
           case .holding(let mode) = activeState {
            activeState = .latched(mode)
            return
        }

        if wasPressed {
            bindingReleased(for: .modifierOnly(modKey))
        } else {
            bindingPressed(for: .modifierOnly(modKey))
        }
    }

    // MARK: - keyDown (combo triggers + Space latch)

    private func handleKeyDown(keyCode: UInt16, flags: CGEventFlags) {
        let eventMods = Self.nsFlags(from: flags)

        let matchingBinding = bindings.first { _, binding in
            if case .combo(let modifiers, let kc) = binding {
                let required = NSEvent.ModifierFlags(rawValue: modifiers)
                    .intersection(.deviceIndependentFlagsMask)
                return kc == keyCode && !required.isEmpty && eventMods.isSuperset(of: required)
            }
            return false
        }
        guard let (_, binding) = matchingBinding else { return }
        bindingPressed(for: binding)
    }

    private func handleKeyUp(keyCode: UInt16) {
        // If a combo is the active binding and its keyCode went up → released.
        guard let mode = activeState.mode, let binding = bindings[mode] else { return }
        if case .combo(_, let kc) = binding, kc == keyCode {
            bindingReleased(for: binding)
        }
    }

    // MARK: - Binding state machine

    /// Called when a physical binding just became active (key went down).
    private func bindingPressed(for binding: HotkeyBinding) {
        guard let mode = modeFor(binding: binding) else { return }

        switch activeState {
        case .none:
            activeState = .holding(mode)
            delegate?.hotkeyPressed(mode: mode)

        case .holding(let active):
            // Auto-repeat or a different binding while already holding — ignore.
            if active == mode, toggleMode {
                // toggle-mode: second press stops
                activeState = .none
                delegate?.hotkeyReleased(mode: mode)
            }

        case .latched(let active):
            if active == mode {
                // Same binding pressed again → stop.
                activeState = .none
                delegate?.hotkeyReleased(mode: mode)
            }
            // Otherwise ignore: only the active mode's binding can end the session.
        }
    }

    /// Called when a physical binding just became inactive (key went up / modifier released).
    private func bindingReleased(for binding: HotkeyBinding) {
        guard let mode = modeFor(binding: binding) else { return }

        switch activeState {
        case .holding(let active) where active == mode:
            if toggleMode {
                // In toggle-mode, releases don't end recording; wait for next press.
                return
            }
            activeState = .none
            delegate?.hotkeyReleased(mode: mode)

        case .latched:
            // Releases are ignored while latched — only a fresh press ends it.
            return

        default:
            return
        }
    }

    private func modeFor(binding: HotkeyBinding) -> Mode? {
        return bindings.first { $0.value == binding }?.key
    }

    // MARK: - Helpers

    private static func nsFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var out: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl)   { out.insert(.control) }
        if flags.contains(.maskAlternate) { out.insert(.option) }
        if flags.contains(.maskShift)     { out.insert(.shift) }
        if flags.contains(.maskCommand)   { out.insert(.command) }
        return out.intersection(.deviceIndependentFlagsMask)
    }
}
