import Foundation
import AppKit

/// Identifies a specific physical modifier key (left vs right matters).
enum ModifierKey: String, Codable, CaseIterable, Hashable {
    case leftShift, rightShift
    case leftControl, rightControl
    case leftOption, rightOption
    case leftCommand, rightCommand
    case fn

    var displayName: String {
        switch self {
        case .leftShift:    return "Left Shift"
        case .rightShift:   return "Right Shift"
        case .leftControl:  return "Left Control"
        case .rightControl: return "Right Control"
        case .leftOption:   return "Left Option"
        case .rightOption:  return "Right Option"
        case .leftCommand:  return "Left Command"
        case .rightCommand: return "Right Command"
        case .fn:           return "Fn"
        }
    }

    /// CoreGraphics virtual key codes for each physical modifier.
    var keyCode: CGKeyCode {
        switch self {
        case .leftShift:    return 56
        case .rightShift:   return 60
        case .leftControl:  return 59
        case .rightControl: return 62
        case .leftOption:   return 58
        case .rightOption:  return 61
        case .leftCommand:  return 55
        case .rightCommand: return 54
        case .fn:           return 63
        }
    }
}

/// A user-configurable hotkey. Either a lone modifier key (e.g. Right-Option)
/// or a combination of modifiers + a regular key.
enum HotkeyBinding: Codable, Equatable, Hashable {
    case modifierOnly(ModifierKey)
    case combo(modifiers: UInt, keyCode: UInt16)

    /// Pretty description for settings UI.
    var displayString: String {
        switch self {
        case .modifierOnly(let key):
            return key.displayName
        case .combo(let modifiers, let keyCode):
            var parts: [String] = []
            let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            if flags.contains(.control) { parts.append("⌃") }
            if flags.contains(.option)  { parts.append("⌥") }
            if flags.contains(.shift)   { parts.append("⇧") }
            if flags.contains(.command) { parts.append("⌘") }
            parts.append(Self.keyName(for: keyCode))
            return parts.joined()
        }
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        case 29: return "0"
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        default: return "key\(keyCode)"
        }
    }
}
