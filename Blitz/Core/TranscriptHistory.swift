import Foundation

/// A single record of a dictation session: the mode that was used, the
/// transcribed text (if we got it), and optionally the audio file (kept until
/// the transcription succeeds or the user deletes the entry).
struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let mode: Mode
    var text: String?
    var rawTranscript: String?
    var errorMessage: String?
    var audioFileName: String?

    var isSuccessful: Bool { errorMessage == nil && text != nil && !(text?.isEmpty ?? true) }
    var canRetry: Bool { audioFileName != nil }

    var preview: String {
        if let t = text, !t.isEmpty { return t }
        if let err = errorMessage { return "Error: \(err)" }
        return "(no text yet)"
    }
}

@MainActor
final class TranscriptHistory: ObservableObject {
    static let maxEntries = 100

    @Published private(set) var entries: [HistoryEntry] = []

    private let fileManager = FileManager.default

    private lazy var baseDir: URL = {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = support.appendingPathComponent("Blitz", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let audio = dir.appendingPathComponent("audio", isDirectory: true)
        try? fileManager.createDirectory(at: audio, withIntermediateDirectories: true)
        return dir
    }()

    private var indexURL: URL { baseDir.appendingPathComponent("history.json") }
    private var audioDir: URL { baseDir.appendingPathComponent("audio", isDirectory: true) }

    init() {
        load()
    }

    // MARK: - Mutations

    /// Save a pending entry and write the audio blob to disk.
    /// Returns the new entry's id.
    @discardableResult
    func appendPending(mode: Mode, audioData: Data) -> UUID {
        let id = UUID()
        let filename = "\(id.uuidString).wav"
        let audioURL = audioDir.appendingPathComponent(filename)
        do {
            try audioData.write(to: audioURL, options: .atomic)
        } catch {
            // If writing fails we still create the entry without audio; the
            // user will see "(no audio)" and won't be able to retry.
        }

        let entry = HistoryEntry(
            id: id,
            createdAt: Date(),
            mode: mode,
            text: nil,
            rawTranscript: nil,
            errorMessage: nil,
            audioFileName: fileManager.fileExists(atPath: audioURL.path) ? filename : nil
        )
        entries.insert(entry, at: 0)
        trim()
        persist()
        return id
    }

    func markSucceeded(id: UUID, text: String, rawTranscript: String) {
        update(id: id) { entry in
            entry.text = text
            entry.rawTranscript = rawTranscript
            entry.errorMessage = nil
            // Free the audio file once transcription is committed; the text
            // is what the user wanted anyway.
            if let fn = entry.audioFileName {
                try? fileManager.removeItem(at: audioDir.appendingPathComponent(fn))
            }
            entry.audioFileName = nil
        }
    }

    func markFailed(id: UUID, message: String) {
        update(id: id) { entry in
            entry.errorMessage = message
        }
    }

    func remove(id: UUID) {
        if let entry = entries.first(where: { $0.id == id }), let fn = entry.audioFileName {
            try? fileManager.removeItem(at: audioDir.appendingPathComponent(fn))
        }
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        for entry in entries {
            if let fn = entry.audioFileName {
                try? fileManager.removeItem(at: audioDir.appendingPathComponent(fn))
            }
        }
        entries.removeAll()
        persist()
    }

    /// Returns the raw WAV data for a retry, or nil if audio is no longer on disk.
    func audioData(for id: UUID) -> Data? {
        guard let entry = entries.first(where: { $0.id == id }),
              let fn = entry.audioFileName
        else { return nil }
        return try? Data(contentsOf: audioDir.appendingPathComponent(fn))
    }

    // MARK: - Private

    private func update(id: UUID, _ mutate: (inout HistoryEntry) -> Void) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[idx]
        mutate(&entry)
        entries[idx] = entry
        persist()
    }

    private func trim() {
        while entries.count > Self.maxEntries {
            guard let removed = entries.popLast() else { break }
            if let fn = removed.audioFileName {
                try? fileManager.removeItem(at: audioDir.appendingPathComponent(fn))
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
