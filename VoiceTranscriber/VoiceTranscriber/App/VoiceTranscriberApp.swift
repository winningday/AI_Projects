import SwiftUI
import AppKit
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
    var hasLaunched = false
    @Published var totalRecordingSeconds: Double = 0

    let audioRecorder = AudioRecorder()
    let levelMonitor: AudioLevelMonitor
    let hotkeyManager = HotKeyManager()
    let database = TranscriptDatabase.shared
    let config = ConfigManager.shared

    private let whisperClient = WhisperClient()
    private let claudeClient = ClaudeClient()
    private let deepgramClient = DeepgramClient()
    private let appleSpeechClient = AppleSpeechClient()
    private let recordingWindow = RecordingWindowController()
    private lazy var correctionTracker = CorrectionTracker(config: config, database: database)
    private var cancellables = Set<AnyCancellable>()
    /// Captured before recording starts for context-aware transcription
    private var capturedContext: String?
    private var capturedAppName: String?

    init() {
        self.levelMonitor = AudioLevelMonitor(recorder: audioRecorder)
        setupHotkeyCallbacks()
        computeTotalWords()
        computeTotalRecordingTime()

        // Forward nested ConfigManager changes so SwiftUI views update properly.
        // Without this, changes to config.translationEnabled etc. don't trigger
        // view refreshes in views that observe AppState (like MenuBarView).
        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Listen for dock icon clicks to reopen main window
        NotificationCenter.default.addObserver(forName: .showMainWindow, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.showMainWindow()
            }
        }
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

    /// Voice dictation WPM (words produced per minute of recording)
    var wordsPerMinute: Int {
        guard totalRecordingSeconds > 5 else { return 0 }
        return Int(Double(totalWordsTranscribed) / (totalRecordingSeconds / 60.0))
    }

    /// Speed multiplier vs typing (e.g. 2.5x faster)
    var speedMultiplier: Double {
        guard config.typingSpeed > 0, wordsPerMinute > 0 else { return 0 }
        return Double(wordsPerMinute) / Double(config.typingSpeed)
    }

    /// Minutes saved compared to typing the same words
    var minutesSaved: Double {
        guard config.typingSpeed > 0, totalWordsTranscribed > 0 else { return 0 }
        let typingMinutes = Double(totalWordsTranscribed) / Double(config.typingSpeed)
        let voiceMinutes = totalRecordingSeconds / 60.0
        return max(0, typingMinutes - voiceMinutes)
    }

    /// Average words per transcript
    var averageWordsPerTranscript: Int {
        let count = database.transcripts.count
        guard count > 0 else { return 0 }
        return totalWordsTranscribed / count
    }

    /// Today's word count
    var todayWordCount: Int {
        database.transcripts
            .filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0) { $0 + $1.cleanedText.split(separator: " ").count }
    }

    /// Today's transcript count
    var todayTranscriptCount: Int {
        database.transcripts.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    /// Last 7 days of daily word counts (for chart)
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

    // MARK: - Hotkey Callbacks

    private func setupHotkeyCallbacks() {
        hotkeyManager.onHotkeyDown = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }

        hotkeyManager.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndProcess()
            }
        }
    }

    // MARK: - Recording Flow

    func startRecording() {
        guard !isRecording && !isProcessing else { return }

        // Cancel any pending correction check from previous transcription
        correctionTracker.cancelPending()

        // Capture context BEFORE recording (while user is in their app)
        if config.contextAwareness {
            capturedContext = TextInjector.readContextFromActiveField()
            capturedAppName = TextInjector.activeAppName()
        } else {
            capturedContext = nil
            capturedAppName = TextInjector.activeAppName()
        }

        AudioRecorder.requestMicrophonePermission { [weak self] granted in
            guard granted else {
                Task { @MainActor [weak self] in
                    self?.lastError = "Microphone permission denied."
                    self?.statusMessage = "Mic access needed"
                }
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                do {
                    let _ = try self.audioRecorder.startRecording()
                    self.isRecording = true
                    self.lastError = nil
                    self.statusMessage = "Recording..."

                    self.recordingWindow.show(recorder: self.audioRecorder, levelMonitor: self.levelMonitor)

                    if self.config.useHapticFeedback {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                } catch {
                    self.lastError = "Failed to start recording: \(error.localizedDescription)"
                    self.statusMessage = "Error"
                }
            }
        }
    }

    func stopRecordingAndProcess() {
        guard isRecording else { return }

        guard let result = audioRecorder.stopRecording() else {
            isRecording = false
            statusMessage = "Ready"
            recordingWindow.hide()
            return
        }

        isRecording = false
        isProcessing = true
        statusMessage = "Processing..."
        recordingWindow.hide()

        if config.useHapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }

        let context = capturedContext
        let appName = capturedAppName

        Task {
            await processRecording(url: result.url, duration: result.duration, contextText: context, activeApp: appName)
        }
    }

    func cancelRecording() {
        audioRecorder.cancelRecording()
        isRecording = false
        isProcessing = false
        statusMessage = "Ready"
        recordingWindow.hide()
        levelMonitor.reset()
    }

    // MARK: - Processing Pipeline

    private func processRecording(url: URL, duration: TimeInterval, contextText: String?, activeApp: String?) async {
        defer {
            audioRecorder.cleanupTempFile(url: url)
        }

        let pipelineStart = CFAbsoluteTimeGetCurrent()

        do {
            let styleTone = detectStyleTone(appName: activeApp)
            let rawText: String
            let cleanedText: String

            // Step 1: Transcribe audio with selected engine
            statusMessage = "Transcribing..."
            let transcribeStart = CFAbsoluteTimeGetCurrent()
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
            case .appleSpeech:
                rawText = try await appleSpeechClient.transcribe(fileURL: url)
            }
            let transcribeMs = Int((CFAbsoluteTimeGetCurrent() - transcribeStart) * 1000)
            let sttModel: String = {
                switch config.transcriptionEngine {
                case .whisperMini: return "gpt-4o-mini-transcribe"
                case .whisperFull: return "gpt-4o-transcribe"
                case .deepgram: return "nova-2"
                case .appleSpeech: return "apple-speech"
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
                // Force AI cleanup when translation is enabled (programmatic cleaner can't translate)
                let needsAICleanup = config.useAICleanup || config.translationEnabled
                let cleanupStart = CFAbsoluteTimeGetCurrent()
                let cleanupMethod: String
                if needsAICleanup {
                    statusMessage = config.translationEnabled ? "Translating..." : "Cleaning up..."
                    cleanedText = try await claudeClient.cleanTranscription(
                        rawText,
                        dictionaryWords: config.dictionaryWords,
                        styleTone: styleTone,
                        activeApp: activeApp,
                        contextText: config.contextAwareness ? contextText : nil,
                        smartFormatting: config.smartFormatting,
                        translationEnabled: config.translationEnabled,
                        targetLanguage: config.targetLanguage,
                        recentCorrections: config.recentCorrections
                    )
                    cleanupMethod = "claude"
                } else {
                    cleanedText = ProgrammaticCleaner.clean(rawText, styleTone: styleTone)
                    cleanupMethod = "programmatic"
                }
                let cleanupMs = Int((CFAbsoluteTimeGetCurrent() - cleanupStart) * 1000)
                let cleanupModel = cleanupMethod == "claude" ? "claude-haiku-4-5" : "none"

            guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                isProcessing = false
                statusMessage = "Ready"
                lastError = "No speech detected."
                PipelineLogger.shared.log(engine: config.transcriptionEngine.displayName, sttModel: sttModel, transcribeMs: transcribeMs, cleanupMs: cleanupMs, cleanupMethod: cleanupMethod, cleanupModel: cleanupModel, audioDuration: duration, wordCount: 0, error: "Empty after cleanup")
                return
            }

            // Step 3: Save
            let transcript = Transcript(
                originalText: rawText,
                cleanedText: cleanedText,
                durationSeconds: duration
            )
            try database.save(transcript)

            // Step 5: Inject text (APPENDS at cursor)
            if config.autoInjectText {
                TextInjector.inject(text: cleanedText)

                // Step 6: Start tracking corrections (self-learning feedback loop)
                correctionTracker.startTracking(transcript: transcript, injectedText: cleanedText)
            }

            let totalMs = Int((CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000)
            let wordCount = cleanedText.split(separator: " ").count
            PipelineLogger.shared.log(engine: config.transcriptionEngine.displayName, sttModel: sttModel, transcribeMs: transcribeMs, cleanupMs: cleanupMs, cleanupMethod: cleanupMethod, cleanupModel: cleanupModel, audioDuration: duration, wordCount: wordCount, totalMs: totalMs)

            lastTranscript = transcript
            isProcessing = false
            statusMessage = "Ready"
            lastError = nil
            computeTotalWords()
            computeTotalRecordingTime()

            if config.useHapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }

        } catch {
            let totalMs = Int((CFAbsoluteTimeGetCurrent() - pipelineStart) * 1000)
            PipelineLogger.shared.log(engine: config.transcriptionEngine.displayName, sttModel: "", transcribeMs: 0, cleanupMs: 0, cleanupMethod: "error", audioDuration: duration, wordCount: 0, totalMs: totalMs, error: error.localizedDescription)
            isProcessing = false
            statusMessage = "Error"
            lastError = error.localizedDescription
        }
    }

    /// Detect which style tone to use based on the active app
    private func detectStyleTone(appName: String?) -> StyleTone {
        guard let app = appName?.lowercased() else { return config.styleTone(for: .other) }

        if app.contains("message") || app.contains("whatsapp") || app.contains("telegram") || app.contains("signal") {
            return config.styleTone(for: .personalMessages)
        } else if app.contains("slack") || app.contains("teams") || app.contains("discord") {
            return config.styleTone(for: .workMessages)
        } else if app.contains("mail") || app.contains("outlook") || app.contains("gmail") || app.contains("spark") {
            return config.styleTone(for: .email)
        }
        return config.styleTone(for: .other)
    }

    // MARK: - Navigation

    var hotkeyDescription: String {
        HotKeyManager.keyName(for: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
    }

    func showTranscriptHistory() {
        selectedTab = .history
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = MainAppWindow(appState: self)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showOnboardingWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("onboarding")
            window.title = "Setup Verbalize"
            window.center()
            // Prevent dealloc on close — same fix as MainAppWindow to avoid
            // SIGSEGV in OnboardingView destroy during CoreAnimation flush
            window.isReleasedWhenClosed = false
            window.delegate = WindowDelegate.shared
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    config: config,
                    hotkeyManager: hotkeyManager,
                    onComplete: { [weak self] in
                        // Hide instead of close to avoid dealloc crash
                        window.orderOut(nil)
                        self?.hotkeyManager.startListening()
                        self?.showMainWindow()
                    }
                )
            )
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Lifecycle

    func appDidFinishLaunching() {
        guard !hasLaunched else { return }
        hasLaunched = true

        if !config.hasCompletedOnboarding {
            showOnboardingWindow()
        } else {
            hotkeyManager.startListening()
            // Show main window on launch so the app feels like it opened
            showMainWindow()
        }
    }

    func appWillTerminate() {
        hotkeyManager.stopListening()
        if isRecording {
            cancelRecording()
        }
    }
}

