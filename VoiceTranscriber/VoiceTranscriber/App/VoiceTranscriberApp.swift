import SwiftUI
import AppKit
import Combine

// MARK: - Navigation

enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case style = "Style"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
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

    let audioRecorder = AudioRecorder()
    let levelMonitor: AudioLevelMonitor
    let hotkeyManager = HotKeyManager()
    let database = TranscriptDatabase.shared
    let config = ConfigManager.shared

    private let whisperClient = WhisperClient()
    private let claudeClient = ClaudeClient()
    private let recordingWindow = RecordingWindowController()
    private var cancellables = Set<AnyCancellable>()
    /// Captured before recording starts for context-aware transcription
    private var capturedContext: String?
    private var capturedAppName: String?

    init() {
        self.levelMonitor = AudioLevelMonitor(recorder: audioRecorder)
        setupHotkeyCallbacks()
        computeTotalWords()
    }

    private func computeTotalWords() {
        totalWordsTranscribed = database.transcripts.reduce(0) {
            $0 + $1.cleanedText.split(separator: " ").count
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

        do {
            // Step 1: Transcribe with Whisper (+ dictionary words for accuracy)
            statusMessage = "Transcribing..."
            let rawText = try await whisperClient.transcribe(
                fileURL: url,
                dictionaryWords: config.dictionaryWords,
                contextHint: contextText
            )

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                isProcessing = false
                statusMessage = "Ready"
                lastError = "No speech detected."
                return
            }

            // Step 2: Determine style based on active app
            let styleTone = detectStyleTone(appName: activeApp)

            // Step 3: Clean with Claude (dictionary, style, context, smart formatting)
            statusMessage = "Cleaning up..."
            let cleanedText = try await claudeClient.cleanTranscription(
                rawText,
                dictionaryWords: config.dictionaryWords,
                styleTone: styleTone,
                activeApp: activeApp,
                contextText: config.contextAwareness ? contextText : nil,
                smartFormatting: config.smartFormatting
            )

            // Step 4: Save
            let transcript = Transcript(
                originalText: rawText,
                cleanedText: cleanedText,
                durationSeconds: duration
            )
            try database.save(transcript)

            // Step 5: Inject text (APPENDS at cursor)
            if config.autoInjectText {
                TextInjector.inject(text: cleanedText)
            }

            lastTranscript = transcript
            isProcessing = false
            statusMessage = "Ready"
            lastError = nil
            computeTotalWords()

            if config.useHapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }

        } catch {
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
        selectedTab = .home
        showMainWindow()
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("main")
            window.title = "VoiceTranscriber"
            window.center()
            window.minSize = NSSize(width: 700, height: 450)
            window.contentView = NSHostingView(rootView: MainWindowView(appState: self))
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showOnboardingWindow() {
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
            window.title = "Setup VoiceTranscriber"
            window.center()
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    config: config,
                    hotkeyManager: hotkeyManager,
                    onComplete: { [weak self] in
                        window.close()
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
        if !config.hasCompletedOnboarding {
            showOnboardingWindow()
        } else {
            hotkeyManager.startListening()
        }
    }

    func appWillTerminate() {
        hotkeyManager.stopListening()
        if isRecording {
            cancelRecording()
        }
    }
}

// MARK: - App Entry Point

@main
struct VoiceTranscriberApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar icon (always present)
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label {
                Text("VoiceTranscriber")
            } icon: {
                Image(systemName: menuBarIcon)
            }
        }
        .menuBarExtraStyle(.window)

        // Main app window
        WindowGroup("VoiceTranscriber") {
            MainWindowView(appState: appState)
                .frame(minWidth: 700, minHeight: 450)
                .onAppear {
                    appState.appDidFinishLaunching()
                }
        }
        .defaultSize(width: 900, height: 600)
    }

    private var menuBarIcon: String {
        if appState.isRecording { return "mic.fill" }
        if appState.isProcessing { return "ellipsis.circle" }
        return "mic"
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show in dock so users can Cmd+Tab
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Re-open main window when dock icon is clicked and all windows are closed
            for window in NSApp.windows {
                if window.identifier?.rawValue == "main" {
                    window.makeKeyAndOrderFront(nil)
                    return true
                }
            }
        }
        return true
    }
}
