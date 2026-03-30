import Foundation
import Speech

/// On-device speech recognition using Apple's SFSpeechRecognizer.
/// Free, fast, no API key required. Works offline on macOS 13+.
final class AppleSpeechClient {
    private let recognizer: SFSpeechRecognizer?

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    /// Transcribes an audio file using Apple's on-device speech recognition.
    /// - Parameter fileURL: Local URL of the audio file to transcribe
    /// - Returns: The transcribed text
    func transcribe(fileURL: URL) async throws -> String {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw AppleSpeechError.recognizerUnavailable
        }

        // Request authorization if needed
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            throw AppleSpeechError.notAuthorized
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        // Prefer on-device recognition for speed and privacy
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = false // Allow fallback to server if on-device unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: AppleSpeechError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let result = result else { return }

                if result.isFinal {
                    let text = result.bestTranscription.formattedString
                    continuation.resume(returning: text)
                }
            }
        }
    }

    /// Check if speech recognition is available on this system.
    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }
}

// MARK: - Errors

enum AppleSpeechError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Apple Speech Recognition is not available on this device."
        case .notAuthorized:
            return "Speech recognition permission was denied. Please enable it in System Settings > Privacy & Security > Speech Recognition."
        case .recognitionFailed(let message):
            return "Speech recognition failed: \(message)"
        }
    }
}