// MARK: - Main App Window (prevents crash on close)

/// Custom NSWindow subclass that hides instead of closing to prevent
/// the SIGSEGV crash in _NSWindowTransformAnimation dealloc.
final class MainAppWindow: NSWindow {
    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.identifier = NSUserInterfaceItemIdentifier("main")
        self.title = "Verbalize"
        self.center()
        self.minSize = NSSize(width: 700, height: 450)
        self.titlebarAppearsTransparent = false
        self.titleVisibility = .visible
        self.isOpaque = true
        self.backgroundColor = .windowBackgroundColor
        self.contentView = NSHostingView(rootView: MainWindowView(appState: appState))
        self.isReleasedWhenClosed = false
        self.delegate = WindowDelegate.shared
    }
}

/// Window delegate that hides the main window instead of closing it,
/// preventing the animation dealloc crash.
final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let windowId = sender.identifier?.rawValue
        if windowId == "main" || windowId == "onboarding" {
            sender.orderOut(nil)
            // Revert to accessory if no visible windows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let hasVisibleWindows = NSApp.windows.contains {
                    $0.isVisible && $0.identifier?.rawValue != "com.apple.menuExtra" && !($0 is NSPanel)
                }
                if !hasVisibleWindows {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
            return false
        }
        return true
    }
}

