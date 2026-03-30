import UIKit
import SwiftUI
import Combine
import AVFoundation

/// Main keyboard extension view controller.
/// Provides a standard keyboard layout with an integrated microphone button for voice transcription.
class KeyboardViewController: UIInputViewController {

    // MARK: - State

    private let config = SharedConfig.shared
    private let whisperClient = WhisperClient()
    private let claudeClient = ClaudeClient()
    private let deepgramClient = DeepgramClient()
    private let mistralClient = MistralClient()
    private let audioRecorder = AudioRecorderIOS()
    private lazy var correctionTracker = CorrectionTracker()

    private var hostingController: UIHostingController<KeyboardView>?
    private var keyboardState = KeyboardState()
    private var cancellables = Set<AnyCancellable>()

    /// Text that was last inserted via voice transcription (for correction tracking)
    private var lastInsertedText: String?
    private var lastInsertedTranscript: Transcript?
    /// Snapshot of document text right after insertion (for detecting edits)
    private var postInsertionSnapshot: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Reload shared config (may have changed in main app)
        config.reload()

        let keyboardView = KeyboardView(
            state: keyboardState,
            onKeyTap: { [weak self] key in self?.handleKeyTap(key) },
            onMicTap: { [weak self] in self?.handleMicTap() },
            onBackspace: { [weak self] in self?.handleBackspace() },
            onSpace: { [weak self] in self?.handleSpace() },
            onReturn: { [weak self] in self?.handleReturn() },
            onGlobe: { [weak self] in self?.advanceToNextInputMode() },
            onShift: { [weak self] in self?.handleShift() }
        )

        let hostingVC = UIHostingController(rootView: keyboardView)
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false
        hostingVC.view.backgroundColor = .clear

        addChild(hostingVC)
        view.addSubview(hostingVC.view)
        hostingVC.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.hostingController = hostingVC

