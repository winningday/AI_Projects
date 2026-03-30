import SwiftUI
import AVFoundation

/// In-app settings view (shown in the main window sidebar).
struct AppSettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var config: ConfigManager
    @ObservedObject var hotkeyManager: HotKeyManager
    @ObservedObject var database: TranscriptDatabase

    @State private var openAIKey = ""
    @State private var claudeKey = ""
    @State private var deepgramKey = ""
    @State private var showOpenAIKey = false
    @State private var showClaudeKey = false
    @State private var showDeepgramKey = false
    @State private var isCapturingHotkey = false
    @State private var showSavedAlert = false
    @State private var showDeleteConfirm = false
    @State private var micGranted = false
    @State private var axGranted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold))

                // General section
                SettingsSection(title: "General", icon: "gear") {
                    Toggle("Launch at login", isOn: $config.launchAtLogin)
                    Toggle("Haptic feedback", isOn: $config.useHapticFeedback)
                    Toggle("Sound effects", isOn: $config.playSoundEffects)
                    Toggle("Auto-inject text into active field", isOn: $config.autoInjectText)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Your typing speed")
                                .font(.system(size: 13))
                            Spacer()
                            HStack(spacing: 4) {
                                TextField("", value: $config.typingSpeed, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("WPM")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Text("Used to compare voice dictation speed against typing in the Stats dashboard. Average is 40 WPM.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Hotkey section
                SettingsSection(title: "Hotkey", icon: "keyboard") {
                    HStack {
                        Text("Current hotkey:")
                            .font(.system(size: 13))
                        KeyBadge(text: HotKeyManager.keyName(for: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers))
                        Spacer()
                    }

                    if isCapturingHotkey {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Press any key or key combination...")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        Button("Cancel") {
                            isCapturingHotkey = false
                            hotkeyManager.stopCapturingHotkey()
                        }
                        .controlSize(.small)
                    } else {
                        Button("Change Hotkey") {
                            isCapturingHotkey = true
                            hotkeyManager.startCapturingHotkey()
                            hotkeyManager.onHotkeyCaptured = { keyCode, modifiers in
                                hotkeyManager.updateHotkey(keyCode: keyCode, modifiers: modifiers)
                                isCapturingHotkey = false
                                // Restart listening with new hotkey
                                hotkeyManager.stopListening()
                                hotkeyManager.startListening()
                            }
                        }
                    }

                    Text("The hotkey display throughout the app updates automatically when changed.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Translation section
                SettingsSection(title: "Translation", icon: "globe") {
                    Toggle(isOn: $config.translationEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Translation mode")
                            Text("Automatically translate transcribed speech to your target language")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if config.translationEnabled {
                        HStack {
                            Text("Output language:")
                                .font(.system(size: 13))
                            Picker("", selection: $config.targetLanguage) {
                                ForEach(ConfigManager.supportedLanguages, id: \.code) { lang in
                                    Text(lang.name).tag(lang.code)
                                }
                            }
                            .frame(width: 180)
                        }

                        Text("Speak in any language — the output will always be in \(ConfigManager.supportedLanguages.first(where: { $0.code == config.targetLanguage })?.name ?? config.targetLanguage). Works with Chinese, Spanish, French, Arabic, and more.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Text("Tip: You can also toggle translation quickly from the menu bar icon.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .italic()
                }

                // Transcription Engine section
                SettingsSection(title: "Transcription Engine", icon: "waveform") {
                    Picker("Engine", selection: $config.transcriptionEngine) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.displayName)
                                Text(engine.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .tag(engine)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    if config.transcriptionEngine.includesCleanup {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                                .font(.system(size: 11))
                            Text("This engine transcribes and cleans in a single step — all your settings (dictionary, style, corrections) are applied automatically.")
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                        }
                    }
                }

                // Text Cleanup section
                SettingsSection(title: "Text Cleanup", icon: "sparkles") {
                    Toggle(isOn: $config.useAICleanup) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use AI cleanup (Claude)")
                            Text("Sends transcript to Claude for advanced cleanup. May occasionally modify your words.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if !config.useAICleanup {
                        Text("Using fast programmatic cleanup: capitalizes sentences, adds punctuation, removes filler words (um, uh), and fixes stutters. Your words are never changed.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text("AI cleanup uses Claude Haiku for intelligent formatting, self-correction handling, and context-aware styling. Requires a Claude API key.")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }

                    Divider()

                    Toggle("Smart formatting (code, technical terms)", isOn: $config.smartFormatting)
                    Toggle("Auto-add corrected words to dictionary", isOn: $config.autoAddToDictionary)
                    Toggle("Context awareness (read surrounding text for accuracy)", isOn: $config.contextAwareness)

                    Text("Context awareness reads a small amount of text from the active field to help spell names correctly and understand topic context.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }

                // Permissions section
                SettingsSection(title: "Permissions", icon: "lock.shield") {
                    PermissionItem(
                        icon: "mic.fill", color: .red,
                        title: "Microphone", description: "Record speech",
                        isGranted: micGranted,
                        action: {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async { micGranted = granted }
                            }
                        }
                    )
                    PermissionItem(
                        icon: "hand.raised.fill", color: .blue,
                        title: "Accessibility", description: "Global hotkey & text injection",
                        isGranted: axGranted,
                        action: {
                            // Open directly to the Accessibility pane
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    )

                    if !axGranted {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("After enabling in System Settings, click Refresh below.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Note: You may need to remove and re-add the app if you rebuilt it.")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }

                    Button("Refresh Permissions") {
                        refreshPermissions()
                        // Also restart hotkey listening if accessibility was just granted
                        if axGranted {
                            hotkeyManager.stopListening()
                            hotkeyManager.startListening()
                        }
                    }
                    .controlSize(.small)
                }

                // API Keys section
                SettingsSection(title: "API Keys", icon: "key") {
                    if config.transcriptionEngine == .appleSpeech && !config.useAICleanup && !config.translationEnabled {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("No API keys needed — using fully on-device pipeline!")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                        }
                        .padding(.bottom, 4)
                    }

                    APIKeyField(
                        label: "OpenAI",
                        placeholder: "sk-proj-...",
                        key: $openAIKey,
                        showKey: $showOpenAIKey,
                        isSaved: !(config.openAIAPIKey ?? "").isEmpty,
                        link: ("platform.openai.com", "https://platform.openai.com/api-keys")
                    )
                    APIKeyField(
                        label: "Anthropic Claude",
                        placeholder: "sk-ant-api03-...",
                        key: $claudeKey,
                        showKey: $showClaudeKey,
                        isSaved: !(config.claudeAPIKey ?? "").isEmpty,
                        link: ("console.anthropic.com", "https://console.anthropic.com/settings/keys")
                    )
                    APIKeyField(
                        label: "Deepgram",
                        placeholder: "dg-...",
                        key: $deepgramKey,
                        showKey: $showDeepgramKey,
                        isSaved: !(config.deepgramAPIKey ?? "").isEmpty,
                        link: ("console.deepgram.com", "https://console.deepgram.com")
                    )

                    HStack {
                        Button("Save API Keys") {
                            config.openAIAPIKey = openAIKey.isEmpty ? nil : openAIKey
                            config.claudeAPIKey = claudeKey.isEmpty ? nil : claudeKey
                            config.deepgramAPIKey = deepgramKey.isEmpty ? nil : deepgramKey
                            showSavedAlert = true
                        }
                        .buttonStyle(.borderedProminent)

                        if config.hasAPIKeys {
                            Label("Keys saved", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Data & Privacy section
                SettingsSection(title: "Data & Privacy", icon: "hand.raised") {
                    Toggle(isOn: $config.privacyMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Privacy mode")
                            Text("Do not use transcription data for model training")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    LabeledContent("Transcripts stored") {
                        Text("\(database.transcripts.count) entries")
                            .foregroundColor(.secondary)
                    }

                    LabeledContent("Storage location") {
                        Button("Show in Finder") {
                            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                            let appDir = appSupport.appendingPathComponent("Verbalize")
                            NSWorkspace.shared.open(appDir)
                        }
                        .controlSize(.small)
                    }

                    Button("Delete All History & Activity", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .controlSize(.small)
                }

                // Uninstall section
                SettingsSection(title: "Clean Uninstall", icon: "trash") {
                    Text("To completely remove Verbalize and all its data:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        UninstallStep(number: 1, text: "Quit Verbalize")
                        UninstallStep(number: 2, text: "Delete from /Applications")
                        UninstallStep(number: 3, text: "Remove data folder (button below)")
                        UninstallStep(number: 4, text: "Remove from System Settings > Privacy > Accessibility")
                        UninstallStep(number: 5, text: "Relaunch System Settings if it feels slow")
                    }

                    HStack(spacing: 12) {
                        Button("Open Data Folder") {
                            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                            let appDir = appSupport.appendingPathComponent("Verbalize")
                            NSWorkspace.shared.open(appDir)
                        }
                        .controlSize(.small)

                        Button("Open Accessibility Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }

                // About section
                SettingsSection(title: "About", icon: "info.circle") {
                    LabeledContent("Version") {
                        Text("1.2.0")
                            .foregroundColor(.secondary)
                    }
                    LabeledContent("") {
                        Text("Verbalize — Voice-to-text with translation")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            openAIKey = config.openAIAPIKey ?? ""
            claudeKey = config.claudeAPIKey ?? ""
            deepgramKey = config.deepgramAPIKey ?? ""
            refreshPermissions()
        }
        .alert("API Keys Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        } message: {
            Text("Your API keys have been saved.")
        }
        .alert("Delete All History?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                try? database.deleteAll()
            }
        } message: {
            Text("This will permanently delete all transcripts and activity history. This cannot be undone.")
        }
    }

    private func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        axGranted = AXIsProcessTrusted()
    }
}

// MARK: - Uninstall Step

private struct UninstallStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number).")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
    }
}

// MARK: - Permission Item

private struct PermissionItem: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .foregroundColor(isGranted ? .green : color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(description).font(.system(size: 11)).foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Granted").font(.system(size: 11, weight: .medium)).foregroundColor(.green)
            } else {
                Button("Grant", action: action)
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - API Key Field

private struct APIKeyField: View {
    let label: String
    let placeholder: String
    @Binding var key: String
    @Binding var showKey: Bool
    let isSaved: Bool
    let link: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }

            HStack {
                if showKey {
                    TextField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    SecureField(placeholder, text: $key)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { showKey.toggle() }) {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
            }

            Link("Get a key at \(link.0)", destination: URL(string: link.1)!)
                .font(.system(size: 11))
        }
    }
}
