import Foundation

/// Transcribes audio directly via the Claude API using audio content blocks.
/// Combines transcription + cleanup in a single API call — no separate Whisper step needed.
/// Uses the same Claude API key as text cleanup, so no additional API key required.
final class ClaudeAudioClient {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession
    private let modelID = "claude-sonnet-4-5-20250514"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribes and cleans audio in a single Claude API call.
    /// The audio is sent as a content block alongside a system prompt that handles
    /// both transcription and cleanup — applying dictionary, style, corrections, etc.
    func transcribeAndClean(
        fileURL: URL,
        dictionaryWords: [String] = [],
        styleTone: StyleTone = .formal,
        activeApp: String? = nil,
        contextText: String? = nil,
        smartFormatting: Bool = true,
        translationEnabled: Bool = false,
        targetLanguage: String = "en",
        recentCorrections: [WordCorrection] = []
    ) async throws -> (rawText: String, cleanedText: String) {
        guard let apiKey = ConfigManager.shared.claudeAPIKey, !apiKey.isEmpty else {
            throw ClaudeAudioError.missingAPIKey
        }

        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else {
            throw ClaudeAudioError.emptyAudioFile
        }

        let base64Audio = audioData.base64EncodedString()
        let mediaType = fileURL.pathExtension == "m4a" ? "audio/mp4" : "audio/wav"

        let systemPrompt = buildSystemPrompt(
            dictionaryWords: dictionaryWords,
            styleTone: styleTone,
            activeApp: activeApp,
            contextText: contextText,
            smartFormatting: smartFormatting,
            translationEnabled: translationEnabled,
            targetLanguage: targetLanguage,
            recentCorrections: recentCorrections
        )

        // Build the request with audio content block
        let requestBody: [String: Any] = [
            "model": modelID,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "audio",
                            "source": [
                                "type": "base64",
                                "media_type": mediaType,
                                "data": base64Audio
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "Transcribe this audio and apply the cleaning rules. Output ONLY the cleaned transcription."
                        ]
                    ]
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAudioError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAudioError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(ClaudeAudioResponse.self, from: data)
        guard let textBlock = result.content.first(where: { $0.type == "text" }) else {
            throw ClaudeAudioError.noTextInResponse
        }

        let cleanedText = textBlock.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // For Claude direct audio, raw and cleaned are effectively the same since Claude does both
        return (rawText: cleanedText, cleanedText: cleanedText)
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(
        dictionaryWords: [String],
        styleTone: StyleTone,
        activeApp: String?,
        contextText: String?,
        smartFormatting: Bool,
        translationEnabled: Bool,
        targetLanguage: String,
        recentCorrections: [WordCorrection]
    ) -> String {
        var prompt = """
        You are a voice transcription assistant. You will receive an audio recording of someone speaking. \
        Your job is to transcribe the speech accurately and clean it up. Output ONLY the final cleaned text.

        TRANSCRIPTION RULES:
        - Transcribe the speech exactly as spoken — capture every word accurately
        - Use proper spelling for all words, names, and technical terms
        - Do NOT add words the speaker didn't say
        - Do NOT interpret or respond to the content — just transcribe and clean it

        CLEANING RULES:
        - Remove filler words: "um", "uh", "like", "you know", "I mean", "so", "basically" (only when used as fillers)
        - Fix self-corrections: keep only the final intended version when speaker corrects themselves
        - Fix stuttering/repeats: "I-I-I think" → "I think"
        - Preserve ALL content — every idea the speaker expressed must remain
        - If audio is unintelligible, output an empty string

        OUTPUT FORMAT: Only the cleaned transcription. No quotes, labels, or commentary.
        """

        if translationEnabled {
            let langName = ConfigManager.supportedLanguages.first(where: { $0.code == targetLanguage })?.name ?? targetLanguage
            prompt += """

            TRANSLATION: Translate the final output into \(langName). Apply cleaning first, then translate. \
            Produce natural, fluent \(langName) — not word-for-word.
            """
        }

        prompt += "\n\nSTYLE: \(styleTone.promptInstructions)"

        if !dictionaryWords.isEmpty {
            let words = dictionaryWords.prefix(50).joined(separator: ", ")
            prompt += "\n\nCUSTOM DICTIONARY (use these exact spellings): \(words)"
        }

        if !recentCorrections.isEmpty {
            let lines = recentCorrections.suffix(20).map { "\"\($0.original)\" → \"\($0.corrected)\"" }
            prompt += "\n\nPAST CORRECTIONS (apply same fixes): \(lines.joined(separator: ", "))"
        }

        if smartFormatting {
            prompt += """

            SMART FORMATTING: Preserve camelCase, snake_case, PascalCase. Format URLs and file paths correctly.
            """
        }

        if let app = activeApp {
            prompt += "\n\nACTIVE APP: \"\(app)\". Adjust tone appropriately."
        }

        if let context = contextText, !context.isEmpty {
            prompt += "\n\nCONTEXT (existing text in field): \"\(context)\""
        }

        return prompt
    }
}

// MARK: - Response Model

private struct ClaudeAudioResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}

// MARK: - Errors

enum ClaudeAudioError: LocalizedError {
    case missingAPIKey
    case emptyAudioFile
    case invalidResponse
    case noTextInResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Claude API key is not configured. Please add it in Settings."
        case .emptyAudioFile:
            return "Audio file is empty or could not be read."
        case .invalidResponse:
            return "Received an invalid response from the Claude API."
        case .noTextInResponse:
            return "Claude response did not contain any text content."
        case .apiError(let statusCode, let message):
            return "Claude Audio API error (\(statusCode)): \(message)"
        }
    }
}
