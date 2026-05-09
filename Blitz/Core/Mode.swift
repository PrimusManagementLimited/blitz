import Foundation

enum Mode: String, CaseIterable, Identifiable, Codable, Hashable {
    case exact
    case written
    case rage
    case emoji

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .exact:   return "Exact"
        case .written: return "Written"
        case .rage:    return "Rage"
        case .emoji:   return "Emoji"
        }
    }

    var needsPostProcessing: Bool { self != .exact }

    static let defaultPrompts: [Mode: String] = [
        .exact: "",
        .written: """
        You rewrite spoken dictation into clean written text. Preserve the speaker's \
        meaning and voice, but fix grammar, punctuation, filler words, and repetitions. \
        Output only the rewritten text — no preamble, no commentary. Match the language \
        of the input.
        """,
        .rage: """
        The user is venting. Rewrite their message as a diplomatic, professional, \
        constructive version that preserves the core request or concern but removes \
        anger, insults, and aggressive language. Stay in first person, same language \
        as the input. Output only the rewritten text.
        """,
        .emoji: """
        Rewrite the dictation cleanly and insert fitting emojis where they add warmth \
        or clarity — no more than one per sentence, never gratuitous. Same language \
        as input. Output only the rewritten text.
        """
    ]
}