// MARK: - App Entry Point

@main
struct VerbalizeApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {}

    var body: some Scene {
        // Menu bar icon (always present)
        MenuBarExtra {
            MenuBarView(appState: appState)
                .onAppear {
                    // Trigger launch logic on first menu bar appearance
                    // (also handles the case where AppDelegate fires before appState is ready)
                    if !appState.hasLaunched {
                        appState.appDidFinishLaunching()
                    }
                }
        } label: {
            Label {
                Text("Verbalize")
            } icon: {
                if appState.isRecording || appState.isProcessing {
                    Image(systemName: menuBarIcon)
                } else {
                    menuBarCustomIcon
                }
            }
            .onAppear {
                // The label's onAppear fires at app launch (unlike the content's onAppear
                // which only fires when the user clicks the menu bar icon)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !appState.hasLaunched {
                        appState.appDidFinishLaunching()
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if appState.isRecording { return "mic.fill" }
        return "ellipsis.circle"
    }

    private var menuBarCustomIcon: some View {
        Group {
            if let nsImage = Self.loadMenuBarIcon() {
                Image(nsImage: nsImage)
            } else {
                Image(systemName: "mic")
            }
        }
    }

    private static func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 22, height: 22)
        return image
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as regular app so the window is cmd-tab-able on launch.
        // We switch to accessory mode only when all windows are closed.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When dock icon is clicked and no windows visible, show main window
        if !flag {
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
        return true
    }
}

extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
}
