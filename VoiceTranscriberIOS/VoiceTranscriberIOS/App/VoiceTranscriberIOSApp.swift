import SwiftUI
import Combine

// MARK: - Navigation

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case stats = "Stats"
    case dictionary = "Dictionary"
    case style = "Style"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .stats: return "chart.bar"
        case .dictionary: return "character.book.closed"
        case .style: return "textformat"
        case .settings: return "gear"
        }
    }
}

// MARK: - App State (Orchestrator)

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var lastTranscript: Transcript?
    @Published var lastError: String?
    @Published var statusMessage: String = "Ready"
    @Published var selectedTab: AppTab = .home
    @Published var totalWordsTranscribed: Int = 0
    @Published var totalRecordingSeconds: Double = 0

    let audioRecorder = AudioRecorderIOS()
    let levelMonitor: AudioLevelMonitor
    let database = TranscriptDatabase.shared
    let config = SharedConfig.shared

    private let whisperClient = WhisperClient()
    private let claudeClient = ClaudeClient()
    private let openAICleanupClient = OpenAICleanupClient()
    private let deepgramClient = DeepgramClient()
    private let mistralClient = MistralClient()
    private let cohereClient = CohereTranscribeClient()
    private lazy var correctionTracker = CorrectionTracker(config: config, database: database)
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.levelMonitor = AudioLevelMonitor(recorder: audioRecorder)
        computeTotalWords()
        computeTotalRecordingTime()

        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func computeTotalWords() {
        totalWordsTranscribed = database.transcripts.reduce(0) {
            $0 + $1.cleanedText.split(separator: " ").count
        }
    }

    private func computeTotalRecordingTime() {
        totalRecordingSeconds = database.transcripts.reduce(0.0) {
            $0 + $1.durationSeconds
        }
    }

    var wordsPerMinute: Int {
        guard totalRecordingSeconds > 5 else { return 0 }
        return Int(Double(totalWordsTranscribed) / (totalRecordingSeconds / 60.0))
    }

    var speedMultiplier: Double {
        guard config.typingSpeed > 0, wordsPerMinute > 0 else { return 0 }
        return Double(wordsPerMinute) / Double(config.typingSpeed)
    }

    var minutesSaved: Double {
        guard config.typingSpeed > 0, totalWordsTranscribed > 0 else { return 0 }
        let typingMinutes = Double(totalWordsTranscribed) / Double(config.typingSpeed)
        let voiceMinutes = totalRecordingSeconds / 60.0
        return max(0, typingMinutes - voiceMinutes)
    }

    var todayWordCount: Int {
        database.transcripts
            .filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.cleanedText.split(separator: " ").count }
    }

    var todayTranscriptCount: Int {
        database.transcripts.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    var weeklyWordCounts: [(date: Date, words: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let words = database.transcripts
                .filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
                .reduce(0) { $0 + $1.cleanedText.split(separator: " ").count }
            return (date: date, words: words)
        }
    }

    // MARK: - Recording Flow (for in-app recording)

    func startRecording() {
        guard !isRecording && !isProcessing else { return }

        Task {
            let granted = await AudioRecorderIOS.requestMicrophonePermission()
            guard granted else {
                lastError = "Microphone permission denied."
                statusMessage = "Mic access needed"
                return
            }

            do {
                let _ = try audioRecorder.startRecording()
                isRecording = true
                lastError = nil
                statusMessage = "Recording..."

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            } catch {
                lastError = "Failed to start recording: \(error.localizedDescription)"
                statusMessage = "Error"
            }
        }
    }

    func stopRecordingAndProcess() {
        guard isRecording else { return }

        guard let result = audioRecorder.stopRecording() else {
            isRecording = false
            statusMessage = "Ready"
            return
        }

        isRecording = false
        isProcessing = true
        statusMessage = "Processing..."

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        Task {
            await processRecording(url: result.url, duration: result.duration)
        }
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        isRecording = false
        isProcessing = false
        statusMessage = "Ready"
        levelMonitor.reset()
    }

    // MARK: - Processing Pipeline

    private func processRecording(url: URL, duration: TimeInterval) async {
        defer {
            audioRecorder.cleanupTempFile(url: url)
        }

        let pipelineStart = CFAbsoluteTimeGetCurrent()

        do {
            // Step 1: Transcribe with selected engine
            statusMessage = "Transcribing..."
            let transcribeStart = CFAbsoluteTimeGetCurrent()
            let rawText: String
            switch config.transcriptionEngine {
            case .whisperMini:
                rawText = try await whisperClient.transcribe(
                    fileURL: url,
                    model: "gpt-4o-mini-transcribe",
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords
                )
            case .whisperFull:
                rawText = try await whisperClient.transcribe(
                    fileURL: url,
                    model: "gpt-4o-transcribe",
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords
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
            case .cohereTranscribe:
                rawText = try await cohereClient.transcribe(
                    fileURL: url,
                    language: config.translationEnabled ? nil : "en",
                    dictionaryWords: config.dictionaryWords
                )
            }
            let transcribeMs = Int((CFAbsoluteTimeGetCurrent() - transcribeStart) * 1000)
            let sttModel: String = {
                switch config.transcriptionEngine {
                case .whisperMini: return "gpt-4o-mini-transcribe"
                case .whisperFull: return "gpt-4o-transcribe"
                case .deepgram: return "nova-2"
                case .mistral: return "voxtral-mini"
                case .cohereTranscribe: return "cohere-transcribe-03-2026"
                }
            }()

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                isProcessing = false
                statusMessage = "Ready"
                lastError = "No speech detected."
                PipelineLogger.shared.log(engine: config.transcriptionEngine.displayName, sttModel: sttModel, transcribeMs: transcribeMs, cleanupMs: 0, cleanupMethod: "none", audioDuration: duration, wordCount: 0, error: "No speech detected")
                return
            }

            // Step 2: Clean transcript
            let cleanedText: String
            let needsAICleanup = config.useAICleanup || config.translationEnabled
            let cleanupStart = CFAbsoluteTimeGetCurrent()
            let cleanupMethod: String
            let cleanupModelName: String
            if needsAICleanup {
                statusMessage = config.translationEnabled ? "Translating..." : "Cleaning up..."
                switch config.cleanupModel {
                case .gpt4oMini:
                    cleanedText = try await openAICleanupClient.cleanTranscription(
                        rawText,
                        dictionaryWords: config.dictionaryWords,
                        styleTone: config.defaultStyleTone,
                        smartFormatting: config.smartFormatting,
                        translationEnabled: config.translationEnabled,
                        targetLanguage: config.targetLanguage,
                        recentCorrections: config.recentCorrections
                    )
                    cleanupMethod = "openai"
                    cleanupModelName = "gpt-4o-mini"
                case .claudeHaiku:
                    cleanedText = try await claudeClient.cleanTranscription(
                        rawText,
                        dictionaryWords: config.dictionaryWords,
                        styleTone: config.defaultStyleTone,
                        smartFormatting: config.smartFormatting,
                        translationEnabled: config.translationEnabled,
                        targetLanguage: config.targetLanguage,
                        recentCorrections: config.recentCorrections
                    )
                    cleanupMethod = "claude"
                    cleanupModelName = "claude-haiku-4-5"
                }
            } else {
                cleanedText = ProgrammaticCleaner.clean(rawText, styleTone: config.defaultStyleTone)
                cleanupMethod = "programmatic"
                cleanupModelName = "none"
            }
            let cleanupMs = Int((CFAbsoluteTimeGetCurrent() - cleanupStart) * 1000)
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000)
            let wordCount = cleanedText.split(separator: " ").count
            PipelineLogger.shared.log(engine: config.transcriptionEngine.displayName, sttModel: sttModel, transcribeMs: transcribeMs, cleanupMs: cleanupMs, cleanupMethod: cleanupMethod, cleanupModel: cleanupModelName, audioDuration: duration, wordCount: wordCount, totalMs: totalMs)

            let transcript = Transcript(
                originalText: rawText,
                cleanedText: cleanedText,
                durationSeconds: duration
            )
            try database.save(transcript)

            // Copy to clipboard for easy pasting
            UIPasteboard.general.string = cleanedText

            lastTranscript = transcript
            isProcessing = false
            statusMessage = "Copied to clipboard"
            lastError = nil
            computeTotalWords()
            computeTotalRecordingTime()

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Reset status after a delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if statusMessage == "Copied to clipboard" {
                statusMessage = "Ready"
            }

        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000)
            PipelineLogger.shared.log(engine: config.transcriptionEngine.displayName, sttModel: "", transcribeMs: 0, cleanupMs: 0, cleanupMethod: "error", audioDuration: duration, wordCount: 0, totalMs: totalMs, error: error.localizedDescription)
            isProcessing = false
            statusMessage = "Error"
            lastError = error.localizedDescription
        }
    }
}

// MARK: - App Entry Point

@main
struct VerbalizeIOSApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
    }
}

// MARK: - Content View (Root)

struct ContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.config.hasCompletedOnboarding {
                MainTabView(appState: appState)
            } else {
                OnboardingView(config: appState.config) {
                    appState.config.hasCompletedOnboarding = true
                }
            }
        }
    }
}
