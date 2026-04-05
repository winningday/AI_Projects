import Foundation
import AVFoundation

/// Client for Cohere's Transcribe speech-to-text API.
/// Apache 2.0 open-source model, #1 on HuggingFace Open ASR Leaderboard (5.42% WER).
/// API does not accept m4a — converts to WAV automatically before sending.
final class CohereTranscribeClient {
    private let baseURL = "https://api.cohere.com/v2/audio/transcriptions"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribes an audio file using Cohere Transcribe.
    func transcribe(
        fileURL: URL,
        language: String? = "en",
        dictionaryWords: [String] = []
    ) async throws -> String {
        guard let apiKey = SharedConfig.shared.cohereAPIKey, !apiKey.isEmpty else {
            throw CohereError.missingAPIKey
        }

        // Cohere only accepts: flac, mp3, mpeg, mpga, ogg, wav — not m4a/mp4
        // Convert m4a to wav if needed (sub-100ms for typical recordings)
        let (audioData, filename, mimeType) = try await prepareAudio(fileURL: fileURL)

        guard !audioData.isEmpty else {
            throw CohereError.emptyAudioFile
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
        body.appendCohereMultipart(boundary: boundary, name: "model", value: "cohere-transcribe-03-2026")

        // Language field (if specified)
        if let language = language {
            body.appendCohereMultipart(boundary: boundary, name: "language", value: language)
        }

        // Audio file
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
            throw CohereError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CohereError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let result = try JSONDecoder().decode(CohereTranscriptionResponse.self, from: data)
        return result.text
    }

    // MARK: - Audio Conversion

    /// Prepares audio for the Cohere API. If the file is m4a, converts to WAV.
    private func prepareAudio(fileURL: URL) async throws -> (Data, String, String) {
        let ext = fileURL.pathExtension.lowercased()

        if ext == "wav" {
            let data = try Data(contentsOf: fileURL)
            return (data, fileURL.lastPathComponent, "audio/wav")
        }
        if ext == "flac" {
            let data = try Data(contentsOf: fileURL)
            return (data, fileURL.lastPathComponent, "audio/flac")
        }
        if ext == "mp3" {
            let data = try Data(contentsOf: fileURL)
            return (data, fileURL.lastPathComponent, "audio/mpeg")
        }
        if ext == "ogg" {
            let data = try Data(contentsOf: fileURL)
            return (data, fileURL.lastPathComponent, "audio/ogg")
        }

        // m4a/mp4/aac → convert to WAV (16kHz mono PCM, matching recorder settings)
        let wavURL = fileURL.deletingPathExtension().appendingPathExtension("wav")
        try await convertToWAV(source: fileURL, destination: wavURL)
        let data = try Data(contentsOf: wavURL)
        try? FileManager.default.removeItem(at: wavURL)
        let wavFilename = fileURL.deletingPathExtension().lastPathComponent + ".wav"
        return (data, wavFilename, "audio/wav")
    }

    /// Converts an audio file to 16kHz mono 16-bit PCM WAV using AVFoundation.
    private func convertToWAV(source: URL, destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let sourceFile = try AVAudioFile(forReading: source)

                let format = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: 16000,
                    channels: 1,
                    interleaved: true
                )!

                let destFile = try AVAudioFile(
                    forWriting: destination,
                    settings: format.settings,
                    commonFormat: .pcmFormatInt16,
                    interleaved: true
                )

                let converter = AVAudioConverter(from: sourceFile.processingFormat, to: format)!
                let bufferSize: AVAudioFrameCount = 4096
                let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!

                while true {
                    let status = converter.convert(to: outputBuffer, error: nil) { inNumPackets, outStatus in
                        let inputBuffer = AVAudioPCMBuffer(
                            pcmFormat: sourceFile.processingFormat,
                            frameCapacity: min(inNumPackets, 4096)
                        )!
                        do {
                            try sourceFile.read(into: inputBuffer)
                            if inputBuffer.frameLength == 0 {
                                outStatus.pointee = .endOfStream
                            } else {
                                outStatus.pointee = .haveData
                            }
                        } catch {
                            outStatus.pointee = .endOfStream
                        }
                        return inputBuffer
                    }

                    if outputBuffer.frameLength == 0 || status == .endOfStream || status == .error {
                        break
                    }

                    try destFile.write(from: outputBuffer)
                }

                continuation.resume()
            } catch {
                continuation.resume(throwing: CohereError.audioConversionFailed(error.localizedDescription))
            }
        }
    }
}

// MARK: - Response Model

private struct CohereTranscriptionResponse: Decodable {
    let text: String
}

// MARK: - Multipart Helper

private extension Data {
    mutating func appendCohereMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}

// MARK: - Errors

enum CohereError: LocalizedError {
    case missingAPIKey
    case emptyAudioFile
    case invalidResponse
    case audioConversionFailed(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Cohere API key is not configured. Please add it in Settings."
        case .emptyAudioFile:
            return "Audio file is empty or could not be read."
        case .invalidResponse:
            return "Received an invalid response from the Cohere API."
        case .audioConversionFailed(let reason):
            return "Failed to convert audio to WAV: \(reason)"
        case .apiError(let statusCode, let message):
            return "Cohere API error (\(statusCode)): \(message)"
        }
    }
}
