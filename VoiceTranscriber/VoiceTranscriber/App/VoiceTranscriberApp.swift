import SwiftUI
import Combine

// MARK: - App State (Orchestrator)

/// Central state object that coordinates recording, API calls, text injection, and UI.
@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var lastTranscript: Transcript?
    @Published var lastError: String?
    @Published var statusMessage: String = "Ready"

    let audioRecorder = AudioRecorder()
    let levelMonitor: AudioLevelMonitor
    let hotkeyManager = HotKeyManager()
    let database = TranscriptDatabase.shared
    let config = ConfigManager.shared

    private let whisperClient = WhisperClient()
    private let claudeClient = ClaudeClient()
    private let recordingWindow = RecordingWindowController()
    private var currentRecordingURL: URL?
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.levelMonitor = AudioLevelMonitor(recorder: audioRecorder)
        setupHotkeyCallbacks()
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

        // Check microphone permission
        AudioRecorder.requestMicrophonePermission { [weak self] granted in
            guard granted else {
                self?.lastError = "Microphone permission denied. Please grant access in System Settings > Privacy & Security > Microphone."
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                do {
                    let url = try self.audioRecorder.startRecording()
                    self.currentRecordingURL = url
                    self.isRecording = true
                    self.lastError = nil
                    self.statusMessage = "Recording..."

                    // Show floating recording window
                    self.recordingWindow.show(recorder: self.audioRecorder, levelMonitor: self.levelMonitor)

                    // Haptic feedback
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

        // Haptic feedback
        if config.useHapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }

        // Process in background
        Task {
            await processRecording(url: result.url, duration: result.duration)
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

    private func processRecording(url: URL, duration: TimeInterval) async {
        defer {
            audioRecorder.cleanupTempFile(url: url)
        }

        do {
            // Step 1: Transcribe with Whisper
            statusMessage = "Transcribing..."
            let rawText = try await whisperClient.transcribe(fileURL: url)

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                await MainActor.run {
                    isProcessing = false
                    statusMessage = "Ready"
                    lastError = "No speech detected in recording."
                }
                return
            }

            // Step 2: Clean with Claude
            statusMessage = "Cleaning up..."
            let cleanedText = try await claudeClient.cleanTranscription(rawText)

            // Step 3: Save to database
            let transcript = Transcript(
                originalText: rawText,
                cleanedText: cleanedText,
                durationSeconds: duration
            )
            try database.save(transcript)

            // Step 4: Inject text if enabled
            if config.autoInjectText {
                TextInjector.inject(text: cleanedText)
            }

            await MainActor.run {
                lastTranscript = transcript
                isProcessing = false
                statusMessage = "Ready"
                lastError = nil
            }

            // Success haptic
            if config.useHapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }

        } catch {
            await MainActor.run {
                isProcessing = false
                statusMessage = "Error"
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Navigation

    var hotkeyDescription: String {
        HotKeyManager.keyName(for: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
    }

    func showTranscriptHistory() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "history" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("history")
            window.title = "Transcript History"
            window.center()
            window.contentView = NSHostingView(rootView: TranscriptHistoryView(database: database))
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.title = "VoiceTranscriber Settings"
            window.center()
            window.contentView = NSHostingView(
                rootView: SettingsView(config: config, hotkeyManager: hotkeyManager)
            )
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Lifecycle

    func appDidFinishLaunching() {
        hotkeyManager.startListening()

        if !config.hasCompletedOnboarding {
            showSettings()
            config.hasCompletedOnboarding = true
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
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Menu bar extra — the primary UI
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

        // Settings window
        Settings {
            SettingsView(config: appState.config, hotkeyManager: appState.hotkeyManager)
        }
    }

    private var menuBarIcon: String {
        if appState.isRecording { return "mic.fill" }
        if appState.isProcessing { return "ellipsis.circle" }
        return "mic"
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState?.appDidFinishLaunching()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.appWillTerminate()
    }
}
