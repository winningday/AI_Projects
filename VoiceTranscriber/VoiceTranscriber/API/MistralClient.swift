import Foundation

/// Client for Mistral's Voxtral speech-to-text API.
/// Uses Voxtral Mini Transcribe — fast, accurate, $0.003/min.
final class MistralClient {
    private let baseURL = "https://api.mistral.ai/v1/audio/transcriptions"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribes an audio file using Mistral's Voxtral Mini Transcribe model.
    func transcribe(
        fileURL: URL,
        language: String? = "en",
        dictionaryWords: [String] = []
    ) async throws -> String {
        guard let apiKey = ConfigManager.shared.mistralAPIKey, !apiKey.isEmpty else {
            throw MistralError.missingAPIKey
        }

        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else {
            throw MistralError.emptyAudioFile
        }

        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Build multipart body
        var body = Data()

        // Model field
        body.appendMultipart(boundary: boundary, name: "model", value: "voxtral-mini-latest")

        // Language field (if specified)
        if let language = language {
            body.appendMultipart(boundary: boundary, name: "language", value: language)
        }

        // Context bias (dictionary words for custom vocabulary)
        if !dictionaryWords.isEmpty {
            let biasString = dictionaryWords.prefix(100).joined(separator: ",")
            body.appendMultipart(boundary: boundary, name: "context_bias", value: biasString)
        }

        // Audio file
        let mimeType = fileURL.pathExtension == "m4a" ? "audio/mp4" : "audio/wav"
        let filename = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MistralError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(MistralTranscriptionResponse.self, from: data)
        return result.text
    }
}

// MARK: - Response Model

private struct MistralTranscriptionResponse: Decodable {
    let text: String
}

// MARK: - Multipart Helper

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}

// MARK: - Errors

enum MistralError: LocalizedError {
    case missingAPIKey
    case emptyAudioFile
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Mistral API key is not configured. Please add it in Settings."
        case .emptyAudioFile:
            return "Audio file is empty or could not be read."
        case .invalidResponse:
            return "Received an invalid response from the Mistral API."
        case .apiError(let statusCode, let message):
            return "Mistral API error (\(statusCode)): \(message)"
        }
    }
}