        // Monitor audio levels for waveform
        audioRecorder.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.keyboardState.audioLevel = level
                self?.keyboardState.audioLevels.append(level)
                if (self?.keyboardState.audioLevels.count ?? 0) > 30 {
                    self?.keyboardState.audioLevels.removeFirst()
                }
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        config.reload()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)

        // Check for user corrections to previously inserted text
        checkForCorrections()
    }

    // MARK: - Key Handlers

    private func handleKeyTap(_ key: String) {
        let text = keyboardState.isShifted || keyboardState.isCapsLocked
            ? key.uppercased()
            : key.lowercased()
        textDocumentProxy.insertText(text)

        // Auto-unshift after typing one character (unless caps lock)
        if keyboardState.isShifted && !keyboardState.isCapsLocked {
            keyboardState.isShifted = false
        }
    }

    private func handleBackspace() {
        textDocumentProxy.deleteBackward()
    }

    private func handleSpace() {
        textDocumentProxy.insertText(" ")
    }

    private func handleReturn() {
        textDocumentProxy.insertText("\n")
    }

    private func handleShift() {
        if keyboardState.isShifted {
            // Double-tap shift = caps lock
            keyboardState.isCapsLocked = !keyboardState.isCapsLocked
            if !keyboardState.isCapsLocked {
                keyboardState.isShifted = false
            }
        } else {
            keyboardState.isShifted = true
            keyboardState.isCapsLocked = false
        }
    }

    // MARK: - Voice Recording

    private func handleMicTap() {
        if keyboardState.isRecording {
            stopRecordingAndProcess()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !keyboardState.isRecording && !keyboardState.isProcessing else { return }

        // Check microphone permission
        guard AudioRecorderIOS.microphonePermissionGranted else {
            keyboardState.statusMessage = "Open Verbalize app to grant mic access"
            keyboardState.showStatus = true
            clearStatusAfterDelay()
            return
        }

        // Check API keys
        guard config.hasAPIKeys else {
            keyboardState.statusMessage = "Set up API keys in Verbalize app"
            keyboardState.showStatus = true
            clearStatusAfterDelay()
            return
        }

        do {
            let _ = try audioRecorder.startRecording()
            keyboardState.isRecording = true
            keyboardState.audioLevels = []
            keyboardState.statusMessage = "Listening..."
            keyboardState.showStatus = true

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            keyboardState.statusMessage = "Mic error: \(error.localizedDescription)"
            keyboardState.showStatus = true
            clearStatusAfterDelay()
        }
    }

    private func stopRecordingAndProcess() {
        guard keyboardState.isRecording else { return }

        guard let result = audioRecorder.stopRecording() else {
            keyboardState.isRecording = false
            keyboardState.showStatus = false
            return
        }

        keyboardState.isRecording = false
        keyboardState.isProcessing = true
        keyboardState.statusMessage = "Transcribing..."

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Capture context from text field before processing
        let contextText = readContextFromProxy()
        let inputContext = detectInputContext()

        Task { @MainActor in
            await processRecording(url: result.url, duration: result.duration, contextText: contextText, inputContext: inputContext)
        }
    }

    // MARK: - Processing Pipeline

    @MainActor
    private func processRecording(url: URL, duration: TimeInterval, contextText: String?, inputContext: String? = nil) async {
        defer {
            audioRecorder.cleanupTempFile(url: url)
        }

        do {
            // Step 1: Transcribe with selected engine
            keyboardState.statusMessage = "Transcribing..."
            let rawText: String
            switch config.transcriptionEngine {
            case .whisperMini:
                rawText = try await whisperClient.transcribe(
                    fileURL: url,
                    model: "gpt-4o-mini-transcribe",
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords,
                    contextHint: contextText
                )
            case .whisperFull:
                rawText = try await whisperClient.transcribe(
                    fileURL: url,
                    model: "gpt-4o-transcribe",
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords,
                    contextHint: contextText
                )
            case .deepgram:
                rawText = try await deepgramClient.transcribe(
                    fileURL: url,
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords
                )
            case .mistral:
                rawText = try await mistralClient.transcribe(
                    fileURL: url,
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords
                )
            }

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                keyboardState.isProcessing = false
                keyboardState.statusMessage = "No speech detected"
                clearStatusAfterDelay()
                return
            }

            // Step 2: Clean transcript
            let cleanedText: String
            let needsAICleanup = config.useAICleanup || config.translationEnabled
            if needsAICleanup {
                keyboardState.statusMessage = config.translationEnabled ? "Translating..." : "Cleaning..."
                cleanedText = try await claudeClient.cleanTranscription(
                    rawText,
                    dictionaryWords: config.dictionaryWords,
                    styleTone: config.defaultStyleTone,
                    contextText: contextText,
                    smartFormatting: config.smartFormatting,
                    translationEnabled: config.translationEnabled,
                    targetLanguage: config.targetLanguage,
                    recentCorrections: config.recentCorrections,
                    inputContextHint: inputContext
                )
            } else {
                cleanedText = ProgrammaticCleaner.clean(rawText, styleTone: config.defaultStyleTone)
            }

            // Step 3: Insert text into the active field (with space prepend)
            let beforeContext = textDocumentProxy.documentContextBeforeInput ?? ""
            if let lastChar = beforeContext.last, !lastChar.isWhitespace && !lastChar.isNewline {
                textDocumentProxy.insertText(" " + cleanedText)
            } else {
                textDocumentProxy.insertText(cleanedText)
            }

            // Step 4: Save transcript
            let transcript = Transcript(
                originalText: rawText,
                cleanedText: cleanedText,
                durationSeconds: duration
            )
            try? TranscriptDatabase.shared.save(transcript)

            // Step 5: Track for corrections
            lastInsertedText = cleanedText
            lastInsertedTranscript = transcript
            postInsertionSnapshot = readFullTextFromProxy()

            keyboardState.isProcessing = false
            keyboardState.statusMessage = "Done"

            let notificationGenerator = UINotificationFeedbackGenerator()
            notificationGenerator.notificationOccurred(.success)

            clearStatusAfterDelay()

        } catch {
            keyboardState.isProcessing = false
            keyboardState.statusMessage = "Error: \(error.localizedDescription)"
            clearStatusAfterDelay(seconds: 4)
        }
    }

    // MARK: - Correction Tracking

    private func checkForCorrections() {
        guard let insertedText = lastInsertedText,
              let transcript = lastInsertedTranscript,
              let snapshot = postInsertionSnapshot else { return }

        let currentText = readFullTextFromProxy()
        guard let currentText, currentText != snapshot else { return }

        // Try to find the edited version of the inserted text
        // by looking at the difference between the snapshot and current text
        if let editedRegion = findEditedRegion(original: snapshot, current: currentText, insertedText: insertedText) {
            correctionTracker.processCorrections(
                injectedText: insertedText,
                editedText: editedRegion,
                transcript: transcript
            )

            // Clear tracking (only track once per insertion)
            lastInsertedText = nil
            lastInsertedTranscript = nil
            postInsertionSnapshot = nil
        }
    }

    private func findEditedRegion(original: String, current: String, insertedText: String) -> String? {
        // Find where the inserted text was in the original
        guard let range = original.range(of: insertedText) else { return nil }

        let startOffset = original.distance(from: original.startIndex, to: range.lowerBound)
        let endOffset = original.distance(from: original.startIndex, to: range.upperBound)

        let lengthDelta = current.count - original.count
        let adjustedEnd = endOffset + lengthDelta

        guard startOffset >= 0, startOffset < current.count, adjustedEnd > startOffset, adjustedEnd <= current.count else {
            return nil
        }

        let startIdx = current.index(current.startIndex, offsetBy: startOffset)
        let endIdx = current.index(current.startIndex, offsetBy: adjustedEnd)
        let editedText = String(current[startIdx..<endIdx])

        // Only return if the text actually changed
        return editedText != insertedText ? editedText : nil
    }

    // MARK: - Input Context Detection

    /// Detects the type of text field from keyboardType and textContentType,
    /// providing a hint to Claude about how to format the output.
    /// This is the iOS equivalent of the macOS "active app" detection.
    private func detectInputContext() -> String? {
        let proxy = textDocumentProxy

        // Check textContentType first (more specific)
        if let contentType = proxy.textContentType {
            switch contentType {
            case .emailAddress:
                return "Email address field — output should be a valid email address."
            case .URL:
                return "URL field — output should be a properly formatted URL."
            case .telephoneNumber:
                return "Phone number field — output should be a phone number."
            case .fullStreetAddress, .streetAddressLine1, .streetAddressLine2,
                 .city, .addressState, .postalCode, .countryName:
                return "Address field — output should be a properly formatted address component."
            case .name, .givenName, .familyName, .namePrefix, .nameSuffix, .middleName:
                return "Name field — output should be a person's name, properly capitalized."
            case .organizationName:
                return "Organization name field — output should be a company or organization name."
            case .jobTitle:
                return "Job title field — output should be a professional title."
            default:
                break
            }
        }

        // Fall back to keyboardType
        switch proxy.keyboardType ?? .default {
        case .emailAddress:
            return "This appears to be an email field — use proper email formatting."
        case .URL, .webSearch:
            return "This appears to be a URL or search field — format accordingly."
        case .numberPad, .phonePad, .decimalPad, .numbersAndPunctuation:
            return "This is a numeric input field."
        default:
            return nil
        }
    }

    // MARK: - Text Proxy Helpers

    /// Read surrounding context from the text field (last ~200 characters before cursor)
    private func readContextFromProxy() -> String? {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        if before.isEmpty { return nil }
        return String(before.suffix(200))
    }

    /// Read the full text from the text field (approximation via document proxy)
    private func readFullTextFromProxy() -> String? {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let full = before + after
        return full.isEmpty ? nil : full
    }

    // MARK: - Status Helpers

    private func clearStatusAfterDelay(seconds: TimeInterval = 2) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !keyboardState.isRecording && !keyboardState.isProcessing {
                keyboardState.showStatus = false
            }
        }
    }
}

// MARK: - Keyboard State

class KeyboardState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var isShifted = false
    @Published var isCapsLocked = false
    @Published var showNumbers = false
    @Published var showSymbols = false
    @Published var statusMessage = ""
    @Published var showStatus = false
    @Published var audioLevel: Float = 0
    @Published var audioLevels: [Float] = []
}
