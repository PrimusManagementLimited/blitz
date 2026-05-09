import Foundation

final class OpenAIClient {

    // MARK: - Errors

    private enum OpenAIError: LocalizedError {
        case missingAPIKey
        case httpError(status: Int, body: String)
        case decoding
        case empty

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Missing OpenAI API key."
            case .httpError(let status, let body):
                return "OpenAI HTTP \(status): \(body)"
            case .decoding:
                return "Failed to decode OpenAI response."
            case .empty:
                return "OpenAI returned an empty response."
            }
        }
    }

    // MARK: - Response Models

    private struct TranscriptionResponse: Codable {
        let text: String
    }

    private struct ChatCompletionResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let role: String?
                let content: String?
            }
            let message: Message?
        }
        let choices: [Choice]
    }

    private struct APIErrorEnvelope: Codable {
        struct APIError: Codable {
            let message: String?
            let type: String?
            let code: String?
        }
        let error: APIError?
    }

    // MARK: - Chat Request Models

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Codable {
        let model: String
        let temperature: Double
        let messages: [ChatMessage]
    }

    // MARK: - Properties

    private let apiKeyProvider: () -> String?
    private let session: URLSession = .shared
    private let requestTimeout: TimeInterval = 60

    private static let transcriptionsURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private static let chatCompletionsURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    // MARK: - Init

    init(apiKeyProvider: @escaping () -> String?) {
        self.apiKeyProvider = apiKeyProvider
    }

    // MARK: - Public API

    /// Uploads WAV (16 kHz mono PCM16) to /v1/audio/transcriptions (whisper-1)
    /// and returns the transcribed text.
    func transcribe(wav: Data) async throws -> String {
        let key = try resolveAPIKey()

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = Self.buildMultipartBody(
            boundary: boundary,
            fields: [
                ("model", "whisper-1"),
                ("response_format", "json")
            ],
            fileField: (
                name: "file",
                filename: "audio.wav",
                contentType: "audio/wav",
                data: wav
            )
        )

        var request = URLRequest(url: Self.transcriptionsURL, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        do {
            let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
            return decoded.text
        } catch {
            throw OpenAIError.decoding
        }
    }

    /// Runs a single chat completion with the given system prompt and
    /// user content set to `text`. Model: gpt-4o-mini. Returns the assistant message text.
    func rewrite(_ text: String, systemPrompt: String) async throws -> String {
        let key = try resolveAPIKey()

        var messages: [ChatMessage] = []
        if !systemPrompt.isEmpty {
            messages.append(ChatMessage(role: "system", content: systemPrompt))
        }
        messages.append(ChatMessage(role: "user", content: text))

        let payload = ChatRequest(
            model: "gpt-4o-mini",
            temperature: 0.3,
            messages: messages
        )

        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw OpenAIError.decoding
        }

        var request = URLRequest(url: Self.chatCompletionsURL, timeoutInterval: requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response, data: data)

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw OpenAIError.decoding
        }

        guard let content = decoded.choices.first?.message?.content else {
            throw OpenAIError.empty
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw OpenAIError.empty
        }
        return trimmed
    }

    // MARK: - Helpers

    private func resolveAPIKey() throws -> String {
        guard let key = apiKeyProvider(), !key.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        return key
    }

    /// Validate an HTTP response. Throws `.httpError` on non-2xx, surfacing
    /// an API error message if the body contains one. Never includes the
    /// Authorization header in the error text.
    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(status: -1, body: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = extractErrorMessage(from: data)
            throw OpenAIError.httpError(status: http.statusCode, body: scrubAuthorization(message))
        }
    }

    /// Try to extract `error.message` from a JSON error envelope.
    /// Falls back to a UTF-8 decoding of the body, or a short placeholder.
    private static func extractErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let message = envelope.error?.message,
           !message.isEmpty {
            return message
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "<empty body>"
    }

    /// Defensively strip any accidental occurrence of a Bearer token from
    /// strings that will be surfaced in error descriptions.
    private static func scrubAuthorization(_ string: String) -> String {
        // Redact any "Bearer <token>" sequence.
        let pattern = #"(?i)Bearer\s+[A-Za-z0-9._\-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return string
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(
            in: string,
            options: [],
            range: range,
            withTemplate: "Bearer [REDACTED]"
        )
    }

    // MARK: - Multipart

    /// Builds a multipart/form-data body with the given simple text fields
    /// and a single file field, using proper CRLF separators and a trailing
    /// boundary.
    private static func buildMultipartBody(
        boundary: String,
        fields: [(name: String, value: String)],
        fileField: (name: String, filename: String, contentType: String, data: Data)
    ) -> Data {
        let crlf = "\r\n"
        var body = Data()

        func append(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }

        for field in fields {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(field.name)\"\(crlf)\(crlf)")
            append("\(field.value)\(crlf)")
        }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"\(fileField.name)\"; filename=\"\(fileField.filename)\"\(crlf)")
        append("Content-Type: \(fileField.contentType)\(crlf)\(crlf)")
        body.append(fileField.data)
        append(crlf)

        append("--\(boundary)--\(crlf)")

        return body
    }
}
