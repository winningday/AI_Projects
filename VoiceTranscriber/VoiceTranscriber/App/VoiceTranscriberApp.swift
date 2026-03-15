import SwiftUI
import AppKit
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
    @Published var showOnboarding = false

    let audioRecorder = AudioRecorder()
    let levelMonitor: AudioLevelMonitor
    let hotkeyManager = HotKeyManager()
    let database = TranscriptDatabase.shared
    let config = ConfigManager.shared

    private let whisperClient = WhisperClient()
    private let claudeClient = ClaudeClient()
    private let recordingWindow = RecordingWindowController()
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
                    let url = try self.audioRecorder.startRecording()
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
            statusMessage = "Transcribing..."
            let rawText = try await whisperClient.transcribe(fileURL: url)

            guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                isProcessing = false
                statusMessage = "Ready"
                lastError = "No speech detected."
                return
            }

            statusMessage = "Cleaning up..."
            let cleanedText = try await claudeClient.cleanTranscription(rawText)

            let transcript = Transcript(
                originalText: rawText,
                cleanedText: cleanedText,
                durationSeconds: duration
            )
            try database.save(transcript)

            if config.autoInjectText {
                TextInjector.inject(text: cleanedText)
            }

            lastTranscript = transcript
            isProcessing = false
            statusMessage = "Ready"
            lastError = nil

            if config.useHapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }

        } catch {
            isProcessing = false
            statusMessage = "Error"
            lastError = error.localizedDescription
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
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppState handles its own lifecycle via onAppear
    }
}
