import Foundation

/// Client for the Anthropic Claude API, used for cleaning up raw transcriptions.
/// Supports dictionary words, style profiles, context awareness, smart formatting, and translation.
final class ClaudeClient {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session: URLSession
    private let modelID = "claude-haiku-4-5-20251001"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Cleans up a raw voice transcription using Claude Haiku.
    func cleanTranscription(
        _ rawText: String,
        dictionaryWords: [String] = [],
        styleTone: StyleTone = .formal,
        activeApp: String? = nil,
        contextText: String? = nil,
        smartFormatting: Bool = true,
        translationEnabled: Bool = false,
        targetLanguage: String = "en"
    ) async throws -> String {
        guard let apiKey = ConfigManager.shared.claudeAPIKey, !apiKey.isEmpty else {
            throw ClaudeError.missingAPIKey
        }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // For very short text (< 5 words), skip Claude and return as-is with basic cleanup
        // (unless translation is enabled, then always process)
        let wordCount = trimmed.split(separator: " ").count
        if wordCount <= 3 && !translationEnabled {
            return trimmed
        }

        let systemPrompt = buildSystemPrompt(
            dictionaryWords: dictionaryWords,
            styleTone: styleTone,
            activeApp: activeApp,
            contextText: contextText,
            smartFormatting: smartFormatting,
            translationEnabled: translationEnabled,
            targetLanguage: targetLanguage
        )

        let requestBody = ClaudeRequestWithSystem(
            model: modelID,
            max_tokens: 4096,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: trimmed)
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

    // MARK: - System Prompt Builder

    private func buildSystemPrompt(
        dictionaryWords: [String],
        styleTone: StyleTone,
        activeApp: String?,
        contextText: String?,
        smartFormatting: Bool,
        translationEnabled: Bool,
        targetLanguage: String
    ) -> String {
        var prompt = """
        You are a real-time voice transcription processor. You receive raw speech-to-text output and return clean, polished text ready to be inserted into a document or message field.

        CORE RULES (always apply):
        - Remove filler words: "um", "uh", "like", "you know", "I mean", "so", "basically" (only when used as fillers, not when meaningful)
        - Fix self-corrections: keep only the final intended version. "I want to go to the store, no wait, the park" → "I want to go to the park"
        - Fix stuttering/repeats: "I-I-I think" → "I think"
        - Fix obvious transcription errors (homophones, garbled words) using context
        - Keep contractions natural
        - Detect numbered lists from speech: "first apples second bananas" → "1. Apples\\n2. Bananas"
        - If the text is very short or a single word/phrase, return it with minimal changes
        - If the input contains NO actual speech content (e.g. silence, noise, or the transcription service returned placeholder text like "I'm listening" or "tell me what you want"), return EXACTLY an empty string — output absolutely nothing
        - NEVER generate conversational responses, instructions, or offers to help. You are NOT a chatbot. You are a text processor. If there's nothing to process, output nothing.
        - Output ONLY the cleaned text. No explanations, no markers, no quotes.
        """

        // Translation
        if translationEnabled {
            let langName = ConfigManager.supportedLanguages.first(where: { $0.code == targetLanguage })?.name ?? targetLanguage
            prompt += """

            TRANSLATION MODE (ENABLED):
            - Auto-detect the language of the input speech.
            - Translate the final cleaned output into \(langName) (\(targetLanguage)).
            - The input may be in ANY language — Chinese, Spanish, French, Arabic, etc.
            - Produce natural, fluent \(langName) output — not a word-for-word literal translation.
            - Apply all cleaning rules FIRST, then translate.
            - If the input is already in \(langName), just clean it without translation.
            """
        }

        // Style instructions
        prompt += "\n\nSTYLE: \(styleTone.promptInstructions)"

        // Dictionary words
        if !dictionaryWords.isEmpty {
            let words = dictionaryWords.prefix(50).joined(separator: ", ")
            prompt += """

            \nCUSTOM DICTIONARY (use these exact spellings when you hear these words or similar-sounding words):
            \(words)
            """
        }

        // Smart formatting
        if smartFormatting {
            prompt += """

            \nSMART FORMATTING:
            - If the user appears to be dictating code or technical content (function names, variable names, class names), preserve technical formatting: camelCase, snake_case, PascalCase as appropriate
            - URLs, file paths, and technical terms should be formatted correctly
            - Code snippets should be on their own lines
            """
        }

        // Context awareness
        if let app = activeApp {
            prompt += "\n\nACTIVE APP: The user is typing in \"\(app)\". Adjust tone appropriately."

            let appLower = app.lowercased()
            if appLower.contains("slack") || appLower.contains("teams") || appLower.contains("discord") {
                prompt += " This is a work messenger — keep it professional but concise."
            } else if appLower.contains("message") || appLower.contains("whatsapp") || appLower.contains("telegram") {
                prompt += " This is a personal messenger — keep it natural and conversational."
            } else if appLower.contains("mail") || appLower.contains("outlook") || appLower.contains("gmail") {
                prompt += " This is email — use proper email formatting."
            } else if appLower.contains("xcode") || appLower.contains("vs code") || appLower.contains("visual studio") || appLower.contains("cursor") || appLower.contains("terminal") {
                prompt += " This is a code editor — preserve technical terms, function names, and code formatting precisely."
            }
        }

        if let context = contextText, !context.isEmpty {
            prompt += """

            \nCONTEXT (text already in the field — use for spelling names and understanding topic):
            \"\(context)\"
            """
        }

        return prompt
    }
}

// MARK: - Request/Response Models

private struct ClaudeRequestWithSystem: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
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
