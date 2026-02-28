import Foundation

/// Client for the OpenAI Whisper API for speech-to-text transcription.
final class WhisperClient {
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribes an audio file using OpenAI's Whisper API.
    /// - Parameters:
    ///   - fileURL: Local URL of the audio file to transcribe
    ///   - language: Optional language hint (ISO 639-1 code, e.g. "en")
    /// - Returns: The transcribed text
    func transcribe(fileURL: URL, language: String? = "en") async throws -> String {
        guard let apiKey = ConfigManager.shared.openAIAPIKey, !apiKey.isEmpty else {
            throw WhisperError.missingAPIKey
        }

        // Read audio file data
        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else {
            throw WhisperError.emptyAudioFile
        }

        // Build multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()

        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: "whisper-1")

        // Language field (optional)
        if let language = language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // Response format
        body.appendMultipart(boundary: boundary, name: "response_format", value: "json")

        // Audio file
        let filename = fileURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/mpeg"
        body.appendMultipart(boundary: boundary, name: "file", filename: filename, mimeType: mimeType, data: audioData)

        // Closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Execute request
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        // Parse response
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return result.text
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
