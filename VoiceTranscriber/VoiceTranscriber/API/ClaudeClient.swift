import Foundation

/// Client for the Anthropic Claude API, used for cleaning up raw transcriptions.
final class ClaudeClient {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession
    private let modelID = "claude-haiku-4-5-20251001"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Cleans up a raw voice transcription using Claude Haiku.
    /// - Parameter rawText: The raw transcription from Whisper
    /// - Returns: Cleaned text with filler words removed and corrections applied
    func cleanTranscription(_ rawText: String) async throws -> String {
        guard let apiKey = ConfigManager.shared.claudeAPIKey, !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        // Don't process very short or empty text
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return trimmed
        }

        let prompt = buildCleanupPrompt(rawText: trimmed)

        let requestBody = ClaudeRequest(
            model: modelID,
            max_tokens: 4096,
            messages: [
                ClaudeMessage(role: "user", content: prompt)
            ]
        )

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textBlock = result.content.first(where: { $0.type == "text" }) else {
            throw ClaudeError.noTextInResponse
        }

        return textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt

    private func buildCleanupPrompt(rawText: String) -> String {
        """
        You are a voice transcription cleaner. Your job is to fix common speech patterns WITHOUT changing meaning.

        Rules:
        1. Remove filler words and false starts: "um", "uh", "like", "you know", "I mean" (unless essential to meaning)
        2. Detect self-corrections and use only the corrected version. Example: "I want to go to the store, no wait, I want to go to the park" → "I want to go to the park"
        3. Fix repeated words from stuttering: "I-I-I think" → "I think"
        4. Keep contractions natural: "I'm", "don't", etc.
        5. Preserve the speaker's tone and voice—don't over-formalize
        6. If the user says items with numbers between them, such as "one apples, two bananas" and you can tell it's part of a list return as a list. ie:
               1. Apples
               2. Bananas
        7. If the transcription is clearly incomplete or nonsensical, return it as-is with no changes
        8. Output ONLY the cleaned text. No explanations, no markers, nothing else.

        Raw transcription:
        \(rawText)

        Cleaned output:
        """
    }
}

// MARK: - Request/Response Models

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
}

private struct ClaudeMessage: Encodable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case noTextInResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude API key is not configured. Please add it in Settings."
        case .invalidResponse:
            return "Received an invalid response from the Claude API."
        case .noTextInResponse:
            return "Claude response did not contain any text content."
        case .apiError(let statusCode, let message):
            return "Claude API error (\(statusCode)): \(message)"
        }
    }
}
