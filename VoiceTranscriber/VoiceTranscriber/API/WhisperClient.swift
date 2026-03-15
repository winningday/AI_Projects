import Foundation

/// Client for the OpenAI Whisper API for speech-to-text transcription.
/// Uses gpt-4o-mini-transcribe for faster, more accurate results.
final class WhisperClient {
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribes an audio file using OpenAI's transcription API.
    /// - Parameters:
    ///   - fileURL: Local URL of the audio file to transcribe
    ///   - language: Optional language hint (ISO 639-1 code, e.g. "en")
    ///   - dictionaryWords: Custom words/names to help the model spell correctly
    ///   - contextHint: Surrounding text from the active field for context
    /// - Returns: The transcribed text
    func transcribe(
        fileURL: URL,
        language: String? = "en",
        dictionaryWords: [String] = [],
        contextHint: String? = nil
    ) async throws -> String {
        guard let apiKey = ConfigManager.shared.openAIAPIKey, !apiKey.isEmpty else {
            throw WhisperError.missingAPIKey
        }

        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else {
            throw WhisperError.emptyAudioFile
        }

        // Use gpt-4o-mini-transcribe for speed + accuracy (falls back to whisper-1 on error)
        let model = "gpt-4o-mini-transcribe"

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        // Model
        body.appendMultipart(boundary: boundary, name: "model", value: model)

        // Language hint
        if let language = language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        // Prompt: dictionary words + context help Whisper spell names correctly
        let prompt = buildPrompt(dictionaryWords: dictionaryWords, contextHint: contextHint)
        if !prompt.isEmpty {
            body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        }

        // Audio file
        let filename = fileURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/mpeg"
        body.appendMultipart(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: audioData)

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        // If gpt-4o-mini-transcribe fails (e.g., not available), retry with whisper-1
        if httpResponse.statusCode != 200 && model != "whisper-1" {
            return try await transcribeWithFallback(
                fileURL: fileURL,
                audioData: audioData,
                language: language,
                prompt: prompt
            )
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }

    /// Fallback transcription using whisper-1 model
    private func transcribeWithFallback(
        fileURL: URL,
        audioData: Data,
        language: String?,
        prompt: String
    ) async throws -> String {
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(ConfigManager.shared.openAIAPIKey!)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")
        if let language = language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")
        if !prompt.isEmpty {
            body.appendMultipart(boundary: boundary, name: "prompt", value: prompt)
        }

        let filename = fileURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/mpeg"
        body.appendMultipart(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: audioData)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.apiError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: errorBody
            )
        }

        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
    }

    /// Build a prompt string with dictionary words and context.
    /// Whisper uses this to bias toward known spellings of names, terms, etc.
    private func buildPrompt(dictionaryWords: [String], contextHint: String?) -> String {
        var parts: [String] = []

        if !dictionaryWords.isEmpty {
            parts.append(dictionaryWords.joined(separator: ", "))
        }

        if let context = contextHint, !context.isEmpty {
            parts.append(context)
        }

        return parts.joined(separator: ". ")
    }
}

// MARK: - Response Models

private struct WhisperResponse: Decodable {
    let text: String
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case missingAPIKey
    case emptyAudioFile
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Please add it in Settings."
        case .emptyAudioFile:
            return "Audio file is empty or could not be read."
        case .invalidResponse:
            return "Received an invalid response from the Whisper API."
        case .apiError(let statusCode, let message):
            return "Whisper API error (\(statusCode)): \(message)"
        }
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
