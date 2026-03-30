import Foundation

/// Client for Deepgram's Nova-2 speech-to-text API.
final class DeepgramClient {
    private let baseURL = "https://api.deepgram.com/v1/listen"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribes an audio file using Deepgram's Nova-2 model.
    func transcribe(
        fileURL: URL,
        language: String? = "en",
        dictionaryWords: [String] = []
    ) async throws -> String {
        guard let apiKey = SharedConfig.shared.deepgramAPIKey, !apiKey.isEmpty else {
            throw DeepgramError.missingAPIKey
        }

        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else {
            throw DeepgramError.emptyAudioFile
        }

        var queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "filler_words", value: "false")
        ]

        if let language = language {
            queryItems.append(URLQueryItem(name: "language", value: language))
        }

        if !dictionaryWords.isEmpty {
            let keywords = dictionaryWords.prefix(50).joined(separator: ",")
            queryItems.append(URLQueryItem(name: "keywords", value: keywords))
        }

        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = queryItems

        let mimeType = fileURL.pathExtension == "m4a" ? "audio/mp4" : "audio/wav"

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = audioData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw DeepgramError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        guard let transcript = result.results?.channels.first?.alternatives.first?.transcript else {
            throw DeepgramError.noTranscriptInResponse
        }

        return transcript
    }
}

// MARK: - Response Models

private struct DeepgramResponse: Decodable {
    let results: Results?

    struct Results: Decodable {
        let channels: [Channel]
    }

    struct Channel: Decodable {
        let alternatives: [Alternative]
    }

    struct Alternative: Decodable {
        let transcript: String
    }
}

// MARK: - Errors

enum DeepgramError: LocalizedError {
    case missingAPIKey
    case emptyAudioFile
    case invalidResponse
    case noTranscriptInResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Deepgram API key is not configured. Please add it in Settings."
        case .emptyAudioFile:
            return "Audio file is empty or could not be read."
        case .invalidResponse:
            return "Received an invalid response from the Deepgram API."
        case .noTranscriptInResponse:
            return "Deepgram response did not contain a transcript."
        case .apiError(let statusCode, let message):
            return "Deepgram API error (\(statusCode)): \(message)"
        }
    }
}
